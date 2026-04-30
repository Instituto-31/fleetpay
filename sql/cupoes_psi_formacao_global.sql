-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Cupões PSI/Formação são GLOBAIS (cross-sell Instituto 31)
-- ════════════════════════════════════════════════════════════════════
-- Regra de negócio:
--   ✅ SUPERADMIN cria/edita/apaga cupões PSI/Formação
--   ✅ MOTORISTAS de QUALQUER empresa vêm + reservam esses cupões
--   ✅ OPERADORES de QUALQUER empresa vêm esses cupões na lista
--      (com badge 🔒 INST 31, sem poder editar)
--   ❌ OPERADORES não podem criar/editar PSI ou Formação
--
-- Caso de uso: o Instituto 31 vende PSI (avaliações psicológicas) e
-- Formações TVDE como cross-sell. Motoristas de operadores clientes
-- do FleetPay devem poder ver e reservar essas ofertas para se
-- candidatarem aos serviços.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. SELECT em cupoes: PSI/Formação visíveis a todos ──────────────
DROP POLICY IF EXISTS "cupoes_select_op" ON cupoes;
CREATE POLICY "cupoes_select_op" ON cupoes
  FOR SELECT USING (
    -- Superadmin vê tudo
    get_role() = 'superadmin'
    -- Operador vê cupões da sua empresa + cupões PSI/Formação activos de qualquer empresa
    OR (
      get_role() = 'operador'
      AND (
        empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
        OR (categoria IN ('psi','formacao') AND ativo = TRUE)
      )
    )
    -- Motorista vê cupões activos da sua empresa + PSI/Formação activos de qualquer empresa
    OR (
      ativo = TRUE
      AND (valido_ate IS NULL OR valido_ate >= CURRENT_DATE)
      AND (
        empresa_id IN (SELECT empresa_id FROM motoristas WHERE perfil_id = auth.uid())
        OR categoria IN ('psi','formacao')
      )
    )
  );

-- ── 2. INSERT em cupoes_redencoes: motorista pode reservar cross-empresa ──
DROP POLICY IF EXISTS "redencoes_insert" ON cupoes_redencoes;
CREATE POLICY "redencoes_insert" ON cupoes_redencoes
  FOR INSERT WITH CHECK (
    -- Motorista reserva para si próprio um cupão visível (RLS SELECT cobre cross-empresa)
    (
      motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
      AND cupao_id IN (
        SELECT id FROM cupoes
        WHERE ativo = TRUE
          AND (valido_ate IS NULL OR valido_ate >= CURRENT_DATE)
          AND (
            empresa_id IN (SELECT empresa_id FROM motoristas WHERE perfil_id = auth.uid())
            OR categoria IN ('psi','formacao')
          )
      )
    )
    -- Operador/superadmin sempre podem
    OR get_role() IN ('operador','superadmin')
  );

-- ── 3. INSERT em cupoes_indicacoes: motorista pode partilhar cross-empresa ──
DROP POLICY IF EXISTS "indic_insert_motorista" ON cupoes_indicacoes;
CREATE POLICY "indic_insert_motorista" ON cupoes_indicacoes
  FOR INSERT WITH CHECK (
    indicador_motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
    -- E o cupão tem que ser visível ao motorista (sua empresa OU cross-empresas)
    AND cupao_id IN (
      SELECT id FROM cupoes
      WHERE ativo = TRUE
        AND partilhavel = TRUE
        AND (
          empresa_id IN (SELECT empresa_id FROM motoristas WHERE perfil_id = auth.uid())
          OR categoria IN ('psi','formacao')
        )
    )
  );

-- ── 4. INSERT/UPDATE/DELETE de cupoes mantém restrição ───────────────
-- (já aplicado no script anterior cupoes_psi_formacao_restriction.sql,
-- mas re-aplicamos para garantir idempotência)

DROP POLICY IF EXISTS "cupoes_insert_op" ON cupoes;
CREATE POLICY "cupoes_insert_op" ON cupoes
  FOR INSERT WITH CHECK (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi','formacao')
    )
  );

DROP POLICY IF EXISTS "cupoes_update_op" ON cupoes;
CREATE POLICY "cupoes_update_op" ON cupoes
  FOR UPDATE
  USING (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi','formacao')
    )
  )
  WITH CHECK (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi','formacao')
    )
  );

DROP POLICY IF EXISTS "cupoes_delete_op" ON cupoes;
CREATE POLICY "cupoes_delete_op" ON cupoes
  FOR DELETE USING (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi','formacao')
    )
  );

SELECT 'Cupões PSI/Formação agora globais — visíveis a todas as empresas (cross-sell), mas só superadmin pode criar/editar' AS resultado;
