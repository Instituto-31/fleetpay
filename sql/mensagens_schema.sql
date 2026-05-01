-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Canal de comunicação directa motorista ↔ operador
-- ════════════════════════════════════════════════════════════════════
-- Diferente das comunicacoes (broadcast operador→todos), aqui é
-- conversa 1-para-1 bidireccional entre operador e motorista.
--
-- Schema:
--   - mensagens: cada linha é UMA mensagem (operador ou motorista escreveu)
--   - autor: 'operador' ou 'motorista' (origem da mensagem)
--   - lida_em: quando o destinatário a abriu (null = não-lida)
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Tabela mensagens ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mensagens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID NOT NULL REFERENCES motoristas(id) ON DELETE CASCADE,

  -- Quem escreveu
  autor TEXT NOT NULL CHECK (autor IN ('operador','motorista','superadmin')),
  autor_perfil_id UUID REFERENCES perfis(id),
  autor_nome TEXT,  -- snapshot do nome no momento (para histórico)

  -- Conteúdo
  mensagem TEXT NOT NULL,

  -- Tracking
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  lida_em TIMESTAMPTZ,  -- quando o destinatário leu

  -- Soft-delete (opcional para v1, útil para futuro)
  apagada_em TIMESTAMPTZ
);

-- ── 2. Indexes para performance ─────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_mensagens_motorista_data ON mensagens(motorista_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_mensagens_empresa ON mensagens(empresa_id);
CREATE INDEX IF NOT EXISTS idx_mensagens_nao_lidas ON mensagens(motorista_id, autor) WHERE lida_em IS NULL;

-- ── 3. RLS ──────────────────────────────────────────────────────────
ALTER TABLE mensagens ENABLE ROW LEVEL SECURITY;

-- SELECT: operador da empresa OU motorista dono da conversa
DROP POLICY IF EXISTS "mensagens_select" ON mensagens;
CREATE POLICY "mensagens_select" ON mensagens
  FOR SELECT USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
    OR motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
  );

-- INSERT: operador da empresa OU motorista escreve em conversa própria
DROP POLICY IF EXISTS "mensagens_insert" ON mensagens;
CREATE POLICY "mensagens_insert" ON mensagens
  FOR INSERT WITH CHECK (
    -- Operador/superadmin escreve em conversa de motorista da sua empresa
    (
      get_role() IN ('operador','superadmin')
      AND autor IN ('operador','superadmin')
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
    )
    -- Motorista escreve em conversa própria
    OR (
      autor = 'motorista'
      AND motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
    )
  );

-- UPDATE: marcar como lida (só destinatário) e apagar (só autor)
DROP POLICY IF EXISTS "mensagens_update" ON mensagens;
CREATE POLICY "mensagens_update" ON mensagens
  FOR UPDATE USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
    OR motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
  );

-- DELETE: só o autor (ou superadmin)
DROP POLICY IF EXISTS "mensagens_delete" ON mensagens;
CREATE POLICY "mensagens_delete" ON mensagens
  FOR DELETE USING (
    get_role() = 'superadmin'
    OR autor_perfil_id = auth.uid()
  );

-- ── 4. Função helper: contar não-lidas por motorista ────────────────
CREATE OR REPLACE FUNCTION mensagens_nao_lidas_motorista(p_motorista_id UUID)
RETURNS INT AS $$
  SELECT COUNT(*)::INT FROM mensagens
  WHERE motorista_id = p_motorista_id
    AND autor IN ('operador','superadmin')
    AND lida_em IS NULL;
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- ── DONE ────────────────────────────────────────────────────────────
SELECT 'Schema mensagens criado!' AS resultado,
       (SELECT COUNT(*) FROM mensagens) AS mensagens_existentes;
