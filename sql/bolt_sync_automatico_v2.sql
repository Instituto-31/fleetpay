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

-- ════════════════════════════════════════════════════════════════════
-- 2026-11-16 — Token interno de cron (deixa de ser precisa a service_role key)
-- O segredo 'fleetpay_service_role_key' no Vault passa a guardar um token
-- 'fpcron_…' gerado na base de dados. A Edge Function bolt-earnings corre com
-- verify_jwt=false e valida o token via fp_verificar_cron_token (só service_role).
-- pg_net com timeout de 120 s (a Bolt demora > 5 s).
-- ════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_id uuid; v_tok text;
BEGIN
  v_tok := 'fpcron_' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'fleetpay_service_role_key';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(v_tok, 'fleetpay_service_role_key', 'token interno cron FleetPay (não é a service_role)');
  ELSE
    PERFORM vault.update_secret(v_id, v_tok, 'fleetpay_service_role_key', 'token interno cron FleetPay (não é a service_role)');
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fp_verificar_cron_token(p_token text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM vault.decrypted_secrets
    WHERE name = 'fleetpay_service_role_key' AND length(coalesce(p_token, '')) >= 40 AND decrypted_secret = p_token);
$$;
REVOKE ALL ON FUNCTION public.fp_verificar_cron_token(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fp_verificar_cron_token(text) TO service_role;

CREATE OR REPLACE FUNCTION public.fp_chamar_bolt_sync(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_key text; v_url text := 'https://udqddasbfqbeeaxtnsoj.supabase.co'; v_resp_id bigint;
BEGIN
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'fleetpay_service_role_key' LIMIT 1;
  IF v_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'vault: fleetpay_service_role_key em falta'); END IF;
  SELECT net.http_post(
    url := v_url || '/functions/v1/bolt-earnings',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := jsonb_build_object('empresa_id', p_empresa_id, 'months', 2),
    timeout_milliseconds := 120000
  ) INTO v_resp_id;
  RETURN jsonb_build_object('ok', true, 'request_id', v_resp_id);
END $function$;
