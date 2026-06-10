-- =====================================================
-- FleetPay — Bolt sync automático horário
-- Acumula dados continuamente sem operador precisar clicar.
-- =====================================================

-- 1) Tabela de logs (para ver o que aconteceu e debugar)
CREATE TABLE IF NOT EXISTS bolt_sync_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  empresa_id UUID REFERENCES empresas(id) ON DELETE CASCADE,
  iniciado_em TIMESTAMPTZ DEFAULT NOW(),
  duracao_ms INT,
  ok BOOLEAN,
  pagamentos_criados INT DEFAULT 0,
  pagamentos_actualizados INT DEFAULT 0,
  orders_received INT DEFAULT 0,
  erro TEXT,
  origem TEXT DEFAULT 'cron'
);
CREATE INDEX IF NOT EXISTS idx_bolt_sync_empresa ON bolt_sync_logs(empresa_id, iniciado_em DESC);

-- 2) Função SQL que chama a Edge Function bolt-earnings
--    via http extension (precisa de pg_net habilitado, vem por defeito em Supabase)
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION fp_chamar_bolt_sync(p_empresa_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service_role text;
  v_supabase_url text;
  v_resp_id bigint;
BEGIN
  -- Lê secrets (configurados no Supabase)
  v_service_role := current_setting('app.settings.service_role_key', true);
  v_supabase_url := current_setting('app.settings.supabase_url', true);

  -- Se não estão definidos, falha graceful
  IF v_service_role IS NULL OR v_supabase_url IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'secrets nao configurados — usa Supabase Dashboard cron');
  END IF;

  -- Chama Edge Function (async, devolve request_id)
  SELECT net.http_post(
    url := v_supabase_url || '/functions/v1/bolt-earnings',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role
    ),
    body := jsonb_build_object('empresa_id', p_empresa_id, 'months', 2)
  ) INTO v_resp_id;

  RETURN jsonb_build_object('ok', true, 'request_id', v_resp_id);
END;
$$;

-- 3) Função que sincroniza TODAS as empresas com Bolt configurado
CREATE OR REPLACE FUNCTION fp_sync_bolt_todas_empresas()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_empresa record;
  v_count int := 0;
BEGIN
  FOR v_empresa IN
    SELECT id, nome FROM empresas
    WHERE bolt_client_id IS NOT NULL
      AND bolt_client_secret IS NOT NULL
      AND bolt_company_id IS NOT NULL
      AND demo IS DISTINCT FROM TRUE
  LOOP
    PERFORM fp_chamar_bolt_sync(v_empresa.id);
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'empresas_sincronizadas', v_count);
END;
$$;

-- 4) Cron job horário (00:05, 01:05, etc — fora dos minutos cheios para evitar congestão)
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;

  PERFORM cron.unschedule('fleetpay-bolt-sync-horario')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fleetpay-bolt-sync-horario');

  PERFORM cron.schedule(
    'fleetpay-bolt-sync-horario',
    '5 * * * *',  -- minuto 5 de cada hora
    $cmd$ SELECT fp_sync_bolt_todas_empresas(); $cmd$
  );

  RAISE NOTICE 'pg_cron agendado: fleetpay-bolt-sync-horario às :05 de cada hora';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron erro: %', SQLERRM;
  RAISE NOTICE 'Alternativa: cria cron externo a chamar SELECT fp_sync_bolt_todas_empresas();';
END $$;

-- 5) Verifica
SELECT
  (SELECT COUNT(*) FROM empresas WHERE bolt_client_id IS NOT NULL) AS empresas_com_bolt,
  (SELECT jobname FROM cron.job WHERE jobname = 'fleetpay-bolt-sync-horario') AS cron_activo;
