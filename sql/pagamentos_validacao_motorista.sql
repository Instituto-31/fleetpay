-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Validação bilateral de pagamentos (Sessão 2026-05-23)
-- ════════════════════════════════════════════════════════════════════
-- Fluxo:
--   1. Operador marca pagamento como 'pago' (transfere bancariamente)
--   2. Motorista vê na app o pagamento 'pago' + botões:
--        ✓ Confirmo recebimento  → preenche confirmado_motorista_em
--        ⚠️ Não recebi           → preenche contestado_motorista_em + motivo
--   3. Admin vê no painel quais foram confirmados / contestados
--
-- Audit trail completo: timestamps + IP + user agent de cada operação.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE pagamentos
  ADD COLUMN IF NOT EXISTS confirmado_motorista_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS confirmado_motorista_ip TEXT,
  ADD COLUMN IF NOT EXISTS confirmado_motorista_ua TEXT,
  ADD COLUMN IF NOT EXISTS contestado_motorista_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS contestado_motorista_motivo TEXT;

COMMENT ON COLUMN pagamentos.confirmado_motorista_em IS
  'Timestamp em que o motorista confirmou ter recebido o valor transferido.';
COMMENT ON COLUMN pagamentos.contestado_motorista_em IS
  'Timestamp em que o motorista contestou o recebimento. Mutuamente exclusivo com confirmado_motorista_em.';

-- Policy: motorista pode fazer UPDATE no SEU próprio pagamento
DROP POLICY IF EXISTS "pagamentos_motorista_confirmar" ON pagamentos;
CREATE POLICY "pagamentos_motorista_confirmar"
ON pagamentos
FOR UPDATE
TO authenticated
USING (
  motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
)
WITH CHECK (
  motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
);

SELECT 'pagamentos: colunas de validação bilateral + policy criadas' AS resultado;
