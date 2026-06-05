-- =====================================================
-- FleetPay — Templates Matriz
-- Templates que servem de base para qualquer operador.
-- Qualquer operador pode promover os seus a matriz.
-- =====================================================

-- 1) Colunas extra
ALTER TABLE contratos_templates
  ADD COLUMN IF NOT EXISTS is_matriz BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS matriz_origem UUID REFERENCES contratos_templates(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS promovido_por UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS promovido_em TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_templates_matriz
  ON contratos_templates(is_matriz)
  WHERE is_matriz = TRUE;

-- 2) Policy SELECT: qualquer authenticated pode ver matriz; resto continua igual
DROP POLICY IF EXISTS templates_select_all ON contratos_templates;
DROP POLICY IF EXISTS templates_operador_select ON contratos_templates;
DROP POLICY IF EXISTS templates_motorista_select ON contratos_templates;

CREATE POLICY templates_select_all ON contratos_templates
  FOR SELECT TO authenticated
  USING (
    get_role() = 'superadmin'
    OR is_matriz = TRUE
    OR empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
  );

-- 3) Storage policy: download dos ficheiros matriz por qualquer authenticated
DROP POLICY IF EXISTS templates_storage_matriz_select ON storage.objects;
CREATE POLICY templates_storage_matriz_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'contratos-templates'
    AND name IN (
      SELECT ficheiro_path FROM contratos_templates WHERE is_matriz = TRUE
    )
  );

-- 4) Promover os templates da Inst31 actuais a matriz (assume Inst31 = Instituto 31, LDA)
-- ⚠️ Ajusta o nome se for diferente
UPDATE contratos_templates
SET is_matriz = TRUE,
    promovido_em = NOW()
WHERE empresa_id IN (
  SELECT id FROM empresas WHERE nome ILIKE '%instituto%' OR nipc = '518644650'
)
  AND ativo = TRUE
  AND is_matriz = FALSE;

-- 5) Verificação
SELECT
  (SELECT COUNT(*) FROM contratos_templates WHERE is_matriz = TRUE) AS templates_matriz,
  (SELECT COUNT(*) FROM contratos_templates WHERE NOT is_matriz) AS templates_proprios,
  (SELECT COUNT(*) FROM contratos_templates) AS total;
