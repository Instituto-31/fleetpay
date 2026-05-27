-- =====================================================
-- FleetPay — Documentos (Empresa + Viatura + Motorista)
-- Sistema de upload de docs pelo operador, visíveis pelo
-- motorista para fiscalização (carta condução, inspeção,
-- seguros, DUA, licença operador, etc.)
-- =====================================================

-- 1) Tabela documentos
CREATE TABLE IF NOT EXISTS documentos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  veiculo_id UUID REFERENCES veiculos(id) ON DELETE CASCADE,
  motorista_id UUID REFERENCES motoristas(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL,
  nome TEXT NOT NULL,
  ficheiro_path TEXT NOT NULL,
  mime_type TEXT,
  tamanho_bytes BIGINT,
  validade DATE,
  notas TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  criado_por UUID REFERENCES auth.users(id),
  CONSTRAINT documentos_nivel_check CHECK (
    -- Empresa: ambos NULL; Viatura: só veiculo_id; Motorista: só motorista_id
    (veiculo_id IS NULL AND motorista_id IS NULL) OR
    (veiculo_id IS NOT NULL AND motorista_id IS NULL) OR
    (veiculo_id IS NULL AND motorista_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_documentos_empresa ON documentos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_documentos_veiculo ON documentos(veiculo_id) WHERE veiculo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_documentos_motorista ON documentos(motorista_id) WHERE motorista_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_documentos_validade ON documentos(validade) WHERE validade IS NOT NULL;

-- 2) RLS
ALTER TABLE documentos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS documentos_operador_all ON documentos;
DROP POLICY IF EXISTS documentos_motorista_select ON documentos;
DROP POLICY IF EXISTS documentos_superadmin_all ON documentos;

-- Superadmin: tudo
CREATE POLICY documentos_superadmin_all ON documentos
  FOR ALL TO authenticated
  USING (get_role() = 'superadmin')
  WITH CHECK (get_role() = 'superadmin');

-- Operador: CRUD na sua empresa
CREATE POLICY documentos_operador_all ON documentos
  FOR ALL TO authenticated
  USING (
    get_role() IN ('operador','admin')
    AND empresa_id IN (
      SELECT empresa_id FROM perfis WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    get_role() IN ('operador','admin')
    AND empresa_id IN (
      SELECT empresa_id FROM perfis WHERE id = auth.uid()
    )
  );

-- Motorista: SELECT só dos seus + da empresa + da viatura atribuída
CREATE POLICY documentos_motorista_select ON documentos
  FOR SELECT TO authenticated
  USING (
    -- docs da empresa do motorista (genéricos)
    (
      veiculo_id IS NULL AND motorista_id IS NULL
      AND empresa_id IN (
        SELECT m.empresa_id FROM motoristas m WHERE m.user_id = auth.uid()
      )
    )
    OR
    -- docs da viatura atribuída ao motorista
    (
      veiculo_id IS NOT NULL AND motorista_id IS NULL
      AND veiculo_id IN (
        SELECT m.veiculo_id FROM motoristas m WHERE m.user_id = auth.uid() AND m.veiculo_id IS NOT NULL
      )
    )
    OR
    -- docs pessoais do motorista
    (
      motorista_id IS NOT NULL
      AND motorista_id IN (
        SELECT m.id FROM motoristas m WHERE m.user_id = auth.uid()
      )
    )
  );

-- 3) Storage bucket
-- ⚠️ MANUAL: ir a Storage → Create new bucket → nome 'documentos' → Private (NÃO public)
-- Depois correr as policies abaixo.

-- Policies do bucket: paths no formato "{empresa_id}/{tipo}/{ficheiro}"
DROP POLICY IF EXISTS documentos_storage_operador_all ON storage.objects;
DROP POLICY IF EXISTS documentos_storage_motorista_select ON storage.objects;
DROP POLICY IF EXISTS documentos_storage_superadmin_all ON storage.objects;

CREATE POLICY documentos_storage_superadmin_all ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'documentos' AND get_role() = 'superadmin')
  WITH CHECK (bucket_id = 'documentos' AND get_role() = 'superadmin');

CREATE POLICY documentos_storage_operador_all ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'documentos'
    AND get_role() IN ('operador','admin')
    AND (storage.foldername(name))[1]::uuid IN (
      SELECT empresa_id FROM perfis WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    bucket_id = 'documentos'
    AND get_role() IN ('operador','admin')
    AND (storage.foldername(name))[1]::uuid IN (
      SELECT empresa_id FROM perfis WHERE id = auth.uid()
    )
  );

CREATE POLICY documentos_storage_motorista_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documentos'
    AND (storage.foldername(name))[1]::uuid IN (
      SELECT m.empresa_id FROM motoristas m WHERE m.user_id = auth.uid()
    )
  );

-- =====================================================
-- Tipos sugeridos (usar como TEXT na coluna `tipo`):
-- Empresa:   licenca_operador | seguro_rc_geral | alvara_tvde | outros
-- Viatura:   inspecao | dua | seguro_auto | livrete | dtr | outros
-- Motorista: carta_conducao | cc_motorista | certificado_motorista | outros
-- =====================================================
