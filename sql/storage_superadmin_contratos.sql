-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Storage policies: superadmin opera em qualquer empresa
-- ════════════════════════════════════════════════════════════════════
-- Problema corrigido:
--   StorageApiError: new row violates row-level security policy
--   (ao tentar copiar template entre empresas, mesmo sendo superadmin)
--
-- Causa: as policies actuais dos buckets `contratos-templates` e
-- `contratos-assinados` filtram por `storage.foldername(name)[1] =
-- empresa_id_do_utilizador`. O superadmin precisa de poder escrever
-- em pastas de qualquer empresa, não só na empresa ativa.
--
-- Solução: adicionar uma policy PERMISSIVA por bucket que liberta
-- TUDO (SELECT/INSERT/UPDATE/DELETE) ao superadmin. Como o
-- PostgreSQL avalia múltiplas policies permissivas em OR, isto
-- NÃO remove restrições existentes para operadores/motoristas —
-- apenas dá ao superadmin um caminho adicional para passar.
--
-- Aplicar: copiar/colar este script no Supabase → SQL Editor → Run.
-- Idempotente: pode correr-se várias vezes sem efeitos secundários.
-- ════════════════════════════════════════════════════════════════════

-- ─── Bucket: contratos-templates (usado por upload + auto-replicação) ──
DROP POLICY IF EXISTS "contratos_templates_superadmin_all" ON storage.objects;
CREATE POLICY "contratos_templates_superadmin_all"
ON storage.objects
FOR ALL
TO authenticated
USING (
  bucket_id = 'contratos-templates'
  AND public.get_role() = 'superadmin'
)
WITH CHECK (
  bucket_id = 'contratos-templates'
  AND public.get_role() = 'superadmin'
);

-- ─── Bucket: contratos-assinados (PDFs assinados arquivados) ──────────
DROP POLICY IF EXISTS "contratos_assinados_superadmin_all" ON storage.objects;
CREATE POLICY "contratos_assinados_superadmin_all"
ON storage.objects
FOR ALL
TO authenticated
USING (
  bucket_id = 'contratos-assinados'
  AND public.get_role() = 'superadmin'
)
WITH CHECK (
  bucket_id = 'contratos-assinados'
  AND public.get_role() = 'superadmin'
);

-- ─── Verificação ──────────────────────────────────────────────────────
SELECT
  'storage.objects' AS tabela,
  policyname,
  cmd
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname LIKE '%superadmin%'
ORDER BY policyname;

SELECT '✅ Policies de Storage criadas — superadmin pode escrever em qualquer pasta de contratos-templates e contratos-assinados' AS resultado;
