-- =====================================================
-- FleetPay — Notificações enviadas (audit + dedupe)
-- =====================================================

CREATE TABLE IF NOT EXISTS notificacoes_enviadas (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID REFERENCES motoristas(id) ON DELETE SET NULL,
  -- tipo: pagamento_criado | pagamento_pago | documento_expira | termo_novo
  tipo TEXT NOT NULL,
  -- referência ao objecto que originou (ex: pagamento_id, documento_id)
  referencia_id UUID,
  canal TEXT NOT NULL DEFAULT 'email',  -- email | whatsapp | push | sms
  destino TEXT,                          -- email/telefone usado
  assunto TEXT,
  enviado_em TIMESTAMPTZ DEFAULT NOW(),
  sucesso BOOLEAN DEFAULT TRUE,
  erro TEXT,
  resposta_provider JSONB
);

CREATE INDEX IF NOT EXISTS idx_notif_motorista ON notificacoes_enviadas(motorista_id, tipo, referencia_id);
CREATE INDEX IF NOT EXISTS idx_notif_empresa ON notificacoes_enviadas(empresa_id, enviado_em DESC);

-- Constraint: não duplica o mesmo email
-- (mesmo motorista + mesmo tipo + mesma referência = só 1)
CREATE UNIQUE INDEX IF NOT EXISTS uq_notif_dedupe
  ON notificacoes_enviadas(motorista_id, tipo, referencia_id, canal)
  WHERE sucesso = TRUE AND referencia_id IS NOT NULL;

ALTER TABLE notificacoes_enviadas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notif_operador_all ON notificacoes_enviadas;
CREATE POLICY notif_operador_all ON notificacoes_enviadas
  FOR ALL TO authenticated
  USING (
    get_role() IN ('operador','admin','superadmin')
    AND (
      get_role() = 'superadmin'
      OR empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
    )
  )
  WITH CHECK (
    get_role() IN ('operador','admin','superadmin')
    AND (
      get_role() = 'superadmin'
      OR empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
    )
  );
