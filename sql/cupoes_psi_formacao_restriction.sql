-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Restrição: cupões PSI e Formação só para superadmin
-- ════════════════════════════════════════════════════════════════════
-- Regra de negócio: as categorias 'psi' e 'formacao' são serviços
-- exclusivos do Instituto 31. Outros operadores TVDE clientes do
-- FleetPay não podem criar nem editar cupões dessas categorias.
--
-- Operadores normais continuam a poder:
--   ✅ Criar cupões de combustível, seguro, oficina, slot, serviço, etc.
--   ✅ Ver cupões PSI/Formação (caso o superadmin os tenha publicado
--      para a sua empresa específica)
--   ❌ Criar ou editar cupões de PSI ou Formação
-- ════════════════════════════════════════════════════════════════════

-- INSERT — operador só pode criar se categoria NÃO é psi/formacao
DROP POLICY IF EXISTS "cupoes_insert_op" ON cupoes;
CREATE POLICY "cupoes_insert_op" ON cupoes
  FOR INSERT WITH CHECK (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi', 'formacao')
    )
  );

-- UPDATE — operador só pode editar se categoria NÃO é psi/formacao
-- (USING aplica-se à row antes de UPDATE; WITH CHECK à row depois)
DROP POLICY IF EXISTS "cupoes_update_op" ON cupoes;
CREATE POLICY "cupoes_update_op" ON cupoes
  FOR UPDATE
  USING (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi', 'formacao')
    )
  )
  WITH CHECK (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi', 'formacao')
    )
  );

-- DELETE — mesma regra (operador não apaga PSI/Formação)
DROP POLICY IF EXISTS "cupoes_delete_op" ON cupoes;
CREATE POLICY "cupoes_delete_op" ON cupoes
  FOR DELETE USING (
    get_role() = 'superadmin'
    OR (
      get_role() = 'operador'
      AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
      AND categoria NOT IN ('psi', 'formacao')
    )
  );

-- SELECT mantém-se igual (operadores podem VER cupões psi/formacao
-- que o superadmin tenha publicado para a empresa deles, para que
-- os motoristas possam reservar)

SELECT 'Restrição PSI/Formação aplicada — só superadmin pode criar/editar/apagar essas categorias' AS resultado;
