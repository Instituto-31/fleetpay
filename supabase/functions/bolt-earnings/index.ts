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
//   bolt_liquido        = sum(order_price.net_earnings)        (com comissão FleetPay)
//   bolt_gorjetas       = sum(order_price.tip)                 (SEM comissão)
//   bolt_cancelamentos  = sum(order_price.cancellation_fee)    (com comissão)
//   bolt_reembolsos     = sum(order_price.toll_fee + ...)      (SEM comissão)
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
  if (!r.ok) throw new
