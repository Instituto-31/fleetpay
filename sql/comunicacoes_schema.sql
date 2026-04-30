-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Canal interno de comunicação (operador → motoristas)
-- ════════════════════════════════════════════════════════════════════
-- Casos de uso:
--   • Avisos do operador (manutenção, mudanças de regras, novidades)
--   • Anúncios fixados no topo da app do motorista
--   • Comunicações com prioridade (info / aviso / urgente)
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Tabela comunicacoes ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS comunicacoes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

  titulo TEXT NOT NULL,
  mensagem TEXT NOT NULL,

  prioridade TEXT NOT NULL DEFAULT 'info'
    CHECK (prioridade IN ('info','aviso','urgente')),

  -- Estado e visibilidade
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  fixado BOOLEAN NOT NULL DEFAULT FALSE,
  expira_em TIMESTAMPTZ,

  -- Audit
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  criado_por UUID REFERENCES perfis(id)
);

CREATE INDEX IF NOT EXISTS idx_comunicacoes_empresa ON comunicacoes(empresa_id);
CREATE INDEX IF NOT EXISTS idx_comunicacoes_ativo ON comunicacoes(ativo, expira_em);

-- ── 2. Tabela comunicacoes_lidas (registo de leitura por motorista) ──
CREATE TABLE IF NOT EXISTS comunicacoes_lidas (
  comunicacao_id UUID NOT NULL REFERENCES comunicacoes(id) ON DELETE CASCADE,
  motorista_id UUID NOT NULL REFERENCES motoristas(id) ON DELETE CASCADE,
  lido_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (comunicacao_id, motorista_id)
);

CREATE INDEX IF NOT EXISTS idx_com_lidas_motorista ON comunicacoes_lidas(motorista_id);

-- ── 3. RLS ───────────────────────────────────────────────────────────
ALTER TABLE comunicacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE comunicacoes_lidas ENABLE ROW LEVEL SECURITY;

-- Operador/superadmin: CRUD na empresa; motorista: SELECT só dos ativos
DROP POLICY IF EXISTS "comunicacoes_select" ON comunicacoes;
CREATE POLICY "comunicacoes_select" ON comunicacoes
  FOR SELECT USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
    OR (
      ativo = TRUE
      AND (expira_em IS NULL OR expira_em >= NOW())
      AND empresa_id IN (SELECT empresa_id FROM motoristas WHERE perfil_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "comunicacoes_insert" ON comunicacoes;
CREATE POLICY "comunicacoes_insert" ON comunicacoes
  FOR INSERT WITH CHECK (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

DROP POLICY IF EXISTS "comunicacoes_update" ON comunicacoes;
CREATE POLICY "comunicacoes_update" ON comunicacoes
  FOR UPDATE USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

DROP POLICY IF EXISTS "comunicacoes_delete" ON comunicacoes;
CREATE POLICY "comunicacoes_delete" ON comunicacoes
  FOR DELETE USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

-- Lidas: motorista só vê e marca as suas
DROP POLICY IF EXISTS "com_lidas_select" ON comunicacoes_lidas;
CREATE POLICY "com_lidas_select" ON comunicacoes_lidas
  FOR SELECT USING (
    motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
    OR get_role() IN ('operador','superadmin')
  );

DROP POLICY IF EXISTS "com_lidas_insert" ON comunicacoes_lidas;
CREATE POLICY "com_lidas_insert" ON comunicacoes_lidas
  FOR INSERT WITH CHECK (
    motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
  );

-- ── DONE ─────────────────────────────────────────────────────────────
SELECT 'Schema comunicações criado!' AS resultado,
       (SELECT COUNT(*) FROM comunicacoes) AS comunicacoes,
       (SELECT COUNT(*) FROM comunicacoes_lidas) AS lidas;
