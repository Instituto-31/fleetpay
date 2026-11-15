// FleetPay — Edge Function: bolt-earnings
// Busca corridas finalizadas da Bolt Fleet API e agrega em pagamentos semanais.
//
// Endpoint:
//   POST https://node.bolt.eu/fleet-integration-gateway/fleetIntegration/v1/getFleetOrders
//   body: { company_ids: [<id>], start_ts, end_ts, offset, limit }
//   resp: { code: 0, data: { orders: [{ driver_uuid, order_status, order_finished_timestamp,
//                                       order_price: { ride_price, net_earnings, commission } }] } }
//
// Mapping para tabela pagamentos:
//   bolt_bruto          = sum(order_price.ride_price)
//   bolt_taxa           = sum(order_price.commission)
//   bolt_liquido        = sum(net_earnings − tip)   (com comissão FleetPay)
//   bolt_gorjetas       = sum(tip)                  (SEM comissão FleetPay)
//   NOTA: net_earnings da Bolt JÁ inclui a gorjeta (sem comissão Bolt), a taxa de
//   cancelamento (com comissão Bolt) e portagens. Por isso a gorjeta é RETIRADA do
//   líquido (não somada) e cancelamentos/portagens ficam dentro do líquido.
//   Validado contra o portal: Ganhos líquidos = (brutos − gorjeta) × (1 − comissão Bolt) + gorjeta.
//   bolt_campanha       = NÃO vem nas corridas (Bolt paga à parte) → só via CSV; a API não toca nesta coluna
//   semana_inicio       = segunda-feira da semana da corrida (Europe/Lisbon)
//   semana_fim          = domingo
//
// NOTA: a função regista nos logs ("ORDER_PRICE_KEYS") todos os campos que a Bolt
// devolve em order_price, para confirmar nomes reais (tip, cancellation_fee, toll_fee…).

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const BOLT_AUTH_URL = 'https://oidc.bolt.eu/token';
const BOLT_API_BASE = 'https://node.bolt.eu/fleet-integration-gateway/fleetIntegration/v1';

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
  const data = JSON.parse(txt);
  if (!data.access_token) throw new Error(`Bolt OAuth sem access_token: ${txt}`);
  return data.access_token;
}

async function boltCall(endpoint: string, token: string, body: any): Promise<any> {
  const r = await fetch(`${BOLT_API_BASE}/${endpoint}`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`Bolt ${endpoint} ${r.status}: ${txt}`);
  return JSON.parse(txt);
}

// Converte um instante para a data civil em Portugal (Europe/Lisbon, com hora de verão).
// Importante: uma corrida às 00:30 de segunda em Lisboa é 23:30 de domingo em UTC —
// sem isto cairia na semana anterior (o portal Bolt usa hora local).
const fmtLisboa = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit', day: '2-digit' });
function dataLisboa(d: Date): Date {
  const [y, m, dd] = fmtLisboa.format(d).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, dd));
}

// Segunda-feira da semana (em data civil de Lisboa) que contém o instante dado.
function mondayOf(instante: Date): Date {
  const d = dataLisboa(instante);
  const day = d.getUTCDay(); // 0=Sun ... 6=Sat
  const diff = day === 0 ? -6 : 1 - day;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + diff));
}

function ymd(d: Date): string {
  return d.toISOString().slice(0, 10);
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  try {
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

    const { data: perfil } = await supabase
      .from('perfis').select('role, empresa_id').eq('id', user.id).single();
    if (!perfil || !['operador', 'superadmin'].includes(perfil.role)) {
      return new Response(JSON.stringify({ error: 'Sem permissão' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const body = await req.json().catch(() => ({}));
    const empresaId = perfil.role === 'superadmin' && body.empresa_id ? body.empresa_id : perfil.empresa_id;
    const monthsBack = Math.max(1, Math.min(6, body.months || 2));  // default 2 meses

    const { data: emp, error: errEmp } = await supabase
      .from('empresas')
      .select('id, nome, bolt_client_id, bolt_client_secret, bolt_company_id, iva_uber_pct, bolt_iva_pct')
      .eq('id', empresaId).single();
    if (errEmp || !emp) throw new Error('Empresa não encontrada');
    if (!emp.bolt_client_id || !emp.bolt_client_secret) {
      throw new Error('Credenciais Bolt não configuradas');
    }
    const companyId = Number(emp.bolt_company_id);
    if (!companyId || Number.isNaN(companyId)) {
      throw new Error(`Bolt Company ID inválido: "${emp.bolt_company_id}"`);
    }

    const accessToken = await getBoltToken(emp.bolt_client_id, emp.bolt_client_secret);

    // Janelas de 30 dias (Bolt limita)
    const WINDOW_DAYS = 30;
    const windowMs = WINDOW_DAYS * 24 * 3600 * 1000;
    const numWindows = Math.ceil((monthsBack * 30) / WINDOW_DAYS);
    const nowMs = Date.now();

    function extractOrders(resp: any): any[] {
      return resp?.data?.orders || resp?.orders || resp?.data?.list || resp?.list
        || (Array.isArray(resp?.data) ? resp.data : []) || [];
    }

    async function fetchOrdersWindow(startMs: number, endMs: number): Promise<{ list: any[]; sample: any }> {
      const list: any[] = [];
      let offset = 0;
      const startSec = Math.floor(startMs / 1000);
      const endSec = Math.floor(endMs / 1000);
      let sample: any = null;
      const MAX_PER_PAGE = 1000;
      while (true) {
        const body: any = {
          company_ids: [companyId],   // ARRAY (diferente dos getDrivers/getVehicles)
          start_ts: startSec,
          end_ts: endSec,
          offset,
          limit: MAX_PER_PAGE,
        };
        const resp = await boltCall('getFleetOrders', accessToken, body);
        if (offset === 0 && !sample) sample = resp;
        if (resp?.code && resp.code !== 0 && resp.code !== 200) {
          const errMsg = `${resp.message || 'erro'} (code ${resp.code})`;
          const validation = resp.validation_errors?.map((v: any) => `${v.property}: ${v.error}`).join('; ') || '';
          throw new Error(`Bolt getFleetOrders: ${errMsg}${validation ? ' | ' + validation : ''}`);
        }
        const batch = extractOrders(resp);
        list.push(...batch);
        if (batch.length < MAX_PER_PAGE) break;
        offset += batch.length;
        if (offset > 100000) break;
      }
      return { list, sample };
    }

    // Lança 6 janelas em paralelo
    const t0 = Date.now();
    const winPromises: Promise<{ index: number; list: any[]; sample: any; err?: string }>[] = [];
    for (let i = 0; i < numWindows; i++) {
      const endMs = nowMs - i * windowMs;
      const startMs = endMs - windowMs;
      winPromises.push(
        fetchOrdersWindow(startMs, endMs)
          .then(r => ({ index: i, list: r.list, sample: r.sample }))
          .catch(e => ({ index: i, list: [], sample: null, err: (e as Error).message }))
      );
    }
    const winResults = await Promise.all(winPromises);
    console.log(`[bolt-earnings] ${numWindows} janelas em ${Date.now() - t0}ms`);

    const seenOrders = new Set<string>();
    const allOrders: any[] = [];
    let firstSample: any = null;
    for (const r of winResults) {
      if (r.err) {
        console.error(`[bolt-earnings] janela ${r.index + 1}: ${r.err}`);
        continue;
      }
      if (r.index === 0) firstSample = r.sample;
      for (const o of r.list) {
        const id = String(o.order_id || o.id || o.uuid || o.order_uuid || JSON.stringify(o).slice(0, 50));
        if (!seenOrders.has(id)) {
          seenOrders.add(id);
          allOrders.push(o);
        }
      }
      console.log(`[bolt-earnings] janela ${r.index + 1}: +${r.list.length}`);
    }

    if (allOrders.length === 0) {
      console.log('[bolt-earnings] 0 orders. Raw sample:', JSON.stringify(firstSample || {}).slice(0, 1500));
    } else {
      console.log('[bolt-earnings] ORDER #0:', JSON.stringify(allOrders[0]).slice(0, 1500));
    }

    // Buscar motoristas da empresa (uma vez) para mapear bolt_driver_id -> motorista
    const { data: mots } = await supabase
      .from('motoristas').select('id, bolt_driver_id, nome, comissao_pct')
      .eq('empresa_id', empresaId);
    const motByBolt = new Map<string, { id: string; nome: string; comissao_pct: number | null }>();
    (mots || []).forEach(m => { if (m.bolt_driver_id) motByBolt.set(String(m.bolt_driver_id), { id: m.id, nome: m.nome, comissao_pct: m.comissao_pct }); });

    // Agregar orders finalizadas por motorista + semana
    type Agg = { bruto: number; liquido: number; taxa: number; gorjetas: number; cancelamentos: number; reembolsos: number; orders: number };
    const buckets = new Map<string, { driverUuid: string; semanaInicio: string; semanaFim: string; agg: Agg }>();
    let skippedNotFinished = 0;
    let skippedNoTimestamp = 0;
    let skippedNoDriver = 0;
    let skippedNoPrice = 0;
    const statusBreakdown: Record<string, number> = {};

    // Diagnóstico: que campos existem realmente em order_price (todas as orders)
    const priceKeys = new Set<string>();
    for (const o of allOrders) Object.keys(o.order_price || {}).forEach(k => priceKeys.add(k));
    console.log('[bolt-earnings] ORDER_PRICE_KEYS:', Array.from(priceKeys).sort().join(', ') || '(nenhum)');

    const num = (v: any) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

    for (const o of allOrders) {
      const status = String(o.order_status || 'unknown').toLowerCase();
      statusBreakdown[status] = (statusBreakdown[status] || 0) + 1;
      // Conta qualquer corrida que tenha gerado ganhos (finalizada OU cancelada com taxa paga,
      // seja qual for o nome do estado). Sem ganhos → ignorada.
      const price0 = o.order_price || {};
      const net0 = num(price0.net_earnings ?? price0.net);
      const tip0 = num(price0.tip ?? price0.tips ?? price0.tip_amount);
      const isFinished = status === 'finished' || status === 'completed';
      if (!isFinished && net0 === 0 && tip0 === 0) { skippedNotFinished++; continue; }

      const tsRaw = o.order_finished_timestamp ?? o.finished_at ?? o.finished_timestamp ?? o.order_created_timestamp;
      if (!tsRaw) { skippedNoTimestamp++; continue; }
      const tsMs = Number(tsRaw) < 1e12 ? Number(tsRaw) * 1000 : Number(tsRaw);
      const orderDate = new Date(tsMs);
      const mon = mondayOf(orderDate);
      const sun = new Date(Date.UTC(mon.getUTCFullYear(), mon.getUTCMonth(), mon.getUTCDate() + 6));
      const semanaInicio = ymd(mon);
      const semanaFim = ymd(sun);

      const driverUuid = o.driver_uuid || o.driver_id || o.driverId;
      if (!driverUuid) { skippedNoDriver++; continue; }

      const price = o.order_price || {};
      const ride = num(price.ride_price ?? price.gross ?? price.amount);
      const net = num(price.net_earnings ?? price.net);
      const comm = num(price.commission ?? price.fee);
      const tip = num(price.tip ?? price.tips ?? price.tip_amount);
      if (!ride && !net && !tip) { skippedNoPrice++; continue; }

      const key = `${driverUuid}|${semanaInicio}`;
      const b = buckets.get(key) || { driverUuid: String(driverUuid), semanaInicio, semanaFim, agg: { bruto: 0, liquido: 0, taxa: 0, gorjetas: 0, cancelamentos: 0, reembolsos: 0, orders: 0 } };
      b.agg.bruto += ride;
      b.agg.liquido += (net - tip);   // net_earnings já inclui a gorjeta → separar
      b.agg.taxa += comm;
      b.agg.gorjetas += tip;
      b.agg.orders += 1;
      buckets.set(key, b);
    }

    // Upsert na tabela pagamentos
    const summary = {
      orders_received: allOrders.length,
      orders_aggregated: Array.from(buckets.values()).reduce((s, b) => s + b.agg.orders, 0),
      skipped_not_finished: skippedNotFinished,
      skipped_no_timestamp: skippedNoTimestamp,
      skipped_no_driver: skippedNoDriver,
      skipped_no_price: skippedNoPrice,
      status_breakdown: statusBreakdown,
      buckets: buckets.size,
      order_price_keys: Array.from(priceKeys).sort(),
      total_gorjetas: 0,
      total_cancelamentos: 0,
      total_reembolsos: 0,
      pagamentos_created: 0,
      pagamentos_updated: 0,
      pagamentos_skipped_no_motorista: 0,
      errors: [] as string[],
    };

    const round2 = (n: number) => Math.round(n * 100) / 100;

    for (const b of buckets.values()) {
      const m = motByBolt.get(b.driverUuid);
      if (!m) {
        summary.pagamentos_skipped_no_motorista++;
        summary.errors.push(`semana ${b.semanaInicio}: driver_uuid ${b.driverUuid} sem motorista no FleetPay`);
        continue;
      }
      // O trigger fp_pagamento_auto_calcular calcula bolt_iva, iva_cobrar e valor_final
      // automaticamente (gorjetas e reembolsos entram sem comissão). Não calculamos aqui.
      const bolt_liquido = round2(b.agg.liquido);
      const bolt_gorjetas = round2(b.agg.gorjetas);
      const bolt_cancelamentos = round2(b.agg.cancelamentos);
      const bolt_reembolsos = round2(b.agg.reembolsos);
      summary.total_gorjetas = round2(summary.total_gorjetas + bolt_gorjetas);
      summary.total_cancelamentos = round2(summary.total_cancelamentos + bolt_cancelamentos);
      summary.total_reembolsos = round2(summary.total_reembolsos + bolt_reembolsos);

      // Procurar pagamento existente
      const { data: existing, error: selErr } = await supabase
        .from('pagamentos')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('motorista_id', m.id)
        .eq('semana_inicio', b.semanaInicio)
        .maybeSingle();
      if (selErr) {
        summary.errors.push(`select ${b.semanaInicio}/${m.nome}: ${selErr.message}`);
        continue;
      }

      const payload: any = {
        bolt_liquido,
        bolt_gorjetas,
        bolt_cancelamentos: 0,   // já incluído em bolt_liquido (Bolt comissiona-o como corrida)
        bolt_reembolsos: 0,      // portagens já incluídas em bolt_liquido
        // bolt_campanha fica de fora de propósito: não vem na API, só no CSV
        origem: 'api',
      };

      if (existing) {
        const { error: upErr } = await supabase.from('pagamentos').update(payload).eq('id', existing.id);
        if (upErr) {
          summary.errors.push(`update ${b.semanaInicio}/${m.nome}: ${upErr.message}`);
        } else {
          summary.pagamentos_updated++;
        }
      } else {
        payload.empresa_id = empresaId;
        payload.motorista_id = m.id;
        payload.semana_inicio = b.semanaInicio;
        payload.semana_fim = b.semanaFim;
        payload.estado = 'pendente';
        const { error: insErr } = await supabase.from('pagamentos').insert(payload);
        if (insErr) {
          summary.errors.push(`insert ${b.semanaInicio}/${m.nome}: ${insErr.message} | payload: ${JSON.stringify(payload).slice(0, 200)}`);
        } else {
          summary.pagamentos_created++;
        }
      }
    }

    return new Response(JSON.stringify({ ok: true, summary }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[bolt-earnings]', e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
