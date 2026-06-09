-- =====================================================
-- FleetPay — Modelo de comissão MOVIDO para motorista
-- (em vez de empresa)
-- =====================================================
-- Cada motorista tem o seu modelo. Default 'directo'.
-- A empresa mantém a coluna por retrocompatibilidade
-- mas o trigger passa a usar a do motorista.
-- =====================================================

-- 1) Nova coluna no motorista
ALTER TABLE motoristas
  ADD COLUMN IF NOT EXISTS modelo_comissao TEXT DEFAULT 'directo'
  CHECK (modelo_comissao IN ('directo','inclusivo'));

COMMENT ON COLUMN motoristas.modelo_comissao IS
  'directo: comissão = bruto × pct / 100.
   inclusivo: comissão = bruto × pct / (100 + pct).';

-- 2) Migração: cada motorista herda o modelo que estava na empresa
UPDATE motoristas m
SET modelo_comissao = COALESCE(e.modelo_comissao, 'directo')
FROM empresas e
WHERE e.id = m.empresa_id
  AND m.modelo_comissao IS NULL;

-- 3) Actualiza o trigger BEFORE INSERT/UPDATE em pagamentos
--    para usar motoristas.modelo_comissao (em vez de empresas.modelo_comissao)
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
  IF NEW.estado = 'pago' AND TG_OP = 'UPDATE' AND OLD.estado = 'pago' THEN
    RETURN NEW;
  END IF;

  -- Pct + modelo agora vêm do motorista
  SELECT COALESCE(comissao_pct, 6),
         COALESCE(modelo_comissao, 'directo')
    INTO v_pct, v_modelo
  FROM motoristas WHERE id = NEW.motorista_id;

  IF v_pct IS NULL THEN v_pct := 6; END IF;
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

-- 4) Trigger AFTER UPDATE em motoristas: se modelo_comissao OU comissao_pct mudar, recalcula
CREATE OR REPLACE FUNCTION fp_motorista_pct_mudou()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.comissao_pct IS DISTINCT FROM OLD.comissao_pct
     OR NEW.modelo_comissao IS DISTINCT FROM OLD.modelo_comissao THEN
    UPDATE pagamentos
    SET uber_bruto = uber_bruto  -- noop dispara trigger BEFORE
    WHERE motorista_id = NEW.id AND estado <> 'pago';
  END IF;
  RETURN NEW;
END;
$$;

-- 5) Trigger de empresa pode continuar — mas não há motivo prático.
--    Vamos deixar como está (idempotente, não causa mal).

-- 6) Força recálculo geral (todos não-pagos)
UPDATE pagamentos SET uber_bruto = uber_bruto WHERE estado <> 'pago';

-- 7) Verificação
SELECT m.nome, m.comissao_pct, m.modelo_comissao,
       e.nome AS empresa,
       (SELECT COUNT(*) FROM pagamentos p
        WHERE p.motorista_id = m.id AND p.estado <> 'pago') AS pags_pendentes
FROM motoristas m
JOIN empresas e ON e.id = m.empresa_id
WHERE m.ativo = true
ORDER BY e.nome, m.nome;
