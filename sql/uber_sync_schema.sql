-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Uber Supplier Performance Data API integration
-- ════════════════════════════════════════════════════════════════════
-- Adiciona credenciais e tracking para sincronização com a Uber Vehicle
-- Suppliers API (https://developer.uber.com/docs/vehicles).
--
-- Endpoints usados:
--   POST https://login.uber.com/oauth/v2/token
--   GET  https://api.uber.com/v1/vehicle-suppliers/drivers?org_id=X
--   GET  https://api.uber.com/v2/vehicle-suppliers/vehicles?org_id=X
-- ════════════════════════════════════════════════════════════════════

-- ── Credenciais Uber por empresa ────────────────────────────────────
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS uber_client_id TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS uber_client_secret TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS uber_org_id TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS uber_api_ativo BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS uber_last_sync_at TIMESTAMPTZ;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS uber_last_sync_summary JSONB;

-- ── Linkar registos a IDs da Uber (mesma estratégia da Bolt) ────────
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS uber_driver_id TEXT;
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS uber_synced_at TIMESTAMPTZ;
ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS uber_vehicle_id TEXT;
ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS uber_synced_at TIMESTAMPTZ;

-- ── Indexes ─────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_motoristas_uber_id ON motoristas(uber_driver_id) WHERE uber_driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_veiculos_uber_id ON veiculos(uber_vehicle_id) WHERE uber_vehicle_id IS NOT NULL;

-- ── Origem (caso ainda não exista — partilhada com Bolt sync) ───────
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS origem TEXT;
ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS origem TEXT;

SELECT 'Schema Uber sync criado!' AS resultado;
