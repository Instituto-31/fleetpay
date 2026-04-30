-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Bolt API Sync (Parte A: motoristas + viaturas)
-- ════════════════════════════════════════════════════════════════════
-- Adiciona colunas para identificar e fazer match com Bolt Fleet API:
--   • empresas.bolt_company_id   — ID numérico da empresa no portal Bolt
--   • empresas.bolt_last_sync_at — timestamp da última sincronização
--   • motoristas.bolt_driver_id  — ID do motorista na Bolt
--   • motoristas.bolt_synced_at  — última sync deste motorista
--   • veiculos.bolt_car_id       — ID da viatura na Bolt
--   • veiculos.bolt_synced_at    — última sync desta viatura
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Empresas ──────────────────────────────────────────────────────
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS bolt_company_id TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS bolt_last_sync_at TIMESTAMPTZ;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS bolt_last_sync_summary JSONB;

-- ── 2. Motoristas ───────────────────────────────────────────────────
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS bolt_driver_id TEXT;
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS bolt_synced_at TIMESTAMPTZ;
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS bolt_status TEXT;  -- ex: active, suspended, banned

CREATE UNIQUE INDEX IF NOT EXISTS idx_motoristas_bolt_unique
  ON motoristas(empresa_id, bolt_driver_id)
  WHERE bolt_driver_id IS NOT NULL;

-- ── 3. Viaturas ──────────────────────────────────────────────────────
ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS bolt_car_id TEXT;
ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS bolt_synced_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_veiculos_bolt_unique
  ON veiculos(empresa_id, bolt_car_id)
  WHERE bolt_car_id IS NOT NULL;

SELECT 'Schema bolt-sync pronto' AS resultado;
