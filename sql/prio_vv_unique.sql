-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Impedir duplicados PRIO + Via Verde (Sessão 2026-05-24)
-- ════════════════════════════════════════════════════════════════════
-- Problema: re-carregar o mesmo CSV duplicava todos os carregamentos.
-- Solução: UNIQUE constraint + UPSERT no código com ignoreDuplicates.
-- ════════════════════════════════════════════════════════════════════

-- 1. Apagar duplicados existentes (manter 1 por chave)
DELETE FROM prio_carregamentos a
USING prio_carregamentos b
WHERE a.id > b.id
  AND a.empresa_id = b.empresa_id
  AND a.matricula = b.matricula
  AND a.data = b.data
  AND a.valor = b.valor;

DELETE FROM viaverde_portagens a
USING viaverde_portagens b
WHERE a.id > b.id
  AND a.empresa_id = b.empresa_id
  AND a.matricula = b.matricula
  AND a.data = b.data
  AND a.valor = b.valor
  AND COALESCE(a.descricao,'') = COALESCE(b.descricao,'');

-- 2. UNIQUE constraints
ALTER TABLE prio_carregamentos
  DROP CONSTRAINT IF EXISTS uq_prio_unico;
ALTER TABLE prio_carregamentos
  ADD CONSTRAINT uq_prio_unico
  UNIQUE (empresa_id, matricula, data, valor);

ALTER TABLE viaverde_portagens
  DROP CONSTRAINT IF EXISTS uq_viaverde_unico;
ALTER TABLE viaverde_portagens
  ADD CONSTRAINT uq_viaverde_unico
  UNIQUE (empresa_id, matricula, data, valor);

SELECT 'PRIO + Via Verde: duplicados apagados + UNIQUE constraint criada' AS resultado;
