-- =====================================================
-- FleetPay — Merge automático de motoristas duplicados
-- Mantém o motorista com mais histórico (pagamentos +
-- contratos + registos) e migra tudo o resto para esse.
-- O outro fica desactivado (soft delete) — não eliminado.
-- =====================================================

-- ── PASSO 1: Ver duplicados (apenas SELECT, não muda nada) ──
-- SELECT
--   LOWER(TRIM(email)) as email, COUNT(*) qtd,
--   array_agg(id ORDER BY criado_em) ids,
--   array_agg(nome ORDER BY criado_em) nomes
-- FROM motoristas WHERE ativo = true AND email IS NOT NULL
-- GROUP BY LOWER(TRIM(email)) HAVING COUNT(*) > 1;

-- ── PASSO 2: Merge automático ──
-- Para cada email duplicado, escolhe o "vencedor" (mais histórico)
-- e migra pagamentos/contratos/registos/prio/viaverde/documentos.

DO $$
DECLARE
  r_email       text;
  r_winner_id   uuid;
  r_loser_id    uuid;
  r_loser_ids   uuid[];
BEGIN
  FOR r_email IN
    SELECT LOWER(TRIM(email))
    FROM motoristas
    WHERE ativo = true AND email IS NOT NULL
    GROUP BY LOWER(TRIM(email))
    HAVING COUNT(*) > 1
  LOOP
    -- escolhe winner: o que tem mais pagamentos + contratos + perfil_id ligado
    SELECT id INTO r_winner_id FROM (
      SELECT m.id,
        (SELECT COUNT(*) FROM pagamentos p WHERE p.motorista_id = m.id) +
        (SELECT COUNT(*) FROM contratos c WHERE c.motorista_id = m.id) * 2 +
        (CASE WHEN m.perfil_id IS NOT NULL THEN 100 ELSE 0 END) as score,
        m.criado_em
      FROM motoristas m
      WHERE LOWER(TRIM(m.email)) = r_email AND m.ativo = true
      ORDER BY score DESC, m.criado_em ASC
      LIMIT 1
    ) sub;

    -- ids perdedores (todos menos o winner)
    SELECT array_agg(id) INTO r_loser_ids
    FROM motoristas
    WHERE LOWER(TRIM(email)) = r_email
      AND ativo = true
      AND id <> r_winner_id;

    RAISE NOTICE 'merge % | winner=% | losers=%', r_email, r_winner_id, r_loser_ids;

    -- migra dependências SE existirem essas tabelas
    -- pagamentos
    UPDATE pagamentos SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    -- contratos
    UPDATE contratos SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    -- veículos (se motorista_id tiver FK aqui)
    BEGIN
      UPDATE veiculos SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
    -- registos de condução
    BEGIN
      UPDATE registos_conducao SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
    -- prio
    BEGIN
      UPDATE prio_carregamentos SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
    -- via verde
    BEGIN
      UPDATE viaverde_movimentos SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
    -- documentos
    BEGIN
      UPDATE documentos SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
    -- termos aceitacoes
    BEGIN
      UPDATE termos_aceitacoes SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
    -- mensagens
    BEGIN
      UPDATE mensagens SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
    -- compliance checklists
    BEGIN
      UPDATE compliance_checklists SET motorista_id = r_winner_id WHERE motorista_id = ANY(r_loser_ids);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

    -- desactiva perdedores (soft delete, preserva auditoria)
    UPDATE motoristas
    SET ativo = false,
        nome = nome || ' [merged → ' || r_winner_id::text || ']'
    WHERE id = ANY(r_loser_ids);
  END LOOP;
END $$;

-- ── PASSO 3: Constraint UNIQUE para PREVENIR futuros duplicados ──
-- Só permite 1 motorista activo por email por empresa
CREATE UNIQUE INDEX IF NOT EXISTS uq_motoristas_email_empresa_ativo
  ON motoristas (LOWER(TRIM(email)), empresa_id)
  WHERE ativo = true AND email IS NOT NULL AND TRIM(email) <> '';

-- ── PASSO 4: Verificação final ──
SELECT
  (SELECT COUNT(*) FROM motoristas WHERE ativo = true) as motoristas_ativos,
  (SELECT COUNT(*) FROM (
    SELECT LOWER(TRIM(email)) FROM motoristas
    WHERE ativo = true AND email IS NOT NULL
    GROUP BY LOWER(TRIM(email)) HAVING COUNT(*) > 1
  ) x) as duplicados_restantes;
