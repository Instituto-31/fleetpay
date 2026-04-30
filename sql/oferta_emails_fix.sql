-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Fix para emails de oferta (Edge Function send-oferta-emails)
-- ════════════════════════════════════════════════════════════════════
-- Adiciona coluna de idempotência para evitar reenvio de email se a
-- página oferta.html for refrescada ou o form for submetido novamente.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE cupoes_indicacoes
  ADD COLUMN IF NOT EXISTS email_enviado_em TIMESTAMPTZ;

-- Garantir que empresa tem email (caso falte)
ALTER TABLE empresas
  ADD COLUMN IF NOT EXISTS email TEXT;

SELECT 'Schema atualizado para emails automáticos' AS resultado;
