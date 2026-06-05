-- =====================================================
-- FleetPay — Reset automático diário da empresa demo
-- Corre todos os dias às 04:00 (UTC). Apaga dados sujos
-- e re-cria seed limpo (5 motoristas, 5 viaturas, 30 pagamentos).
-- =====================================================

-- ID da empresa demo
-- deadbeef-0000-0000-0000-000000000001

-- 1) Função idempotente que faz o reset completo
CREATE OR REPLACE FUNCTION reset_demo_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_empresa uuid := 'deadbeef-0000-0000-0000-000000000001'::uuid;
  v_motoristas uuid[] := ARRAY[
    'deadbeef-1000-0000-0000-000000000001'::uuid,
    'deadbeef-1000-0000-0000-000000000002'::uuid,
    'deadbeef-1000-0000-0000-000000000003'::uuid,
    'deadbeef-1000-0000-0000-000000000004'::uuid,
    'deadbeef-1000-0000-0000-000000000005'::uuid
  ];
  v_mot uuid; v_idx int; v_off int; v_sem date; v_fim date;
  v_uber numeric; v_bolt numeric; v_iva numeric; v_slot numeric; v_alug numeric;
  v_prio numeric; v_vv numeric; v_final numeric; v_estado text;
  v_inicio timestamptz := NOW();
BEGIN
  -- A) LIMPAR (preserva empresa + motoristas + viaturas — só apaga dados transaccionais)
  DELETE FROM pagamentos WHERE empresa_id = v_empresa;

  -- Apaga eventuais dados acessórios (best effort, ignora se tabela não existe)
  BEGIN DELETE FROM notificacoes_enviadas WHERE empresa_id = v_empresa; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM mensagens WHERE empresa_id = v_empresa; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM documentos WHERE empresa_id = v_empresa; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM contratos WHERE motorista_id = ANY(v_motoristas); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM termos_aceitacoes WHERE motorista_id = ANY(v_motoristas); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM registos_conducao WHERE empresa_id = v_empresa; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM prio_carregamentos WHERE motorista_id = ANY(v_motoristas); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM viaverde_movimentos WHERE motorista_id = ANY(v_motoristas); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM compliance_checklists WHERE motorista_id = ANY(v_motoristas); EXCEPTION WHEN OTHERS THEN NULL; END;

  -- B) GARANTIR motoristas (UPSERT)
  INSERT INTO motoristas (id, empresa_id, nome, email, telefone, whatsapp, nif, ativo, criado_em)
  VALUES
    (v_motoristas[1], v_empresa, 'Joana Ferreira', 'joana@demo.fleetpay.pt', '+351 911 111 111','351911111111','210000001',true, NOW() - INTERVAL '120 days'),
    (v_motoristas[2], v_empresa, 'Miguel Santos',  'miguel@demo.fleetpay.pt','+351 922 222 222','351922222222','210000002',true, NOW() - INTERVAL '90 days'),
    (v_motoristas[3], v_empresa, 'Sofia Oliveira', 'sofia@demo.fleetpay.pt', '+351 933 333 333','351933333333','210000003',true, NOW() - INTERVAL '60 days'),
    (v_motoristas[4], v_empresa, 'André Costa',    'andre@demo.fleetpay.pt', '+351 944 444 444','351944444444','210000004',true, NOW() - INTERVAL '45 days'),
    (v_motoristas[5], v_empresa, 'Beatriz Lopes',  'beatriz@demo.fleetpay.pt','+351 955 555 555','351955555555','210000005',true, NOW() - INTERVAL '30 days')
  ON CONFLICT (id) DO UPDATE SET
    nome = EXCLUDED.nome, ativo = TRUE, email = EXCLUDED.email,
    telefone = EXCLUDED.telefone, whatsapp = EXCLUDED.whatsapp;

  -- C) GARANTIR viaturas
  INSERT INTO veiculos (id, empresa_id, motorista_id, matricula, modelo, marca, ano, estado)
  VALUES
    ('deadbeef-2000-0000-0000-000000000001'::uuid, v_empresa, v_motoristas[1], 'AA-11-DM','Corolla Hybrid','Toyota',  2023, 'ativo'),
    ('deadbeef-2000-0000-0000-000000000002'::uuid, v_empresa, v_motoristas[2], 'BB-22-DM','Captur E-Tech', 'Renault', 2022, 'ativo'),
    ('deadbeef-2000-0000-0000-000000000003'::uuid, v_empresa, v_motoristas[3], 'CC-33-DM','C3 Aircross',   'Citroen', 2024, 'ativo'),
    ('deadbeef-2000-0000-0000-000000000004'::uuid, v_empresa, v_motoristas[4], 'DD-44-DM','Kona EV',       'Hyundai', 2023, 'ativo'),
    ('deadbeef-2000-0000-0000-000000000005'::uuid, v_empresa, v_motoristas[5], 'EE-55-DM','e-208',         'Peugeot', 2024, 'ativo')
  ON CONFLICT (id) DO UPDATE SET
    matricula = EXCLUDED.matricula, modelo = EXCLUDED.modelo,
    marca = EXCLUDED.marca, ano = EXCLUDED.ano, estado = 'ativo',
    motorista_id = EXCLUDED.motorista_id;

  -- D) GERAR pagamentos (30 = 5 motoristas × 6 semanas)
  FOR v_idx IN 1..array_length(v_motoristas,1) LOOP
    v_mot := v_motoristas[v_idx];
    FOR v_off IN 0..5 LOOP
      v_sem := (date_trunc('week', CURRENT_DATE)::date - (v_off * 7));
      v_fim := v_sem + 6;
      v_uber := round((400 + (v_idx*30) + random()*200)::numeric, 2);
      v_bolt := round((200 + (v_idx*20) + random()*150)::numeric, 2);
      v_iva  := round((v_uber * 0.06 + v_bolt * 0.06)::numeric, 2);
      v_slot := CASE WHEN v_idx <= 2 THEN 0 ELSE 35 END;
      v_alug := CASE WHEN v_idx >= 3 THEN 250.0 + (v_idx*10) ELSE 0 END;
      v_prio := round((20 + random()*40)::numeric, 2);
      v_vv   := round((5 + random()*20)::numeric, 2);
      v_final := round((v_uber + v_bolt - v_iva - v_slot - v_alug - v_prio - v_vv)::numeric, 2);
      v_estado := CASE WHEN v_off >= 2 THEN 'pago' ELSE 'pendente' END;
      INSERT INTO pagamentos (
        empresa_id, motorista_id, semana_inicio, semana_fim,
        uber_bruto, uber_liquido, bolt_liquido, iva_cobrar,
        slot_valor, aluguer_valor, prio_valor, viaverde_valor,
        valor_final, estado, data_pagamento, confirmado_motorista_em
      ) VALUES (
        v_empresa, v_mot, v_sem, v_fim,
        v_uber, v_uber, v_bolt, v_iva, v_slot, v_alug, v_prio, v_vv,
        v_final, v_estado,
        CASE WHEN v_estado = 'pago' THEN v_sem + INTERVAL '8 days' ELSE NULL END,
        CASE WHEN v_off >= 1 THEN v_sem + INTERVAL '6 days' ELSE NULL END
      );
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'duracao_ms', round(EXTRACT(EPOCH FROM (NOW() - v_inicio)) * 1000),
    'motoristas', 5, 'viaturas', 5, 'pagamentos', 30
  );
END;
$$;

GRANT EXECUTE ON FUNCTION reset_demo_data() TO authenticated;

-- 2) Activar pg_cron se disponível e agendar reset diário às 04:00 UTC
DO $$
BEGIN
  -- Tenta criar a extension; se já existir, ignora
  CREATE EXTENSION IF NOT EXISTS pg_cron;

  -- Apaga job anterior se existir
  PERFORM cron.unschedule('fleetpay-demo-reset-diario')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fleetpay-demo-reset-diario');

  -- Cria novo job diário às 04:00 UTC
  PERFORM cron.schedule(
    'fleetpay-demo-reset-diario',
    '0 4 * * *',  -- todos os dias às 04:00 UTC
    $cmd$ SELECT reset_demo_data(); $cmd$
  );

  RAISE NOTICE 'pg_cron agendado: fleetpay-demo-reset-diario às 04:00 UTC';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron não disponível ou erro: %', SQLERRM;
  RAISE NOTICE 'Alternativa: configura cron externo a chamar SELECT reset_demo_data();';
END $$;

-- 3) Verifica
SELECT
  (SELECT proname FROM pg_proc WHERE proname = 'reset_demo_data') AS funcao_criada,
  (SELECT jobname FROM cron.job WHERE jobname = 'fleetpay-demo-reset-diario') AS cron_job;
