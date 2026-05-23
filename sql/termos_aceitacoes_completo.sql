-- ════════════════════════════════════════════════════════════════════
-- FleetPay — termos_aceitacoes completo (Sessão 2026-05-20)
-- ════════════════════════════════════════════════════════════════════
-- Consolidação das alterações aplicadas via SQL Editor durante a
-- depuração do loop de Termos & Condições do motorista castro200@sapo.pt:
--
--   1. Policy RLS: motorista pode INSERT a sua propria aceitação
--   2. Policy RLS: motorista vê as suas, operador/superadmin vê todas
--   3. UNIQUE constraint (motorista_id, termos_versao_id) para evitar
--      duplicados que provocavam .maybeSingle() rebentar com >1 row
--   4. Colunas validado_por / validado_em / validado_user_agent para
--      audit trail bilateral (motorista assina + operador valida)
--   5. Policy RLS UPDATE para superadmin/operador validar aceitações
-- ════════════════════════════════════════════════════════════════════

-- 1. RLS activo
ALTER TABLE termos_aceitacoes ENABLE ROW LEVEL SECURITY;

-- 2. INSERT pelo motorista próprio
DROP POLICY IF EXISTS "termos_aceitacoes_insert_motorista" ON termos_aceitacoes;
CREATE POLICY "termos_aceitacoes_insert_motorista"
ON termos_aceitacoes
FOR INSERT
TO authenticated
WITH CHECK (
  motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
);

-- 3. SELECT motorista próprio + operador/superadmin
DROP POLICY IF EXISTS "termos_aceitacoes_select" ON termos_aceitacoes;
CREATE POLICY "termos_aceitacoes_select"
ON termos_aceitacoes
FOR SELECT
TO authenticated
USING (
  motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
  OR get_role() IN ('operador','superadmin')
);

-- 4. UNIQUE constraint — impede o loop de duplicados
ALTER TABLE termos_aceitacoes
  DROP CONSTRAINT IF EXISTS uq_termos_aceitacoes_motorista_versao;
ALTER TABLE termos_aceitacoes
  ADD CONSTRAINT uq_termos_aceitacoes_motorista_versao
  UNIQUE (motorista_id, termos_versao_id);

-- 5. Colunas de audit trail bilateral
ALTER TABLE termos_aceitacoes
  ADD COLUMN IF NOT EXISTS validado_por UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS validado_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS validado_user_agent TEXT;

-- 6. UPDATE pelo operador para validar
DROP POLICY IF EXISTS "termos_aceitacoes_validar_operador" ON termos_aceitacoes;
CREATE POLICY "termos_aceitacoes_validar_operador"
ON termos_aceitacoes
FOR UPDATE
TO authenticated
USING (get_role() IN ('operador','superadmin'))
WITH CHECK (get_role() IN ('operador','superadmin'));

SELECT 'termos_aceitacoes: RLS + UNIQUE + colunas validação aplicadas' AS resultado;
