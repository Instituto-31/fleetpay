-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Sincronização automática Bolt (pagamentos) — correção
-- ════════════════════════════════════════════════════════════════════
-- A versão anterior lia a chave de current_setting('app.settings.*'), que nunca
-- foi configurado → o cron "sucedia" mas não fazia nada.
-- Agora a chave vem do Supabase Vault (secret 'fleetpay_service_role_key').
--
-- PASSO ÚNICO A FAZER NO SQL EDITOR (uma vez; substituir o valor):
--   SELECT vault.create_secret('<SERVICE_ROLE_KEY>', 'fleetpay_service_role_key');
-- (Supabase → Project Settings → API → service_role. Nunca partilhar.)
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fp_chamar_bolt_sync(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_key text; v_url text := 'https://udqddasbfqbeeaxtnsoj.supabase.co'; v_resp_id bigint;
BEGIN
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'fleetpay_service_role_key' LIMIT 1;
  IF v_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'vault: fleetpay_service_role_key em falta');
  END IF;
  SELECT net.http_post(
    url := v_url || '/functions/v1/bolt-earnings',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := jsonb_build_object('empresa_id', p_empresa_id, 'months', 2)
  ) INTO v_resp_id;
  RETURN jsonb_build_object('ok', true, 'request_id', v_resp_id);
END $$;

-- Segunda 05:00 (fecho da semana) + todos os dias 06:00 (semana em curso)
SELECT cron.unschedule('fleetpay-bolt-sync-horario');
SELECT cron.schedule('fleetpay-bolt-pagamentos-segunda', '0 5 * * 1', $$ SELECT fp_sync_bolt_todas_empresas(); $$);
SELECT cron.schedule('fleetpay-bolt-pagamentos-diario',  '0 6 * * 2-7', $$ SELECT fp_sync_bolt_todas_empresas(); $$);
