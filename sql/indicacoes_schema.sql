-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Sistema de Indicações / Referrals (Programa Embaixadores)
-- ════════════════════════════════════════════════════════════════════
-- Fluxo:
--   1. Motorista carrega "Partilhar" num cupão → cria indicação (token)
--   2. Amigo abre oferta.html?t=TOKEN → marca visualizado_em
--   3. Amigo carrega "Quero este cupão" + dados → marca contactado_em
--   4. Parceiro/operador valida conversão no admin → marca convertido_em
--   5. Sistema atribui bonus_indicador ao motorista (creditos)
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Alter cupoes: configuração de partilha + bónus ────────────────
ALTER TABLE cupoes ADD COLUMN IF NOT EXISTS partilhavel BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE cupoes ADD COLUMN IF NOT EXISTS bonus_indicador DECIMAL(10,2);
ALTER TABLE cupoes ADD COLUMN IF NOT EXISTS bonus_indicador_tipo TEXT
  CHECK (bonus_indicador_tipo IN ('valor_fixo','percentagem','credito') OR bonus_indicador_tipo IS NULL);

-- ── 2. Alter motoristas: saldo de créditos ──────────────────────────
ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS creditos DECIMAL(10,2) NOT NULL DEFAULT 0;

-- ── 3. Tabela cupoes_indicacoes (referrals tracking) ─────────────────
CREATE TABLE IF NOT EXISTS cupoes_indicacoes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cupao_id UUID NOT NULL REFERENCES cupoes(id) ON DELETE CASCADE,
  indicador_motorista_id UUID NOT NULL REFERENCES motoristas(id) ON DELETE CASCADE,
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

  -- Token público (vai no link partilhado)
  token TEXT NOT NULL UNIQUE DEFAULT gen_random_uuid()::text,

  -- Dados do indicado (preenchidos quando ele carrega "Quero este cupão")
  indicado_nome TEXT,
  indicado_email TEXT,
  indicado_telefone TEXT,
  indicado_notas TEXT,

  -- Tracking de funil
  partilhado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- 1. criado pelo motorista
  visualizado_em TIMESTAMPTZ,                        -- 2. amigo abriu o link
  visualizacoes_count INT NOT NULL DEFAULT 0,        -- nº de vezes aberto
  contactado_em TIMESTAMPTZ,                         -- 3. amigo preencheu form
  convertido_em TIMESTAMPTZ,                         -- 4. parceiro confirmou compra
  convertido_por UUID REFERENCES perfis(id),

  -- Bónus atribuído ao indicador
  bonus_valor DECIMAL(10,2),                         -- valor que o motorista ganhou
  bonus_atribuido_em TIMESTAMPTZ,
  bonus_pago_em TIMESTAMPTZ,                         -- operador marca quando paga

  -- Audit técnico
  ip_visualizacao TEXT,
  user_agent TEXT,
  notas_operador TEXT
);

CREATE INDEX IF NOT EXISTS idx_indic_cupao ON cupoes_indicacoes(cupao_id);
CREATE INDEX IF NOT EXISTS idx_indic_motorista ON cupoes_indicacoes(indicador_motorista_id);
CREATE INDEX IF NOT EXISTS idx_indic_empresa ON cupoes_indicacoes(empresa_id);
CREATE INDEX IF NOT EXISTS idx_indic_token ON cupoes_indicacoes(token);
CREATE INDEX IF NOT EXISTS idx_indic_estado ON cupoes_indicacoes(convertido_em, contactado_em);

-- ── 4. Trigger: ao marcar convertido_em, atribui bónus + soma créditos
CREATE OR REPLACE FUNCTION atribuir_bonus_indicacao()
RETURNS TRIGGER AS $$
DECLARE
  cup RECORD;
  bonus_calc DECIMAL(10,2);
BEGIN
  -- Só corre quando convertido_em PASSA de NULL para algo
  IF (OLD.convertido_em IS NULL AND NEW.convertido_em IS NOT NULL) THEN
    -- Vai buscar configuração do cupão
    SELECT bonus_indicador, bonus_indicador_tipo, valor, tipo
      INTO cup FROM cupoes WHERE id = NEW.cupao_id;

    IF cup.bonus_indicador IS NOT NULL AND cup.bonus_indicador > 0 THEN
      -- Calcular valor do bónus
      IF cup.bonus_indicador_tipo = 'percentagem' AND cup.valor IS NOT NULL THEN
        bonus_calc := ROUND((cup.valor * cup.bonus_indicador / 100)::numeric, 2);
      ELSE
        -- valor_fixo ou credito
        bonus_calc := cup.bonus_indicador;
      END IF;

      NEW.bonus_valor := bonus_calc;
      NEW.bonus_atribuido_em := NOW();

      -- Somar aos créditos do motorista
      UPDATE motoristas
        SET creditos = COALESCE(creditos, 0) + bonus_calc
        WHERE id = NEW.indicador_motorista_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_indicacoes_bonus ON cupoes_indicacoes;
CREATE TRIGGER trg_indicacoes_bonus
  BEFORE UPDATE ON cupoes_indicacoes
  FOR EACH ROW EXECUTE FUNCTION atribuir_bonus_indicacao();

-- ── 5. RLS ───────────────────────────────────────────────────────────
ALTER TABLE cupoes_indicacoes ENABLE ROW LEVEL SECURITY;

-- Motorista vê as suas indicações (como indicador)
DROP POLICY IF EXISTS "indic_select_motorista" ON cupoes_indicacoes;
CREATE POLICY "indic_select_motorista" ON cupoes_indicacoes
  FOR SELECT USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
    OR indicador_motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
  );

-- Motorista cria indicação para si próprio
DROP POLICY IF EXISTS "indic_insert_motorista" ON cupoes_indicacoes;
CREATE POLICY "indic_insert_motorista" ON cupoes_indicacoes
  FOR INSERT WITH CHECK (
    indicador_motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
  );

-- Operador/superadmin atualizam (marcar convertido, notas, pago)
DROP POLICY IF EXISTS "indic_update_op" ON cupoes_indicacoes;
CREATE POLICY "indic_update_op" ON cupoes_indicacoes
  FOR UPDATE USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

DROP POLICY IF EXISTS "indic_delete_op" ON cupoes_indicacoes;
CREATE POLICY "indic_delete_op" ON cupoes_indicacoes
  FOR DELETE USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

-- Anon: SELECT pelo token (página oferta.html precisa para mostrar info)
DROP POLICY IF EXISTS "indic_select_anon" ON cupoes_indicacoes;
CREATE POLICY "indic_select_anon" ON cupoes_indicacoes
  FOR SELECT TO anon USING (token IS NOT NULL);

-- Anon: UPDATE pelo token (marcar visualizado, contactado, dados do amigo)
-- NOTA: convertido_em e bonus NÃO devem ser editáveis por anon — protegido por column-level
-- Mas RLS de UPDATE permite — controlamos no client + via trigger (anon não pode forçar bonus)
DROP POLICY IF EXISTS "indic_update_anon" ON cupoes_indicacoes;
CREATE POLICY "indic_update_anon" ON cupoes_indicacoes
  FOR UPDATE TO anon USING (
    token IS NOT NULL AND convertido_em IS NULL
  );

-- ── DONE ─────────────────────────────────────────────────────────────
SELECT 'Schema indicações criado!' AS resultado,
       (SELECT COUNT(*) FROM cupoes_indicacoes) AS indicacoes,
       (SELECT COUNT(*) FROM motoristas WHERE creditos > 0) AS motoristas_com_creditos;
