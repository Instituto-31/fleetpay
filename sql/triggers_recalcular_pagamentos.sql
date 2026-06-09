-- =====================================================
-- FleetPay — Auto-recálculo de pagamentos
-- Garante que valores estão SEMPRE correctos.
-- Nunca mais SQL manual para corrigir comissões.
-- =====================================================
--
-- Como funciona:
--   1. Pagamento inserido/actualizado → trigger BEFORE recalcula iva_cobrar + valor_final
--      usando o modelo da empresa e a comissão do motorista
--   2. Empresa muda modelo_comissao → trigger AFTER recalcula TODOS os pagamentos
--      não-pagos dessa empresa
--   3. Motorista muda comissao_pct → trigger AFTER recalcula pagamentos não-pagos dele
--   4. Pagamentos pagos (estado='pago') ficam CONGELADOS como histórico
--
-- =====================================================

-- 1) Função pura: calcula comissão para um pagamento
CREATE OR REPLACE FUNCTION fp_calcular_comissao(
  p_uber_bruto numeric,
  p_bolt_liquido numeric,
  p_comissao_pct numeric,
  p_modelo text
) RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $$
  SELECT (COALESCE(p_uber_bruto, 0) + COALESCE(p_bolt_liquido, 0))
       * COALESCE(p_comissao_pct, 0)
       / CASE WHEN p_modelo = 'inclusivo' THEN (100 + COALESCE(p_comissao_pct, 0)) ELSE 100 END;
$$;

-- 2) Trigger BEFORE INSERT/UPDATE em pagamentos
--    Recalcula iva_cobrar + valor_final automaticamente
CREATE OR REPLACE FUNCTION fp_pagamento_auto_calcular()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_pct numeric;
  v_modelo text;
  v_div numeric;
  v_com_uber numeric;
  v_com_bolt numeric;
  v_com_total numeric;
BEGIN
  -- Não recalcula se estado='pago' (histórico congelado)
  IF NEW.estado = 'pago' AND TG_OP = 'UPDATE' AND OLD.estado = 'pago' THEN
    RETURN NEW;
  END IF;

  -- Busca % do motorista e modelo da empresa
  SELECT COALESCE(comissao_pct, 6) INTO v_pct
  FROM motoristas WHERE id = NEW.motorista_id;
  IF v_pct IS NULL THEN v_pct := 6; END IF;

  SELECT COALESCE(modelo_comissao, 'directo') INTO v_modelo
  FROM empresas WHERE id = NEW.empresa_id;
  IF v_modelo IS NULL THEN v_modelo := 'directo'; END IF;

  v_div := CASE WHEN v_modelo = 'inclusivo' THEN (100 + v_pct) ELSE 100 END;

  v_com_uber := COALESCE(NEW.uber_bruto, 0) * v_pct / v_div;
  v_com_bolt := COALESCE(NEW.bolt_liquido, 0) * v_pct / v_div;
  v_com_total := v_com_uber + v_com_bolt;

  NEW.uber_iva_valor := v_com_uber;
  NEW.bolt_iva := v_com_bolt;
  NEW.iva_cobrar := v_com_total;
  NEW.valor_final := COALESCE(NEW.uber_bruto, 0) + COALESCE(NEW.bolt_liquido, 0)
                    - v_com_total
                    - COALESCE(NEW.slot_valor, 0)
                    - COALESCE(NEW.aluguer_valor, 0)
                    - COALESCE(NEW.prio_valor, 0)
                    - COALESCE(NEW.viaverde_valor, 0);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_pagamento_auto_calcular ON pagamentos;
CREATE TRIGGER tr_pagamento_auto_calcular
  BEFORE INSERT OR UPDATE ON pagamentos
  FOR EACH ROW EXECUTE FUNCTION fp_pagamento_auto_calcular();

-- 3) Trigger AFTER UPDATE em empresas.modelo_comissao
--    Quando muda, recalcula TODOS os pagamentos não-pagos dessa empresa
CREATE OR REPLACE FUNCTION fp_empresa_modelo_mudou()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.modelo_comissao IS DISTINCT FROM OLD.modelo_comissao THEN
    -- Toca em todos os pagamentos não pagos da empresa
    -- (o trigger BEFORE em pagamentos vai recalcular)
    UPDATE pagamentos
    SET uber_bruto = uber_bruto  -- noop UPDATE só para disparar BEFORE trigger
    WHERE empresa_id = NEW.id AND estado <> 'pago';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_empresa_modelo_mudou ON empresas;
CREATE TRIGGER tr_empresa_modelo_mudou
  AFTER UPDATE ON empresas
  FOR EACH ROW EXECUTE FUNCTION fp_empresa_modelo_mudou();

-- 4) Trigger AFTER UPDATE em motoristas.comissao_pct
CREATE OR REPLACE FUNCTION fp_motorista_pct_mudou()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.comissao_pct IS DISTINCT FROM OLD.comissao_pct THEN
    UPDATE pagamentos
    SET uber_bruto = uber_bruto  -- noop
    WHERE motorista_id = NEW.id AND estado <> 'pago';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_motorista_pct_mudou ON motoristas;
CREATE TRIGGER tr_motorista_pct_mudou
  AFTER UPDATE ON motoristas
  FOR EACH ROW EXECUTE FUNCTION fp_motorista_pct_mudou();

-- =====================================================
-- 5) FORÇA recálculo imediato de TUDO (uma vez)
--    Toca em todos os pagamentos não pagos para fixar valores antigos
-- =====================================================
UPDATE pagamentos
SET uber_bruto = uber_bruto
WHERE estado <> 'pago';

-- =====================================================
-- 6) Verificação
-- =====================================================
SELECT
  e.nome AS empresa, e.modelo_comissao,
  COUNT(p.id) AS pagamentos,
  ROUND(SUM(p.iva_cobrar)::numeric, 2) AS total_comissao,
  ROUND(SUM(p.valor_final)::numeric, 2) AS total_a_pagar
FROM pagamentos p
JOIN empresas e ON e.id = p.empresa_id
WHERE p.estado <> 'pago'
GROUP BY e.id, e.nome, e.modelo_comissao
ORDER BY e.nome;
