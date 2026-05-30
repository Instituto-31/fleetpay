-- =====================================================
-- FleetPay — DEMO SEED
-- Empresa fictícia + 5 motoristas + viaturas + 6 semanas
-- de pagamentos com valores realistas. Idempotente.
-- =====================================================

-- IDs fixos da demo (UUIDs válidos com prefixo de:de:ad:)
-- Empresa: deadbeef-0000-0000-0000-000000000001
-- Motoristas: deadbeef-1000-0000-0000-00000000000{1..5}
-- Viaturas:   deadbeef-2000-0000-0000-00000000000{1..5}

-- 1) Coluna demo
ALTER TABLE empresas
  ADD COLUMN IF NOT EXISTS demo BOOLEAN DEFAULT FALSE;

-- 2) Empresa demo
INSERT INTO empresas (id, nome, nipc, morada, codigo_postal, licenca_tvde, telefone, email, plano, demo)
VALUES (
  'deadbeef-0000-0000-0000-000000000001',
  'FleetPay Demo',
  '999999999',
  'Avenida da Liberdade 1',
  '1250-001 Lisboa',
  'DEMO/2026',
  '+351 210 000 000',
  'demo@fleetpay.pt',
  'enterprise',
  TRUE
)
ON CONFLICT (id) DO UPDATE SET
  demo = TRUE, plano = 'enterprise', nome = 'FleetPay Demo';

-- 3) 5 motoristas
INSERT INTO motoristas (id, empresa_id, nome, email, telefone, whatsapp, nif, ativo, criado_em)
VALUES
  ('deadbeef-1000-0000-0000-000000000001','deadbeef-0000-0000-0000-000000000001','Joana Ferreira', 'joana@demo.fleetpay.pt', '+351 911 111 111','351911111111','210000001',true, NOW() - INTERVAL '120 days'),
  ('deadbeef-1000-0000-0000-000000000002','deadbeef-0000-0000-0000-000000000001','Miguel Santos',  'miguel@demo.fleetpay.pt','+351 922 222 222','351922222222','210000002',true, NOW() - INTERVAL '90 days'),
  ('deadbeef-1000-0000-0000-000000000003','deadbeef-0000-0000-0000-000000000001','Sofia Oliveira', 'sofia@demo.fleetpay.pt', '+351 933 333 333','351933333333','210000003',true, NOW() - INTERVAL '60 days'),
  ('deadbeef-1000-0000-0000-000000000004','deadbeef-0000-0000-0000-000000000001','André Costa',    'andre@demo.fleetpay.pt', '+351 944 444 444','351944444444','210000004',true, NOW() - INTERVAL '45 days'),
  ('deadbeef-1000-0000-0000-000000000005','deadbeef-0000-0000-0000-000000000001','Beatriz Lopes',  'beatriz@demo.fleetpay.pt','+351 955 555 555','351955555555','210000005',true, NOW() - INTERVAL '30 days')
ON CONFLICT (id) DO UPDATE SET nome = EXCLUDED.nome, ativo = TRUE;

-- 4) 5 viaturas (1 por motorista)
INSERT INTO veiculos (id, empresa_id, motorista_id, matricula, modelo, marca, ano, ativo)
VALUES
  ('deadbeef-2000-0000-0000-000000000001','deadbeef-0000-0000-0000-000000000001','deadbeef-1000-0000-0000-000000000001','AA-11-DM','Corolla Hybrid','Toyota',  2023, true),
  ('deadbeef-2000-0000-0000-000000000002','deadbeef-0000-0000-0000-000000000001','deadbeef-1000-0000-0000-000000000002','BB-22-DM','Captur E-Tech', 'Renault', 2022, true),
  ('deadbeef-2000-0000-0000-000000000003','deadbeef-0000-0000-0000-000000000001','deadbeef-1000-0000-0000-000000000003','CC-33-DM','C3 Aircross',   'Citroen', 2024, true),
  ('deadbeef-2000-0000-0000-000000000004','deadbeef-0000-0000-0000-000000000001','deadbeef-1000-0000-0000-000000000004','DD-44-DM','Kona EV',       'Hyundai', 2023, true),
  ('deadbeef-2000-0000-0000-000000000005','deadbeef-0000-0000-0000-000000000001','deadbeef-1000-0000-0000-000000000005','EE-55-DM','e-208',         'Peugeot', 2024, true)
ON CONFLICT (id) DO UPDATE SET matricula = EXCLUDED.matricula, ativo = TRUE;

-- 5) 6 semanas de pagamentos (30 rows total)
DO $$
DECLARE
  v_motoristas uuid[] := ARRAY[
    'deadbeef-1000-0000-0000-000000000001'::uuid,
    'deadbeef-1000-0000-0000-000000000002'::uuid,
    'deadbeef-1000-0000-0000-000000000003'::uuid,
    'deadbeef-1000-0000-0000-000000000004'::uuid,
    'deadbeef-1000-0000-0000-000000000005'::uuid
  ];
  v_mot uuid;
  v_idx int;
  v_off int;
  v_sem date;
  v_uber numeric; v_bolt numeric; v_iva numeric; v_slot numeric; v_alug numeric;
  v_prio numeric; v_vv numeric; v_final numeric; v_estado text;
BEGIN
  -- limpa pagamentos demo prévios para re-seed limpo
  DELETE FROM pagamentos WHERE empresa_id = 'deadbeef-0000-0000-0000-000000000001'::uuid;

  FOR v_idx IN 1..array_length(v_motoristas,1) LOOP
    v_mot := v_motoristas[v_idx];
    FOR v_off IN 0..5 LOOP
      v_sem := (date_trunc('week', CURRENT_DATE)::date - (v_off * 7));
      v_uber := round((400 + (v_idx*30) + random()*200)::numeric, 2);
      v_bolt := round((200 + (v_idx*20) + random()*150)::numeric, 2);
      v_iva  := round((v_uber * 0.06 + v_bolt * 0.06)::numeric, 2);
      v_slot := CASE WHEN v_idx <= 2 THEN 0 ELSE 35 END;
      v_alug := CASE WHEN v_idx >= 3 THEN 250.0 + (v_idx*10) ELSE 0 END;
      v_prio := round((20 + random()*40)::numeric, 2);
      v_vv   := round((5 + random()*20)::numeric, 2);
      v_final := round((v_uber + v_bolt - v_iva - v_slot - v_alug - v_prio - v_vv)::numeric, 2);
      v_estado := CASE WHEN v_off >= 2 THEN 'pago' ELSE 'criado' END;

      INSERT INTO pagamentos (
        empresa_id, motorista_id, semana_inicio,
        uber_bruto, uber_liquido, bolt_liquido, iva_cobrar,
        slot_valor, aluguer_valor, prio_valor, viaverde_valor,
        valor_final, estado, data_pagamento, confirmado_motorista_em
      ) VALUES (
        'deadbeef-0000-0000-0000-000000000001'::uuid,
        v_mot, v_sem,
        v_uber, v_uber, v_bolt, v_iva,
        v_slot, v_alug, v_prio, v_vv,
        v_final, v_estado,
        CASE WHEN v_estado = 'pago' THEN v_sem + INTERVAL '8 days' ELSE NULL END,
        CASE WHEN v_off >= 1 THEN v_sem + INTERVAL '6 days' ELSE NULL END
      );
    END LOOP;
  END LOOP;
END $$;

-- 6) Verificação
SELECT
  (SELECT COUNT(*) FROM empresas WHERE demo = TRUE) AS empresas_demo,
  (SELECT COUNT(*) FROM motoristas WHERE empresa_id = 'deadbeef-0000-0000-0000-000000000001'::uuid) AS motoristas_demo,
  (SELECT COUNT(*) FROM veiculos WHERE empresa_id = 'deadbeef-0000-0000-0000-000000000001'::uuid) AS viaturas_demo,
  (SELECT COUNT(*) FROM pagamentos WHERE empresa_id = 'deadbeef-0000-0000-0000-000000000001'::uuid) AS pagamentos_demo,
  (SELECT SUM(valor_final) FROM pagamentos WHERE empresa_id = 'deadbeef-0000-0000-0000-000000000001'::uuid AND estado='pago') AS total_pago;
