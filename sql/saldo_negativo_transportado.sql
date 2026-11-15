-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Saldo negativo transportado para a semana seguinte
-- ════════════════════════════════════════════════════════════════════
-- Quando o valor_final de uma semana é negativo (motorista deve à empresa),
-- esse valor passa como "saldo_anterior" para a semana seguinte do mesmo
-- motorista e é subtraído ao valor a pagar. Encadeia-se automaticamente:
-- se a semana seguinte também ficar negativa, continua a transportar.
--
--   pagamentos.saldo_anterior  — valor (≤ 0) herdado da semana anterior
--   valor_final = rendimento − comissão − despesas + saldo_anterior
--
-- Quando uma semana muda (e não está paga), a semana seguinte é recalculada.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE pagamentos ADD COLUMN IF NOT EXISTS saldo_anterior NUMERIC(10,2) DEFAULT 0;

CREATE OR REPLACE FUNCTION public.fp_pagamento_auto_calcular()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_pct numeric; v_modelo text; v_div numeric;
  v_com_uber numeric; v_com_bolt numeric; v_com_total numeric;
  v_base_bolt numeric; v_sem_com numeric;
  v_saldo numeric;
BEGIN
  IF NEW.estado = 'pago' AND TG_OP = 'UPDATE' AND OLD.estado = 'pago' THEN RETURN NEW; END IF;
  SELECT COALESCE(comissao_pct, 6), COALESCE(modelo_comissao, 'directo')
    INTO v_pct, v_modelo FROM motoristas WHERE id = NEW.motorista_id;
  IF v_pct IS NULL THEN v_pct := 6; END IF;
  IF v_modelo IS NULL THEN v_modelo := 'directo'; END IF;
  v_div := CASE WHEN v_modelo = 'inclusivo' THEN (100 + v_pct) ELSE 100 END;
  v_base_bolt := COALESCE(NEW.bolt_liquido, 0) + COALESCE(NEW.bolt_campanha, 0) + COALESCE(NEW.bolt_cancelamentos, 0);
  v_sem_com   := COALESCE(NEW.bolt_gorjetas, 0) + COALESCE(NEW.bolt_reembolsos, 0);
  v_com_uber  := COALESCE(NEW.uber_bruto, 0) * v_pct / v_div;
  v_com_bolt  := v_base_bolt * v_pct / v_div;
  v_com_total := v_com_uber + v_com_bolt;

  -- Saldo negativo da semana imediatamente anterior deste motorista (≤ 0).
  -- Regra em vigor para semanas a partir de 2026-11-09 (histórico anterior fica como está).
  v_saldo := 0;
  IF NEW.semana_inicio >= DATE '2026-11-09' THEN
    SELECT LEAST(0, COALESCE(p.valor_final, 0)) INTO v_saldo
    FROM pagamentos p
    WHERE p.motorista_id = NEW.motorista_id
      AND p.semana_inicio < NEW.semana_inicio
      AND p.semana_inicio >= DATE '2026-11-02'
      AND (TG_OP = 'INSERT' OR p.id <> NEW.id)
    ORDER BY p.semana_inicio DESC
    LIMIT 1;
  END IF;
  NEW.saldo_anterior := ROUND(COALESCE(v_saldo, 0), 2);

  NEW.uber_iva_valor := v_com_uber;
  NEW.bolt_iva := v_com_bolt;
  NEW.iva_cobrar := v_com_total;
  NEW.rendimento_liquido := COALESCE(NEW.uber_bruto, 0) + v_base_bolt + v_sem_com;
  NEW.valor_final := COALESCE(NEW.uber_bruto, 0) + v_base_bolt + v_sem_com
                   - v_com_total - COALESCE(NEW.slot_valor, 0) - COALESCE(NEW.aluguer_valor, 0)
                   - COALESCE(NEW.prio_valor, 0) - COALESCE(NEW.viaverde_valor, 0)
                   + NEW.saldo_anterior;
  RETURN NEW;
END;
$$;

-- Quando o valor_final de uma semana muda, recalcula a semana seguinte (se não estiver paga)
CREATE OR REPLACE FUNCTION public.fp_pagamento_propagar_saldo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.valor_final IS NOT DISTINCT FROM OLD.valor_final THEN RETURN NEW; END IF;
  UPDATE pagamentos
  SET atualizado_em = now()
  WHERE id = (
    SELECT id FROM pagamentos
    WHERE motorista_id = NEW.motorista_id AND semana_inicio > NEW.semana_inicio
    ORDER BY semana_inicio ASC LIMIT 1
  )
  AND estado <> 'pago';
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER tr_pagamento_propagar_saldo
AFTER INSERT OR UPDATE ON pagamentos
FOR EACH ROW EXECUTE FUNCTION fp_pagamento_propagar_saldo();
