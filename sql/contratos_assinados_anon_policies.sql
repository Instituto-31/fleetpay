-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Policies anon para assinar.html via token (Sessão 2026-05-20)
-- ════════════════════════════════════════════════════════════════════
-- assinar.html é público (motorista chega via link único com token).
-- Precisa de SELECT + UPDATE em contratos_assinados quando o token bate.
-- Também precisa de INSERT/UPDATE em storage.objects no bucket
-- contratos-assinados para fazer upload do PDF final.
--
-- Usamos role `public` (não só `anon`) porque o motorista pode estar
-- autenticado de outra página (já fez login para aceitar termos).
-- ════════════════════════════════════════════════════════════════════

-- ─── contratos_assinados ─────────────────────────────────────────────
DROP POLICY IF EXISTS "contratos_assinados_anon_update_with_check" ON contratos_assinados;
DROP POLICY IF EXISTS "contratos_assinados_anon_select_token" ON contratos_assinados;
DROP POLICY IF EXISTS "contratos_assinados_token_update" ON contratos_assinados;
DROP POLICY IF EXISTS "contratos_assinados_token_select" ON contratos_assinados;

CREATE POLICY "contratos_assinados_token_update"
ON contratos_assinados FOR UPDATE TO public
USING (link_token IS NOT NULL)
WITH CHECK (link_token IS NOT NULL);

CREATE POLICY "contratos_assinados_token_select"
ON contratos_assinados FOR SELECT TO public
USING (link_token IS NOT NULL);

-- ─── storage.objects (bucket contratos-assinados) ────────────────────
DROP POLICY IF EXISTS "contratos_assinados_anon_upload" ON storage.objects;
DROP POLICY IF EXISTS "contratos_assinados_anon_update" ON storage.objects;
DROP POLICY IF EXISTS "contratos_assinados_token_upload" ON storage.objects;
DROP POLICY IF EXISTS "contratos_assinados_token_update_obj" ON storage.objects;

CREATE POLICY "contratos_assinados_token_upload"
ON storage.objects FOR INSERT TO public
WITH CHECK (
  bucket_id = 'contratos-assinados'
  AND EXISTS (
    SELECT 1 FROM contratos_assinados ca
    WHERE ca.link_token IS NOT NULL
      AND ca.empresa_id::text = (storage.foldername(name))[1]
  )
);

CREATE POLICY "contratos_assinados_token_update_obj"
ON storage.objects FOR UPDATE TO public
USING (
  bucket_id = 'contratos-assinados'
  AND EXISTS (
    SELECT 1 FROM contratos_assinados ca
    WHERE ca.link_token IS NOT NULL
      AND ca.empresa_id::text = (storage.foldername(name))[1]
  )
)
WITH CHECK (
  bucket_id = 'contratos-assinados'
  AND EXISTS (
    SELECT 1 FROM contratos_assinados ca
    WHERE ca.link_token IS NOT NULL
      AND ca.empresa_id::text = (storage.foldername(name))[1]
  )
);

SELECT 'Policies anon de contratos_assinados aplicadas' AS resultado;
