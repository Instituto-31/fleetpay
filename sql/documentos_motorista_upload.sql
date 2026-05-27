-- =====================================================
-- FleetPay — Motorista pode CARREGAR documentos pessoais
-- (mas não apagar — operador valida)
-- =====================================================

-- 1) Colunas extra
ALTER TABLE documentos
  ADD COLUMN IF NOT EXISTS criado_por_motorista BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS validado_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS validado_por UUID REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_documentos_pendente
  ON documentos(empresa_id)
  WHERE criado_por_motorista = TRUE AND validado_em IS NULL;

-- 2) Policy: motorista INSERT só docs pessoais (motorista_id = ele próprio)
DROP POLICY IF EXISTS documentos_motorista_insert ON documentos;
CREATE POLICY documentos_motorista_insert ON documentos
  FOR INSERT TO authenticated
  WITH CHECK (
    -- só pode carregar como motorista (não como operador)
    -- e o doc tem de ser pessoal (motorista_id NOT NULL)
    -- e o motorista_id tem de ser o próprio motorista do user
    motorista_id IS NOT NULL
    AND veiculo_id IS NULL
    AND criado_por_motorista = TRUE
    AND validado_em IS NULL
    AND motorista_id IN (
      SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()
    )
    AND empresa_id IN (
      SELECT m.empresa_id FROM motoristas m WHERE m.perfil_id = auth.uid()
    )
  );

-- NOTA: motorista NÃO tem UPDATE nem DELETE. Só operador pode editar/apagar/validar.

-- 3) Policy Storage: motorista INSERT no seu próprio path
-- Path esperado: {empresa_id}/motorista/{doc_id}_{filename}
DROP POLICY IF EXISTS documentos_storage_motorista_insert ON storage.objects;
CREATE POLICY documentos_storage_motorista_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documentos'
    AND (storage.foldername(name))[1]::uuid IN (
      SELECT m.empresa_id FROM motoristas m WHERE m.perfil_id = auth.uid()
    )
    AND (storage.foldername(name))[2] = 'motorista'
  );

-- =====================================================
-- Fluxo:
--   1. Motorista vai ao Perfil → "Os meus documentos" → secção Pessoais → "+ Carregar"
--   2. INSERT documentos com criado_por_motorista=true, validado_em=NULL
--   3. Aparece no admin com badge "🆕 Novo"
--   4. Operador clica "✓ Validar" → UPDATE validado_em=NOW(), validado_por=auth.uid()
-- =====================================================
