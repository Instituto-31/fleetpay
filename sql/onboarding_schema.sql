-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Onboarding wizard tracking
-- ════════════════════════════════════════════════════════════════════
-- Quando uma empresa entra no FleetPay pela primeira vez, é redireccionada
-- para um wizard de 6 passos antes de poder usar o admin. Cada passo é
-- guardado imediatamente para que possa retomar onde parou.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE empresas
  ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS onboarding_step INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS plataformas_usadas JSONB DEFAULT '[]'::jsonb;

-- Empresas existentes (Inst31 + Inst31.1) já estão configuradas — marcamos como concluídas
UPDATE empresas
  SET onboarding_completed = TRUE,
      onboarding_completed_at = NOW()
  WHERE onboarding_completed = FALSE
    AND nome IS NOT NULL
    AND nipc IS NOT NULL;

SELECT 'Schema onboarding criado!' AS resultado,
       (SELECT COUNT(*) FROM empresas WHERE onboarding_completed) AS empresas_completed,
       (SELECT COUNT(*) FROM empresas WHERE NOT onboarding_completed) AS empresas_pendentes;
