-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Detalhes PRIO E-Charge / Combustível (Sessão 2026-05-24)
-- ════════════════════════════════════════════════════════════════════
-- Adiciona colunas para detalhe de cada carregamento:
--   * estacao       — ID da estação (ex: GMR-00109)
--   * duracao_min   — Duração total em minutos
--   * card_code     — Código do cartão PRIO usado
--   * tipo          — 'electrico' | 'combustivel' | 'outro'
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE prio_carregamentos
  ADD COLUMN IF NOT EXISTS estacao TEXT,
  ADD COLUMN IF NOT EXISTS duracao_min NUMERIC(8,2),
  ADD COLUMN IF NOT EXISTS card_code TEXT,
  ADD COLUMN IF NOT EXISTS tipo TEXT;

COMMENT ON COLUMN prio_carregamentos.estacao IS 'ID da estação de carregamento (PRIO E-Charge: ex GMR-00109)';
COMMENT ON COLUMN prio_carregamentos.duracao_min IS 'Duração total do carregamento em minutos';
COMMENT ON COLUMN prio_carregamentos.card_code IS 'Código do cartão PRIO usado (PTPRIO...)';
COMMENT ON COLUMN prio_carregamentos.tipo IS 'Tipo: electrico (E-Charge) | combustivel (Gasolina/Diesel) | outro';

SELECT 'Colunas detalhe PRIO adicionadas' AS resultado;
