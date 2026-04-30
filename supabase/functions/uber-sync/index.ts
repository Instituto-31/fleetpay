// FleetPay — Edge Function: uber-sync
// Sincroniza motoristas e viaturas a partir da Uber Vehicle Suppliers API.
//
// Fluxo:
//   1. Verifica auth (operador/superadmin)
//   2. Lê empresa.uber_client_id, uber_client_secret, uber_org_id
//   3. OAuth2 client_credentials → access_token
//   4. GET /v1/vehicle-suppliers/drivers?org_id=X → paginado
//   5. GET /v2/vehicle-suppliers/vehicles?org_id=X → paginado
//   6. Upsert em motoristas / veiculos (match por uber_driver_id / uber_vehicle_id;
//      se não existir, fallback por email/telefone/matricula; se ainda não existir CRIA)
//   7. Atualiza empresa.uber_last_sync_at + summary
//
// Endpoints (https://developer.uber.com/docs/vehicles):
//   - POST https://login.uber.com/oauth/v2/token
//   - GET  https://api.uber.com/v1/vehicle-suppliers/drivers
//   - GET  https://api.uber.com/v2/vehicle-suppliers/vehicles

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const UBER_OAUTH_URL = 'https://login.uber.com/oauth/v2/token';
const UBER_API_BASE = 'https://api.uber.com';
// Scopes prováveis para Vehicle Suppliers API. Tentamos vários no fallback.
const SCOPE_CANDIDATES = [
  'vehicle_suppliers.drivers.read vehicle_suppliers.vehicles.read',
  'supplier.performance-data',
  'vehicle.suppliers',
  'fleet.read',
];

async function getUberToken(clientId: string, clientSecret: string): Promise<string> {
  // Tenta vários scopes — Uber rejeita scope errado com 400, mas podemos descobrir o certo
  const errors: string[] = [];
  for (const scope of SCOPE_CANDIDATES) {
    const body = new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: 'client_credentials',
      scope,
    });
    const r = await fetch(UBER_OAUTH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    });
    const txt = await r.text();
    if (r.ok) {
      try {
        const j = JSON.parse(txt);
        if (j.access_token) {
          console.log(`[uber-sync] OAuth OK com scope: "${scope}"`);
          return j.access_token;
        }
      } catch {/* continua */}
    }
    errors.push(`scope "${scope}": ${r.status} ${txt.slice(0, 200)}`);
  }
  throw new Error(`Uber OAuth falhou todas as tentativas:\n${errors.join('\n')}`);
}

async function uberGet(path: string, params: Record<string, string>, token: string): Promise<any> {
  const url = new URL(UBER_API_BASE + path);
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  const r = await fetch(url.toString(), {
    headers: { 'Authorization': `Bearer ${token}`, 'Accept': 'application/json' },
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`Uber GET ${path} ${r.status}: ${txt.slice(0, 300)}`);
  try { return JSON.parse(txt); } catch { throw new Error(`Uber GET ${path} JSON inválido: ${txt.slice(0, 200)}`); }
}

async function fetchAllPages(path: string, orgId: string, token: string, listKey: string): Promise<any[]> {
  const all: any[] = [];
  let pageToken: string | undefined;
  let safety = 0;
  while (safety++ < 100) {
    const params: Record<string, string> = { org_id: orgId, page_size: '100' };
    if (pageToken) params.page_token = pageToken;
    const resp = await uberGet(path, params, token);
    const list: any[] = resp?.[listKey] || resp?.data?.[listKey] || resp?.results || [];
    all.push(...list);
    pageToken = resp?.next_page_token || resp?.page_token || resp?.cursor;
    if (!pageToken || list.length === 0) break;
  }
  return all;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // 1) Auth
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return new Response(JSON.stringify({ error: 'Auth em falta' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    const { data: { user } } = await supabase.auth.getUser(authHeader.replace('Bearer ', ''));
    if (!user) return new Response(JSON.stringify({ error: 'Sessão inválida' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

    const { data: perfil } = await supabase.from('perfis').select('role, empresa_id').eq('id', user.id).single();
    if (!perfil || !['operador', 'superadmin'].includes(perfil.role)) {
      return new Response(JSON.stringify({ error: 'Sem permissão' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    const { empresa_id: bodyEmpresaId } = await req.json().catch(() => ({}));
    const empresaId = perfil.role === 'superadmin' && bodyEmpresaId ? bodyEmpresaId : perfil.empresa_id;

    // 2) Empresa creds
    const { data: emp, error: errEmp } = await supabase
      .from('empresas')
      .select('id, nome, uber_client_id, uber_client_secret, uber_org_id')
      .eq('id', empresaId)
      .single();
    if (errEmp || !emp) throw new Error('Empresa não encontrada');
    if (!emp.uber_client_id || !emp.uber_client_secret) {
      throw new Error('Credenciais Uber não configuradas (Configurações → Integração Uber API)');
    }
    if (!emp.uber_org_id) {
      throw new Error('Uber Org ID em falta. Vê em developer.uber.com → Dashboard, no URL: /organization/<UUID>/applications. Cola o UUID no campo Org ID.');
    }

    // 3) OAuth
    const token = await getUberToken(emp.uber_client_id, emp.uber_client_secret);

    // 4) Get drivers
    const drivers = await fetchAllPages('/v1/vehicle-suppliers/drivers', emp.uber_org_id, token, 'drivers');
    console.log(`[uber-sync] drivers: ${drivers.length}`);

    // 5) Get vehicles
    let vehicles: any[] = [];
    try {
      vehicles = await fetchAllPages('/v2/vehicle-suppliers/vehicles', emp.uber_org_id, token, 'vehicles');
      console.log(`[uber-sync] vehicles: ${vehicles.length}`);
    } catch (e) {
      console.error('[uber-sync] vehicles falhou:', (e as Error).message);
    }

    // 6) Upsert drivers
    const summary = {
      drivers_received: drivers.length,
      drivers_new: 0,
      drivers_updated: 0,
      vehicles_received: vehicles.length,
      vehicles_new: 0,
      vehicles_updated: 0,
    };

    for (const d of drivers) {
      const uberId = d.driver_id || d.id || d.uuid;
      if (!uberId) continue;
      const nome = [d.first_name, d.last_name].filter(Boolean).join(' ') || d.name || d.full_name || 'Sem nome';
      const email = d.email || null;
      const telefone = d.phone_number || d.phone || null;

      // Match por uber_driver_id, depois email, depois telefone
      let { data: existing } = await supabase.from('motoristas').select('id').eq('empresa_id', empresaId).eq('uber_driver_id', uberId).maybeSingle();
      if (!existing && email) {
        const { data } = await supabase.from('motoristas').select('id').eq('empresa_id', empresaId).eq('email', email).maybeSingle();
        existing = data;
      }
      if (!existing && telefone) {
        const { data } = await supabase.from('motoristas').select('id').eq('empresa_id', empresaId).eq('telefone', telefone).maybeSingle();
        existing = data;
      }

      const payload: any = {
        uber_driver_id: uberId,
        uber_synced_at: new Date().toISOString(),
        ativo: true,
      };
      if (nome) payload.nome = nome;
      if (email) payload.email = email;
      if (telefone) payload.telefone = telefone;

      if (existing) {
        await supabase.from('motoristas').update(payload).eq('id', existing.id);
        summary.drivers_updated++;
      } else {
        await supabase.from('motoristas').insert({
          ...payload,
          empresa_id: empresaId,
          origem: 'uber',
        });
        summary.drivers_new++;
      }
    }

    // 7) Upsert vehicles
    for (const v of vehicles) {
      const uberId = v.vehicle_id || v.id || v.uuid;
      if (!uberId) continue;
      const matricula = v.license_plate || v.licence_plate || v.plate || null;
      const marca = v.make || v.brand || null;
      const modelo = v.model || null;
      const ano = v.year || null;

      let { data: existing } = await supabase.from('veiculos').select('id').eq('empresa_id', empresaId).eq('uber_vehicle_id', uberId).maybeSingle();
      if (!existing && matricula) {
        const { data } = await supabase.from('veiculos').select('id').eq('empresa_id', empresaId).eq('matricula', matricula).maybeSingle();
        existing = data;
      }

      const payload: any = {
        uber_vehicle_id: uberId,
        uber_synced_at: new Date().toISOString(),
      };
      if (matricula) payload.matricula = matricula;
      if (marca) payload.marca = marca;
      if (modelo) payload.modelo = modelo;
      if (ano) payload.ano = ano;

      if (existing) {
        await supabase.from('veiculos').update(payload).eq('id', existing.id);
        summary.vehicles_updated++;
      } else {
        await supabase.from('veiculos').insert({
          ...payload,
          empresa_id: empresaId,
          origem: 'uber',
        });
        summary.vehicles_new++;
      }
    }

    // 8) Update empresa stats
    await supabase.from('empresas').update({
      uber_last_sync_at: new Date().toISOString(),
      uber_last_sync_summary: summary,
      uber_api_ativo: true,
    }).eq('id', empresaId);

    return new Response(JSON.stringify({ ok: true, summary }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[uber-sync]', e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
