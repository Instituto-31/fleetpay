-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Bolt Fleet API v2 (bolt-sync)
-- Novas colunas para os UUIDs da v2. bolt_driver_id / bolt_car_id (v1)
-- mantêm-se porque bolt-earnings ainda usa a v1 (até a Bolt publicar
-- o endpoint financeiro na v2; v1 desliga a 31 Jan 2027).
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS bolt_uuid TEXT;
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS bolt_partner_uuid TEXT;
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS bolt_online BOOLEAN;
CREATE INDEX IF NOT EXISTS idx_motoristas_bolt_uuid ON motoristas(empresa_id, bolt_uuid) WHERE bolt_uuid IS NOT NULL;

ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS bolt_uuid TEXT;
ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS bolt_status TEXT;
ALTER TABLE veiculos ADD COLUMN IF NOT EXISTS numero_quadro TEXT;
CREATE INDEX IF NOT EXISTS idx_veiculos_bolt_uuid ON veiculos(empresa_id, bolt_uuid) WHERE bolt_uuid IS NOT NULL;

SELECT 'Schema bolt v2 pronto' AS resultado;

-- Chave API v2 separada da v1 (bolt-earnings continua a usar a v1)
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS bolt_client_id_v2 TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS bolt_client_secret_v2 TEXT;
