-- =====================================================
-- FleetPay — Recibos PDF (auto ao marcar pago)
-- =====================================================

ALTER TABLE pagamentos
  ADD COLUMN IF NOT EXISTS recibo_path TEXT,
  ADD COLUMN IF NOT EXISTS recibo_numero TEXT,
  ADD COLUMN IF NOT EXISTS recibo_gerado_em TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_pagamentos_recibo_num
  ON pagamentos(empresa_id, recibo_numero)
  WHERE recibo_numero IS NOT NULL;

-- Função: gera próximo número de recibo no formato AAAA-MM-XXX por empresa
CREATE OR REPLACE FUNCTION proximo_numero_recibo(p_empresa_id UUID, p_data DATE DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_data DATE := COALESCE(p_data, CURRENT_DATE);
  v_prefixo TEXT;
  v_count INT;
  v_numero TEXT;
BEGIN
  v_prefixo := TO_CHAR(v_data, 'YYYY-MM');
  SELECT COUNT(*)+1 INTO v_count
  FROM pagamentos
  WHERE empresa_id = p_empresa_id
    AND recibo_numero LIKE v_prefixo || '-%';
  v_numero := v_prefixo || '-' || LPAD(v_count::text, 3, '0');
  RETURN v_numero;
END;
$$;

-- =====================================================
-- Bucket Storage 'recibos' — privado
-- ⚠️ MANUAL: Storage → Create bucket → 'recibos' → Private → Save
-- =====================================================

DROP POLICY IF EXISTS recibos_storage_operador ON storage.objects;
DROP POLICY IF EXISTS recibos_storage_motorista ON storage.objects;
DROP POLICY IF EXISTS recibos_storage_superadmin ON storage.objects;

CREATE POLICY recibos_storage_superadmin ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'recibos' AND get_role() = 'superadmin')
  WITH CHECK (bucket_id = 'recibos' AND get_role() = 'superadmin');

CREATE POLICY recibos_storage_operador ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'recibos' AND get_role() IN ('operador','admin')
    AND (storage.foldername(name))[1]::uuid IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
  )
  WITH CHECK (
    bucket_id = 'recibos' AND get_role() IN ('operador','admin')
    AND (storage.foldername(name))[1]::uuid IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
  );

-- Motorista vê só os seus recibos (path: {empresa_id}/{motorista_id}/...)
CREATE POLICY recibos_storage_motorista ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'recibos'
    AND (storage.foldername(name))[2]::uuid IN (
      SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()
    )
  );
