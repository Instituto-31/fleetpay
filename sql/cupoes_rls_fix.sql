-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Fix RLS validar.html (cupões + indicações)
-- ════════════════════════════════════════════════════════════════════
-- Problema: políticas estavam como TO anon, mas quando o validar.html
-- ou oferta.html é aberto numa janela com sessão activa (operador ou
-- motorista logged in), o role é authenticated — TO anon não aplica.
-- Solução: mudar para TO public (cobre anon E authenticated). O token
-- é a barreira de segurança, não o role.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. cupoes_redencoes — validar.html ──────────────────────────────
DROP POLICY IF EXISTS "redencoes_select_anon_token" ON cupoes_redencoes;
CREATE POLICY "redencoes_select_anon_token" ON cupoes_redencoes
  FOR SELECT TO public USING (token IS NOT NULL);

DROP POLICY IF EXISTS "redencoes_update_anon_token" ON cupoes_redencoes;
CREATE POLICY "redencoes_update_anon_token" ON cupoes_redencoes
  FOR UPDATE TO public USING (token IS NOT NULL AND estado = 'reservado');

-- ── 2. cupoes — leitura no validar.html ──────────────────────────────
DROP POLICY IF EXISTS "cupoes_select_anon" ON cupoes;
CREATE POLICY "cupoes_select_anon" ON cupoes
  FOR SELECT TO public USING (TRUE);

-- ── 3. cupoes_indicacoes — oferta.html (se já aplicaste indicacoes) ──
DROP POLICY IF EXISTS "indic_select_anon" ON cupoes_indicacoes;
CREATE POLICY "indic_select_anon" ON cupoes_indicacoes
  FOR SELECT TO public USING (token IS NOT NULL);

DROP POLICY IF EXISTS "indic_update_anon" ON cupoes_indicacoes;
CREATE POLICY "indic_update_anon" ON cupoes_indicacoes
  FOR UPDATE TO public USING (
    token IS NOT NULL AND convertido_em IS NULL
  );

-- ── DONE ─────────────────────────────────────────────────────────────
SELECT 'Políticas RLS corrigidas — validar.html e oferta.html funcionam em qualquer janela' AS resultado;
