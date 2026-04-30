// FleetPay — Edge Function: bolt-sync
// Sincroniza motoristas e viaturas a partir da Bolt Fleet API.
//
// Fluxo:
//   1. Verifica auth (operador/superadmin)
//   2. Lê empresa.bolt_client_id, bolt_client_secret, bolt_company_id
//   3. OAuth2 client_credentials → access_token (1h)
//   4. Chama getDriversForApiCalls + getVehiclesByCompany
//   5. Faz upsert em motoristas + veiculos (match por bolt_driver_id / bolt_car_id)
//   6. Atualiza empresa.bolt_last_sync_at + summary
//
// Match strategy:
//   • Bolt driver → match por bolt_driver_id; se não existe procura por email/phone
//   • Bolt car   → match por bolt_car_id; se não existe procura por matricula
//   • Não existe match → CRIA novo registo (com origem=bolt)
//
// Endpoints (Bolt Fleet Integration v1):
//   POST https://oidc.bolt.eu/token
//   POST https://node.bolt.eu/fleet-integration-gateway/fleetIntegration/v1/getDriversForApiCalls
//   POST https://node.bolt.eu/fleet-integration-gateway/fleetIntegration/v1/getVehiclesForApiCalls

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const BOLT_AUTH_URL = 'https://oidc.bolt.eu/token';
const BOLT_API_BASE = 'https://node.bolt.eu/fleet-integration-gateway/fleetIntegration/v1';

interface BoltAuthResponse {
  access_token: string;
  expires_in: number;
  token_type: string;
}

async function getBoltToken(clientId: string, clientSecret: string): Promise<string> {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: clientId,
    client_secret: clientSecret,
    scope: 'fleet-integration:api',
  });
  const r = await fetch(BOLT_AUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`Bolt OAuth ${r.status}: ${txt}`);
  let data: BoltAuthResponse;
  try { data = JSON.parse(txt); } catch { throw new Error(`Bolt OAuth resposta inválida: ${txt}`); }
  if (!data.access_token) throw new Error(`Bolt OAuth sem access_token: ${txt}`);
  return data.access_token;
}

async function boltCall(endpoint: string, token: string, body: any): Promise<any> {
  const r = await fetch(`${BOLT_API_BASE}/${endpoint}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`Bolt ${endpoint} ${r.status}: ${txt}`);
  try { return JSON.parse(txt); } catch { throw new Error(`Bolt ${endpoint} JSON inválido: ${txt}`); }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  try {
    // 1) Auth: precisa de JWT do operador/superadmin
    const authHeader = req.headers.get('authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Sem autorização' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: errUser } = await supabase.auth.getUser(token);
    if (errUser || !user) {
      return new Response(JSON.stringify({ error: 'Sessão inválida' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2) Get user's empresa_id
    const { data: perfil } = await supabase
      .from('perfis')
      .select('role, empresa_id')
      .eq('id', user.id)
      .single();
    if (!perfil || !['operador', 'superadmin'].includes(perfil.role)) {
      return new Response(JSON.stringify({ error: 'Sem permissão' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const { empresa_id: bodyEmpresaId } = await req.json().catch(() => ({}));
    const empresaId = perfil.role === 'superadmin' && bodyEmpresaId ? bodyEmpresaId : perfil.empresa_id;

    // 3) Fetch empresa creds
    const { data: emp, error: errEmp } = await supabase
      .from('empresas')
      .select('id, nome, bolt_client_id, bolt_client_secret, bolt_company_id')
      .eq('id', empresaId)
      .single();
    if (errEmp || !emp) throw new Error('Empresa não encontrada');
    if (!emp.bolt_client_id || !emp.bolt_client_secret) {
      throw new Error('Credenciais Bolt não configuradas (Configurações → Integração Bolt API)');
    }

    if (!emp.bolt_company_id) {
      throw new Error('Bolt Company ID em falta. Vai a Configurações → Integração Bolt API e preenche o Company ID (numérico, vê em fleets.bolt.eu → Settings ou no URL).');
    }
    const companyId = Number(emp.bolt_company_id);
    if (!companyId || Number.isNaN(companyId)) {
      throw new Error(`Bolt Company ID inválido: "${emp.bolt_company_id}" (tem que ser um número).`);
    }

    // 4) OAuth Bolt
    const accessToken = await getBoltToken(emp.bolt_client_id, emp.bolt_client_secret);

    // Time range — Bolt rejeita janelas grandes (INVALID_DATE_RANGE para 365 dias).
    // Estratégia: cobrir 6 meses com janelas de 30 dias cada (6 chamadas).
    // Deduplicação por ID garante que motoristas vistos em múltiplas janelas
    // só aparecem uma vez no resultado final.
    const nowMs = Date.now();
    const WINDOW_DAYS = 30;
    const TOTAL_MONTHS = 6;
    const NUM_WINDOWS = Math.ceil((TOTAL_MONTHS * 30) / WINDOW_DAYS);
    const windowMs = WINDOW_DAYS * 24 * 3600 * 1000;

    function extractList(resp: any, key: string): any[] {
      return resp?.data?.[key]
        || resp?.[key]
        || resp?.data?.list
        || resp?.list
        || resp?.data?.items
        || resp?.items
        || resp?.results
        || (Array.isArray(resp?.data) ? resp.data : null)
        || (Array.isArray(resp) ? resp : null)
        || [];
    }

    async function fetchOneWindow(endpoint: string, key: string, maxPerPage: number, startMs: number, endMs: number): Promise<{ list: any[], firstResp: any }> {
      const list: any[] = [];
      let firstResp: any = null;
      let offset = 0;
      let useMs = true;

      while (true) {
        const body: any = {
          company_id: companyId,
          start_ts: useMs ? startMs : Math.floor(startMs / 1000),
          end_ts: useMs ? endMs : Math.floor(endMs / 1000),
          offset,
          limit: maxPerPage,
        };
        let resp: any;
        try {
          resp = await boltCall(endpoint, accessToken, body);
        } catch (e) {
          if (offset === 0 && useMs) {
            console.log(`[bolt-sync] ${endpoint} falhou em ms, retry em segundos...`);
            useMs = false;
            continue;
          }
          throw e;
        }
        if (offset === 0 && firstResp === null) firstResp = resp;
        const batch = extractList(resp, key);
        list.push(...batch);
        if (batch.length < maxPerPage) break;
        offset += batch.length;
        if (offset > 50000) break;
      }
      return { list, firstResp };
    }

    async function fetchAllWindows(endpoint: string, key: string, maxPerPage: number, idField: string): Promise<{ list: any[], firstResp: any }> {
      // Paraleliza as 6 janelas (Promise.all) — corta tempo total para o tempo da janela mais lenta
      const t0 = Date.now();
      const promises: Promise<{ index: number; list: any[]; firstResp: any; err?: string }>[] = [];
      for (let i = 0; i < NUM_WINDOWS; i++) {
        const endMs = nowMs - i * windowMs;
        const startMs = endMs - windowMs;
        promises.push(
          fetchOneWindow(endpoint, key, maxPerPage, startMs, endMs)
            .then(r => ({ index: i, list: r.list, firstResp: r.firstResp }))
            .catch(e => ({ index: i, list: [], firstResp: null, err: (e as Error).message }))
        );
      }
      const results = await Promise.all(promises);
      console.log(`[bolt-sync] ${endpoint} ${NUM_WINDOWS} janelas em ${Date.now() - t0}ms`);

      const seen = new Set<string>();
      const merged: any[] = [];
      let firstResp: any = null;
      for (const r of results) {
        if (r.err) {
          console.error(`[bolt-sync] ${endpoint} janela ${r.index + 1}: ${r.err}`);
          continue;
        }
        if (r.index === 0) firstResp = r.firstResp;
        for (const item of r.list) {
          const id = String(item.id || item[idField] || item.uuid || JSON.stringify(item).slice(0, 50));
          if (!seen.has(id)) {
            seen.add(id);
            merged.push(item);
          }
        }
        console.log(`[bolt-sync] ${endpoint} janela ${r.index + 1}/${NUM_WINDOWS}: +${r.list.length}`);
      }
      console.log(`[bolt-sync] ${endpoint} total único: ${merged.length}`);
      return { list: merged, firstResp };
    }

    // 5) Get drivers (multi-window 6 meses)
    const driversResult = await fetchAllWindows('getDrivers', 'drivers', 1000, 'driver_id');
    const boltDrivers: any[] = driversResult.list;

    // 6) Get vehicles (multi-window 6 meses)
    let boltVehicles: any[] = [];
    let vehiclesRawSample: any = null;
    try {
      const r = await fetchAllWindows('getVehicles', 'vehicles', 100, 'car_id');
      boltVehicles = r.list;
      vehiclesRawSample = r.firstResp;
    } catch (e) {
      console.error('[bolt-sync] getVehicles falhou:', (e as Error).message);
    }

    // Log raw samples para debug
    if (boltDrivers.length === 0) {
      console.log('[bolt-sync] DRIVERS retornou 0. Raw sample:', JSON.stringify(driversResult.firstResp || {}).slice(0, 1000));
    }
    if (boltVehicles.length === 0 && vehiclesRawSample) {
      console.log('[bolt-sync] VEHICLES retornou 0. Raw sample:', JSON.stringify(vehiclesRawSample).slice(0, 1000));
    }

    // 7) Upsert drivers
    const summary = {
      drivers_received: boltDrivers.length,
      drivers_created: 0,
      drivers_updated: 0,
      drivers_skipped: 0,
      vehicles_received: boltVehicles.length,
      vehicles_created: 0,
      vehicles_updated: 0,
      vehicles_skipped: 0,
      errors: [] as string[],
    };

    const now = new Date().toISOString();

    for (const bd of boltDrivers) {
      try {
        const boltId = String(bd.id || bd.driver_id || bd.uuid || '');
        if (!boltId) { summary.drivers_skipped++; continue; }
        const nome = `${bd.first_name || ''} ${bd.last_name || ''}`.trim() || bd.name || bd.full_name || `Bolt ${boltId}`;
        const email = bd.email || null;
        const phone = bd.phone || bd.phone_number || null;
        const status = bd.status || bd.state || null;

        // Match: 1º por bolt_driver_id, 2º por email, 3º por telefone
        let { data: existing } = await supabase
          .from('motoristas')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('bolt_driver_id', boltId)
          .maybeSingle();

        if (!existing && email) {
          ({ data: existing } = await supabase
            .from('motoristas')
            .select('id')
            .eq('empresa_id', empresaId)
            .eq('email', email)
            .maybeSingle());
        }
        if (!existing && phone) {
          ({ data: existing } = await supabase
            .from('motoristas')
            .select('id')
            .eq('empresa_id', empresaId)
            .eq('telefone', phone)
            .maybeSingle());
        }

        const payload: any = {
          bolt_driver_id: boltId,
          bolt_synced_at: now,
          bolt_status: status,
        };
        if (email) payload.email = email;
        if (phone) payload.telefone = phone;

        if (existing) {
          await supabase.from('motoristas').update(payload).eq('id', existing.id);
          summary.drivers_updated++;
        } else {
          payload.empresa_id = empresaId;
          payload.nome = nome;
          payload.ativo = true;
          await supabase.from('motoristas').insert(payload);
          summary.drivers_created++;
        }
      } catch (e) {
        summary.errors.push(`driver ${bd.id || '?'}: ${(e as Error).message}`);
        summary.drivers_skipped++;
      }
    }

    // 8) Upsert vehicles
    for (const bv of boltVehicles) {
      try {
        const boltId = String(bv.id || bv.car_id || bv.vehicle_id || bv.uuid || '');
        if (!boltId) { summary.vehicles_skipped++; continue; }
        const matricula = (bv.license_plate || bv.plate || bv.registration || '').toUpperCase();
        const marca = bv.brand || bv.make || null;
        const modelo = bv.model || null;
        const ano = bv.year || bv.production_year || null;

        let { data: existing } = await supabase
          .from('veiculos')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('bolt_car_id', boltId)
          .maybeSingle();

        if (!existing && matricula) {
          ({ data: existing } = await supabase
            .from('veiculos')
            .select('id')
            .eq('empresa_id', empresaId)
            .eq('matricula', matricula)
            .maybeSingle());
        }

        const payload: any = {
          bolt_car_id: boltId,
          bolt_synced_at: now,
        };
        if (matricula) payload.matricula = matricula;
        if (marca) payload.marca = marca;
        if (modelo) payload.modelo = modelo;
        if (ano) payload.ano = ano;

        if (existing) {
          await supabase.from('veiculos').update(payload).eq('id', existing.id);
          summary.vehicles_updated++;
        } else {
          payload.empresa_id = empresaId;
          payload.estado = 'ativo';
          await supabase.from('veiculos').insert(payload);
          summary.vehicles_created++;
        }
      } catch (e) {
        summary.errors.push(`vehicle ${bv.id || '?'}: ${(e as Error).message}`);
        summary.vehicles_skipped++;
      }
    }

    // 9) Update empresa
    await supabase.from('empresas').update({
      bolt_last_sync_at: now,
      bolt_last_sync_summary: summary,
    }).eq('id', empresaId);

    return new Response(JSON.stringify({ ok: true, summary }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[bolt-sync]', e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
