-- =====================================================
-- FleetPay — Modelo de comissão configurável por empresa
-- Resolve definitivamente o problema das comissões diferentes
-- entre operadores (Inst31 = inclusivo, Bouchardet = directo, etc.)
-- =====================================================

-- 1) Coluna na empresa
ALTER TABLE empresas
  ADD COLUMN IF NOT EXISTS modelo_comissao TEXT DEFAULT 'directo'
  CHECK (modelo_comissao IN ('directo','inclusivo'));

COMMENT ON COLUMN empresas.modelo_comissao IS
  'directo: comissão = bruto × pct / 100 (mais comum).
   inclusivo: comissão = bruto × pct / (100 + pct) (pct incluso no bruto).';

-- 2) Configura empresas existentes
-- Inst31 / Inst31.1 = inclusivo (modelo que a Flávia usa)
UPDATE empresas SET modelo_comissao = 'inclusivo'
WHERE (nipc = '518644650' OR nome ILIKE '%instituto%31%' OR email = 'coordenacao@instituto31.pt')
  AND modelo_comissao IS DISTINCT FROM 'inclusivo';

-- Bouchardet e quaisquer outros novos = directo (default)
UPDATE empresas SET modelo_comissao = 'directo'
WHERE modelo_comissao IS NULL;

-- 3) Verificação
SELECT id, nome, modelo_comissao FROM empresas ORDER BY nome;

-- =====================================================
-- 4) Recalcular pagamentos existentes — usa o modelo da empresa
-- =====================================================
UPDATE pagamentos p
SET
  uber_iva_valor = p.uber_bruto * m.comissao_pct /
    CASE WHEN e.modelo_comissao = 'inclusivo' THEN (100 + m.comissao_pct) ELSE 100.0 END,
  bolt_iva = p.bolt_liquido * m.comissao_pct /
    CASE WHEN e.modelo_comissao = 'inclusivo' THEN (100 + m.comissao_pct) ELSE 100.0 END,
  iva_cobrar = (p.uber_bruto + p.bolt_liquido) * m.comissao_pct /
    CASE WHEN e.modelo_comissao = 'inclusivo' THEN (100 + m.comissao_pct) ELSE 100.0 END,
  valor_final = (p.uber_bruto + p.bolt_liquido)
              - ((p.uber_bruto + p.bolt_liquido) * m.comissao_pct /
                 CASE WHEN e.modelo_comissao = 'inclusivo' THEN (100 + m.comissao_pct) ELSE 100.0 END)
              - COALESCE(p.slot_valor, 0)
              - COALESCE(p.aluguer_valor, 0)
              - COALESCE(p.prio_valor, 0)
              - COALESCE(p.viaverde_valor, 0)
FROM motoristas m, empresas e
WHERE m.id = p.motorista_id
  AND e.id = p.empresa_id
  AND p.estado <> 'pago';  -- só os não pagos (pagos ficam congelados como histórico)
