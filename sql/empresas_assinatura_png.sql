-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Assinatura digital do operador (Sessão 2026-05-23)
-- ════════════════════════════════════════════════════════════════════
-- Adiciona coluna para armazenar a assinatura digital do operador
-- (Flávia / superadmin / operador da empresa). É um PNG em base64
-- (data URL). Carregado uma vez em Admin → Configurações → "A minha
-- assinatura digital" e usado pela Edge Function gerar-pdf-assinado
-- para inserir nos placeholders «ASS_OP» dos templates v3.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE empresas
  ADD COLUMN IF NOT EXISTS assinatura_png TEXT;

COMMENT ON COLUMN empresas.assinatura_png IS
  'Data URL PNG (base64) da assinatura digital do operador. Carregado via Admin → Configurações.';

SELECT 'Coluna empresas.assinatura_png criada' AS resultado;
