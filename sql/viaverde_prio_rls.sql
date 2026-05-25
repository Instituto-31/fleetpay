-- ════════════════════════════════════════════════════════════════════
-- FleetPay — RLS para viaverde_portagens + prio_carregamentos (2026-05-24)
-- ════════════════════════════════════════════════════════════════════
-- Operadores e superadmin precisam de INSERT/SELECT/DELETE nas tabelas
-- de portagens e combustível. Estas tabelas foram criadas via Dashboard
-- e ficaram sem policies — o INSERT falhava com:
--   "new row violates row-level security policy"
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE viaverde_portagens ENABLE ROW LEVEL SECURITY;
ALTER TABLE prio_carregamentos ENABLE ROW LEVEL SECURITY;

-- ─── viaverde_portagens ──────────────────────────────────────────────
DROP POLICY IF EXISTS "viaverde_portagens_all_operador" ON viaverde_portagens;
CREATE POLICY "viaverde_portagens_all_operador"
ON viaverde_portagens
FOR ALL
TO authenticated
USING (
  get_role() = 'superadmin'
  OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
)
WITH CHECK (
  get_role() = 'superadmin'
  OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
);

-- Motorista vê apenas as suas próprias portagens
DROP POLICY IF EXISTS "viaverde_portagens_select_motorista" ON viaverde_portagens;
CREATE POLICY "viaverde_portagens_select_motorista"
ON viaverde_portagens
FOR SELECT
TO authenticated
USING (
  motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
);

-- ─── prio_carregamentos ─────────────────────────────────────────────
DROP POLICY IF EXISTS "prio_carregamentos_all_operador" ON prio_carregamentos;
CREATE POLICY "prio_carregamentos_all_operador"
ON prio_carregamentos
FOR ALL
TO authenticated
USING (
  get_role() = 'superadmin'
  OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
)
WITH CHECK (
  get_role() = 'superadmin'
  OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
);

-- Motorista vê os seus próprios carregamentos
DROP POLICY IF EXISTS "prio_carregamentos_select_motorista" ON prio_carregamentos;
CREATE POLICY "prio_carregamentos_select_motorista"
ON prio_carregamentos
FOR SELECT
TO authenticated
USING (
  motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
);

SELECT 'Policies criadas para viaverde_portagens + prio_carregamentos' AS resultado;
