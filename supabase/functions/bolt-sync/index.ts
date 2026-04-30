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

    // 4) OAuth Bolt
    const accessToken = await getBoltToken(emp.bolt_client_id, emp.bolt_client_secret);

    // 5) Get drivers from Bolt
    // Note: payload exato pode variar. Tentamos com company_ids[]; se 400, tentamos sem.
    const driversBody: any = {};
    if (emp.bolt_company_id) driversBody.company_ids = [Number(emp.bolt_company_id) || emp.bolt_company_id];
    let driversResp: any;
    try {
      driversResp = await boltCall('getDriversForApiCalls', accessToken, driversBody);
    } catch (e1) {
      // fallback: sem company_ids
      try { driversResp = await boltCall('getDriversForApiCalls', accessToken, {}); }
      catch (e2) { throw new Error(`getDrivers falhou: ${(e1 as Error).message} | fallback: ${(e2 as Error).message}`); }
    }
    const boltDrivers: any[] = driversResp?.data?.drivers || driversResp?.drivers || driversResp?.data || [];

    // 6) Get vehicles from Bolt
    const vehiclesBody: any = {};
    if (emp.bolt_company_id) vehiclesBody.company_ids = [Number(emp.bolt_company_id) || emp.bolt_company_id];
    let vehiclesResp: any;
    try {
      vehiclesResp = await boltCall('getVehiclesForApiCalls', accessToken, vehiclesBody);
    } catch (e1) {
      try { vehiclesResp = await boltCall('getVehiclesForApiCalls', accessToken, {}); }
      catch (e2) { /* veículos é opcional — não bloqueia se falhar */ vehiclesResp = { data: { vehicles: [] } }; }
    }
    const boltVehicles: any[] = vehiclesResp?.data?.vehicles || vehiclesResp?.vehicles || vehiclesResp?.data || [];

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
