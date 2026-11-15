// FleetPay — Edge Function: bolt-sync  (Bolt Fleet API v2)
// Sincroniza motoristas e viaturas a partir da Bolt Fleet API v2.
// Também devolve os motoristas online (estado + posição) para o mapa ao vivo.
//
// Fluxo (sync):
//   1. Verifica auth (operador/superadmin)
//   2. Lê empresa.bolt_client_id, bolt_client_secret, bolt_company_id
//   3. OAuth2 client_credentials → access_token (10 min)
//   4. Chama getDrivers + getVehicles (paginado, sem janelas de datas — v2 devolve o estado actual)
//   5. Upsert em motoristas + veiculos
//   6. Atualiza empresa.bolt_last_sync_at + summary
//
// Fluxo (online):  body { empresa_id?, online: true }
//   → getOnlineDrivers → [{ uuid, nome, estado, lat, lng, matricula, since, motorista_id }]
//
// Match strategy:
//   • Driver  → bolt_uuid (v2) → bolt_driver_id (v1, se for o mesmo uuid) → email → telefone
//   • Vehicle → bolt_uuid (v2) → bolt_car_id (v1) → matrícula
//   • Sem match → cria registo novo (origem Bolt)
//   bolt_driver_id / bolt_car_id só são preenchidos se estiverem vazios (compatibilidade com
//   bolt-earnings, que ainda usa a v1 e faz match por driver_uuid).
//
// Endpoints (Bolt Fleet Integration v2):
//   POST https://oidc.bolt.eu/token
//   POST https://node.bolt.eu/fleet-integration-gateway-v2/fleetIntegration/v2/getDrivers
//   POST https://node.bolt.eu/fleet-integration-gateway-v2/fleetIntegration/v2/getVehicles
//   POST https://node.bolt.eu/fleet-integration-gateway-v2/fleetIntegration/v2/getOnlineDrivers
//
// Resposta Bolt: sempre HTTP 200 com { code, message, data } — code 0 = OK.
// Excepção: 429 TOO_MANY_REQUESTS (code 1005).

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const BOLT_AUTH_URL = 'https://oidc.bolt.eu/token';
const BOLT_API_BASE = 'https://node.bolt.eu/fleet-integration-gateway-v2/fleetIntegration/v2';
const PAGE = 1000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
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
  let data: any;
  try { data = JSON.parse(txt); } catch { throw new Error(`Bolt OAuth resposta inválida: ${txt}`); }
  if (!data.access_token) throw new Error(`Bolt OAuth sem access_token: ${txt}`);
  return data.access_token;
}

async function boltCall(endpoint: string, token: string, body: unknown): Promise<any> {
  let r = await fetch(`${BOLT_API_BASE}/${endpoint}`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (r.status === 429) {
    const wait = Number(r.headers.get('retry-after') || 2);
    await new Promise(res => setTimeout(res, Math.min(wait, 10) * 1000));
    r = await fetch(`${BOLT_API_BASE}/${endpoint}`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  }
  const txt = await r.text();
  if (!r.ok) throw new Error(`Bolt ${endpoint} HTTP ${r.status}: ${txt.slice(0, 300)}`);
  let resp: any;
  try { resp = JSON.parse(txt); } catch { throw new Error(`Bolt ${endpoint} JSON inválido: ${txt.slice(0, 300)}`); }
  if (resp?.code !== 0) {
    const val = resp?.validation_errors?.map((v: any) => `${v.property ?? v.field ?? '?'}: ${v.error ?? v.message ?? ''}`).join('; ');
    const dica = resp?.code === 498811 ? ' — a chave não está ativa na API v2: cria uma chave em fleets.bolt.eu → Definições → Chaves API da frota (v2) e grava-a em Configurações → Chave API v2' : '';
    throw new Error(`Bolt ${endpoint}: ${resp?.message || 'erro'} (code ${resp?.code})${resp?.error_hint ? ' hint=' + resp.error_hint : ''}${val ? ' | ' + val : ''}${dica}`);
  }
  return resp.data ?? {};
}

async function fetchAllPages(endpoint: string, key: string, token: string, base: Record<string, unknown>): Promise<any[]> {
  const list: any[] = [];
  let offset = 0;
  while (true) {
    const data = await boltCall(endpoint, token, { ...base, limit: PAGE, offset });
    const batch: any[] = data?.[key] || [];
    list.push(...batch);
    const total = Number(data?.total_rows ?? data?.total ?? NaN);
    offset += batch.length;
    if (batch.length < PAGE) break;
    if (!Number.isNaN(total) && offset >= total) break;
    if (offset > 50000) break;
  }
  return list;
}

function nomeDriver(d: any): string {
  return `${d.first_name || ''} ${d.last_name || ''}`.trim() || d.display_name || `Bolt ${d.uuid}`;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  try {
    // 1) Auth
    const authHeader = req.headers.get('authorization');
    if (!authHeader) return json({ error: 'Sem autorização' }, 401);
    const jwt = authHeader.replace('Bearer ', '');
    const { data: { user }, error: errUser } = await supabase.auth.getUser(jwt);
    if (errUser || !user) return json({ error: 'Sessão inválida' }, 401);

    const { data: perfil } = await supabase.from('perfis').select('role, empresa_id').eq('id', user.id).single();
    if (!perfil || !['operador', 'superadmin'].includes(perfil.role)) return json({ error: 'Sem permissão' }, 403);

    const body = await req.json().catch(() => ({}));
    const empresaId = perfil.role === 'superadmin' && body.empresa_id ? body.empresa_id : perfil.empresa_id;
    const modoOnline = body.online === true;

    // 2) Credenciais
    const { data: emp, error: errEmp } = await supabase
      .from('empresas')
      .select('id, nome, bolt_client_id, bolt_client_secret, bolt_company_id, bolt_client_id_v2, bolt_client_secret_v2')
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

    // 3) Token — chave v2 se existir, senão a v1
    const clientId = emp.bolt_client_id_v2 || emp.bolt_client_id;
    const clientSecret = emp.bolt_client_id_v2 ? (emp.bolt_client_secret_v2 || '') : emp.bolt_client_secret;
    if (!clientSecret) throw new Error('Chave Bolt v2: falta o Client Secret (Configurações → Integração Bolt API)');
    let accessToken: string;
    try {
      accessToken = await getBoltToken(clientId, clientSecret);
    } catch (e) {
      throw new Error(`${(e as Error).message} — confirma as credenciais ${emp.bolt_client_id_v2 ? 'v2' : 'v1'} em Configurações`);
    }

    // ── MODO ONLINE (mapa ao vivo) ──
    if (modoOnline) {
      const data = await boltCall('getOnlineDrivers', accessToken, { company_id: companyId });
      const online: any[] = data?.drivers || [];
      const uuids = online.map(d => d.uuid).filter(Boolean);
      const porUuid = new Map<string, { id: string; nome: string }>();
      if (uuids.length) {
        const { data: mots } = await supabase
          .from('motoristas').select('id, nome, bolt_uuid, bolt_driver_id')
          .eq('empresa_id', empresaId)
          .or(`bolt_uuid.in.(${uuids.join(',')}),bolt_driver_id.in.(${uuids.join(',')})`);
        (mots || []).forEach(m => {
          if (m.bolt_uuid) porUuid.set(m.bolt_uuid, { id: m.id, nome: m.nome });
          if (m.bolt_driver_id && !porUuid.has(m.bolt_driver_id)) porUuid.set(m.bolt_driver_id, { id: m.id, nome: m.nome });
        });
      }
      const lista = online.map(d => {
        const m = porUuid.get(d.uuid);
        const ordem = d.current_order || null;
        return {
          uuid: d.uuid,
          motorista_id: m?.id || null,
          nome: m?.nome || nomeDriver(d),
          estado: String(d.current_state?.code || '').toLowerCase() || null,   // waiting | on_ride | on_break
          desde: d.current_state?.changed_at || null,
          lat: d.current_location?.lat ?? null,
          lng: d.current_location?.lng ?? null,
          matricula: d.vehicle?.registration_number || null,
          em_corrida: !!ordem,
        };
      });
      return json({ ok: true, online: lista, total: lista.length, obtido_em: new Date().toISOString() });
    }

    // ── MODO SYNC ──
    const [boltDrivers, boltVehicles] = await Promise.all([
      fetchAllPages('getDrivers', 'drivers', accessToken, { company_id: companyId }),
      fetchAllPages('getVehicles', 'vehicles', accessToken, { company_id: companyId })
        .catch(e => { console.error('[bolt-sync] getVehicles falhou:', (e as Error).message); return [] as any[]; }),
    ]);
    if (boltDrivers[0]) console.log('[bolt-sync] DRIVER #0:', JSON.stringify(boltDrivers[0]).slice(0, 600));
    if (boltVehicles[0]) console.log('[bolt-sync] VEHICLE #0:', JSON.stringify(boltVehicles[0]).slice(0, 600));

    const summary = {
      api: 'v2',
      drivers_received: boltDrivers.length,
      drivers_created: 0, drivers_updated: 0, drivers_skipped: 0,
      drivers_uuid_diferente_v1: 0,
      vehicles_received: boltVehicles.length,
      vehicles_created: 0, vehicles_updated: 0, vehicles_skipped: 0,
      errors: [] as string[],
    };
    const now = new Date().toISOString();

    // 4) Motoristas
    for (const bd of boltDrivers) {
      try {
        const uuid = bd.uuid ? String(bd.uuid) : '';
        if (!uuid) { summary.drivers_skipped++; summary.errors.push(`driver sem uuid: ${JSON.stringify(bd).slice(0, 120)}`); continue; }
        const nome = nomeDriver(bd);
        const email = bd.email || null;
        const phone = bd.phone || null;
        const status = bd.status || null;                 // active | suspended | deactivated

        let existing: { id: string; bolt_driver_id: string | null } | null = null;
        const sel = () => supabase.from('motoristas').select('id, bolt_driver_id').eq('empresa_id', empresaId);
        ({ data: existing } = await sel().eq('bolt_uuid', uuid).maybeSingle());
        if (!existing) ({ data: existing } = await sel().eq('bolt_driver_id', uuid).maybeSingle());
        if (!existing && email) ({ data: existing } = await sel().ilike('email', email).maybeSingle());
        if (!existing && phone) ({ data: existing } = await sel().eq('telefone', phone).maybeSingle());

        const payload: any = {
          bolt_uuid: uuid,
          bolt_partner_uuid: bd.partner_uuid || null,
          bolt_synced_at: now,
          bolt_status: status,
          bolt_nome: nome,
          bolt_online: !!bd.is_online,
        };
        if (email) payload.email = email;
        if (phone) payload.telefone = phone;

        if (existing) {
          if (!existing.bolt_driver_id) payload.bolt_driver_id = uuid;
          else if (existing.bolt_driver_id !== uuid) summary.drivers_uuid_diferente_v1++;
          const { error: upErr } = await supabase.from('motoristas').update(payload).eq('id', existing.id);
          if (upErr) { summary.errors.push(`driver ${uuid} update: ${upErr.message}`); summary.drivers_skipped++; }
          else summary.drivers_updated++;
        } else {
          payload.empresa_id = empresaId;
          payload.nome = nome;
          payload.bolt_driver_id = uuid;
          payload.ativo = status !== 'deactivated';
          const { error: insErr } = await supabase.from('motoristas').insert(payload);
          if (insErr) { summary.errors.push(`driver ${uuid} insert: ${insErr.message}`); summary.drivers_skipped++; }
          else summary.drivers_created++;
        }
      } catch (e) {
        summary.errors.push(`driver ${bd?.uuid || '?'}: ${(e as Error).message}`);
        summary.drivers_skipped++;
      }
    }

    // 5) Viaturas
    for (const bv of boltVehicles) {
      try {
        const uuid = bv.uuid ? String(bv.uuid) : '';
        if (!uuid) { summary.vehicles_skipped++; summary.errors.push(`vehicle sem uuid: ${JSON.stringify(bv).slice(0, 120)}`); continue; }
        const matricula = String(bv.normalised_registration_number || bv.registration_number || '').toUpperCase().replace(/\s+/g, '');
        const matriculaFmt = matricula.length === 6 ? `${matricula.slice(0, 2)}-${matricula.slice(2, 4)}-${matricula.slice(4)}` : (bv.registration_number || matricula).toUpperCase();

        let existing: { id: string; bolt_car_id: string | null } | null = null;
        const sel = () => supabase.from('veiculos').select('id, bolt_car_id').eq('empresa_id', empresaId);
        ({ data: existing } = await sel().eq('bolt_uuid', uuid).maybeSingle());
        if (!existing) ({ data: existing } = await sel().eq('bolt_car_id', uuid).maybeSingle());
        if (!existing && matricula) {
          // matrícula pode estar guardada com ou sem hífens → comparar normalizado
          const { data: byPlate } = await supabase.from('veiculos').select('id, bolt_car_id, matricula').eq('empresa_id', empresaId);
          existing = (byPlate || []).find((v: any) => String(v.matricula || '').toUpperCase().replace(/[^A-Z0-9]/g, '') === matricula) || null;
        }

        const payload: any = {
          bolt_uuid: uuid,
          bolt_synced_at: now,
          bolt_status: bv.status || null,
        };
        if (matricula && !existing) payload.matricula = matriculaFmt;
        if (bv.make) payload.marca = bv.make;
        if (bv.model) payload.modelo = bv.model;
        if (bv.year) payload.ano = Number(bv.year) || null;
        if (bv.vin) payload.numero_quadro = bv.vin;

        if (existing) {
          if (!existing.bolt_car_id) payload.bolt_car_id = uuid;
          const { error: upErr } = await supabase.from('veiculos').update(payload).eq('id', existing.id);
          if (upErr) { summary.errors.push(`vehicle ${uuid} update: ${upErr.message}`); summary.vehicles_skipped++; }
          else summary.vehicles_updated++;
        } else {
          payload.empresa_id = empresaId;
          payload.bolt_car_id = uuid;
          payload.estado = bv.status === 'deactivated' ? 'inativo' : 'ativo';
          const { error: insErr } = await supabase.from('veiculos').insert(payload);
          if (insErr) { summary.errors.push(`vehicle ${uuid} insert: ${insErr.message}`); summary.vehicles_skipped++; }
          else summary.vehicles_created++;
        }
      } catch (e) {
        summary.errors.push(`vehicle ${bv?.uuid || '?'}: ${(e as Error).message}`);
        summary.vehicles_skipped++;
      }
    }

    // 6) Empresa
    await supabase.from('empresas').update({ bolt_last_sync_at: now, bolt_last_sync_summary: summary }).eq('id', empresaId);

    return json({ ok: true, summary });
  } catch (e) {
    console.error('[bolt-sync]', e);
    return json({ error: (e as Error).message }, 500);
  }
});
