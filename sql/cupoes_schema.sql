-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Sistema de Cupões (cross-selling)
-- ════════════════════════════════════════════════════════════════════
-- Casos de uso:
--   • Operador → motorista: PSI, formações, slots, cursos atualização
--   • Parceiros externos: combustível, seguros, oficinas
--   • Operador → operador: parcerias, partilha de slots/motoristas
--   • Plataforma → operadores: descontos plano Pro/Enterprise
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Tabela cupoes (catálogo) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS cupoes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

  -- Identificação
  codigo TEXT NOT NULL,
  titulo TEXT NOT NULL,
  descricao TEXT,

  -- Tipo desconto
  tipo TEXT NOT NULL CHECK (tipo IN ('percentagem','valor_fixo','gratis','oferta')),
  valor DECIMAL(10,2),  -- % se percentagem; € se valor_fixo; NULL se gratis/oferta
  valor_minimo DECIMAL(10,2),  -- compra mínima para usar

  -- Categoria/parceiro
  categoria TEXT NOT NULL CHECK (categoria IN ('psi','formacao','slot','combustivel','seguro','oficina','saas','servico','outro')),
  parceiro_nome TEXT,
  parceiro_logo_path TEXT,
  parceiro_link TEXT,
  parceiro_morada TEXT,
  parceiro_telefone TEXT,

  -- Validade
  valido_desde DATE DEFAULT CURRENT_DATE,
  valido_ate DATE,

  -- Limites
  max_utilizacoes INT,                       -- NULL = ilimitado
  utilizacoes_count INT NOT NULL DEFAULT 0,  -- contador atualizado por trigger
  max_por_motorista INT NOT NULL DEFAULT 1,  -- normalmente 1 cupão por pessoa

  -- Público-alvo (flags)
  para_motoristas BOOLEAN NOT NULL DEFAULT TRUE,
  para_operadores BOOLEAN NOT NULL DEFAULT FALSE,

  -- Estado
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  destaque BOOLEAN NOT NULL DEFAULT FALSE,

  -- Audit
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  criado_por UUID REFERENCES perfis(id),

  CONSTRAINT cupoes_codigo_empresa_uq UNIQUE (empresa_id, codigo)
);

CREATE INDEX IF NOT EXISTS idx_cupoes_empresa ON cupoes(empresa_id);
CREATE INDEX IF NOT EXISTS idx_cupoes_ativo_validade ON cupoes(ativo, valido_ate);
CREATE INDEX IF NOT EXISTS idx_cupoes_categoria ON cupoes(categoria);

-- ── 2. Tabela cupoes_redencoes (audit + tokens) ──────────────────────
CREATE TABLE IF NOT EXISTS cupoes_redencoes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cupao_id UUID NOT NULL REFERENCES cupoes(id) ON DELETE CASCADE,
  motorista_id UUID REFERENCES motoristas(id),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

  -- Token único shareable com o parceiro (UUID v4 = unguessable)
  token TEXT NOT NULL UNIQUE DEFAULT gen_random_uuid()::text,

  -- Estado
  estado TEXT NOT NULL DEFAULT 'reservado' CHECK (estado IN ('reservado','usado','expirado','cancelado')),

  reservado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  usado_em TIMESTAMPTZ,

  -- Validação parceiro (preenchido quando confirma utilização em validar.html)
  validado_por TEXT,
  validado_ip TEXT,
  validado_user_agent TEXT,
  notas TEXT
);

CREATE INDEX IF NOT EXISTS idx_redencoes_cupao ON cupoes_redencoes(cupao_id);
CREATE INDEX IF NOT EXISTS idx_redencoes_motorista ON cupoes_redencoes(motorista_id);
CREATE INDEX IF NOT EXISTS idx_redencoes_token ON cupoes_redencoes(token);
CREATE INDEX IF NOT EXISTS idx_redencoes_estado ON cupoes_redencoes(estado);

-- ── 3. Trigger: atualizar contador no cupão quando redenção muda ─────
CREATE OR REPLACE FUNCTION atualizar_contador_cupao()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.estado IN ('reservado','usado') THEN
    UPDATE cupoes SET utilizacoes_count = utilizacoes_count + 1 WHERE id = NEW.cupao_id;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Se passou de reservado para cancelado, decrementar
    IF OLD.estado IN ('reservado','usado') AND NEW.estado IN ('cancelado','expirado') THEN
      UPDATE cupoes SET utilizacoes_count = GREATEST(0, utilizacoes_count - 1) WHERE id = NEW.cupao_id;
    END IF;
  ELSIF TG_OP = 'DELETE' AND OLD.estado IN ('reservado','usado') THEN
    UPDATE cupoes SET utilizacoes_count = GREATEST(0, utilizacoes_count - 1) WHERE id = OLD.cupao_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cupoes_redencoes_contador ON cupoes_redencoes;
CREATE TRIGGER trg_cupoes_redencoes_contador
  AFTER INSERT OR UPDATE OR DELETE ON cupoes_redencoes
  FOR EACH ROW EXECUTE FUNCTION atualizar_contador_cupao();

-- ── 4. RLS ───────────────────────────────────────────────────────────
ALTER TABLE cupoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE cupoes_redencoes ENABLE ROW LEVEL SECURITY;

-- Cupões: operador/superadmin vê os da sua empresa; motorista vê os ativos da sua empresa
DROP POLICY IF EXISTS "cupoes_select_op" ON cupoes;
CREATE POLICY "cupoes_select_op" ON cupoes
  FOR SELECT USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
    OR (
      ativo = TRUE
      AND (valido_ate IS NULL OR valido_ate >= CURRENT_DATE)
      AND empresa_id IN (SELECT empresa_id FROM motoristas WHERE perfil_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "cupoes_insert_op" ON cupoes;
CREATE POLICY "cupoes_insert_op" ON cupoes
  FOR INSERT WITH CHECK (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

DROP POLICY IF EXISTS "cupoes_update_op" ON cupoes;
CREATE POLICY "cupoes_update_op" ON cupoes
  FOR UPDATE USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

DROP POLICY IF EXISTS "cupoes_delete_op" ON cupoes;
CREATE POLICY "cupoes_delete_op" ON cupoes
  FOR DELETE USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
  );

-- Redenções: motorista vê as suas; operador/superadmin vê as da sua empresa
DROP POLICY IF EXISTS "redencoes_select" ON cupoes_redencoes;
CREATE POLICY "redencoes_select" ON cupoes_redencoes
  FOR SELECT USING (
    get_role() = 'superadmin'
    OR (get_role() = 'operador' AND empresa_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid()))
    OR motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid())
  );

DROP POLICY IF EXISTS "redencoes_insert" ON cupoes_redencoes;
CREATE POLICY "redencoes_insert" ON cupoes_redencoes
  FOR INSERT WITH CHECK (
    -- Motorista pode reservar para si próprio
    (motorista_id IN (SELECT id FROM motoristas WHERE perfil_id = auth.uid()))
    OR get_role() IN ('operador','superadmin')
  );

-- Validação por parceiro: anon pode SELECT/UPDATE quando passa o token
DROP POLICY IF EXISTS "redencoes_select_anon_token" ON cupoes_redencoes;
CREATE POLICY "redencoes_select_anon_token" ON cupoes_redencoes
  FOR SELECT TO anon USING (token IS NOT NULL);

DROP POLICY IF EXISTS "redencoes_update_anon_token" ON cupoes_redencoes;
CREATE POLICY "redencoes_update_anon_token" ON cupoes_redencoes
  FOR UPDATE TO anon USING (token IS NOT NULL AND estado = 'reservado');

-- Cupão: anon pode SELECT (precisa para mostrar info no validar.html)
DROP POLICY IF EXISTS "cupoes_select_anon" ON cupoes;
CREATE POLICY "cupoes_select_anon" ON cupoes
  FOR SELECT TO anon USING (TRUE);

-- ── 5. Bucket Storage para logos de parceiros (público) ──────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('cupoes-logos', 'cupoes-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Policies Storage
DROP POLICY IF EXISTS "cupoes_logos_read" ON storage.objects;
CREATE POLICY "cupoes_logos_read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'cupoes-logos');

DROP POLICY IF EXISTS "cupoes_logos_write_op" ON storage.objects;
CREATE POLICY "cupoes_logos_write_op" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (
    bucket_id = 'cupoes-logos'
    AND get_role() IN ('operador','superadmin')
  );

DROP POLICY IF EXISTS "cupoes_logos_delete_op" ON storage.objects;
CREATE POLICY "cupoes_logos_delete_op" ON storage.objects
  FOR DELETE TO authenticated USING (
    bucket_id = 'cupoes-logos'
    AND get_role() IN ('operador','superadmin')
  );

-- ── 6. Cupões iniciais para Instituto 31 (PSI, formações) ────────────
-- Dois cupões pré-populados — apaga se não quiseres
DO $$
DECLARE
  inst31_id UUID;
BEGIN
  SELECT id INTO inst31_id FROM empresas WHERE nipc = '517069234' OR nome ILIKE '%Instituto 31%' LIMIT 1;
  IF inst31_id IS NOT NULL THEN
    INSERT INTO cupoes (empresa_id, codigo, titulo, descricao, tipo, valor, categoria, parceiro_nome, parceiro_link, valido_ate, max_por_motorista, destaque)
    VALUES
      (inst31_id, 'PSI-GRUPO2-10', '10% desconto Avaliação PSI Grupo 2',
       'Desconto na avaliação psicológica para averbamento ao Grupo 2 da carta de condução (obrigatória para TVDE).',
       'percentagem', 10, 'psi', 'Instituto 31 — PSI', 'https://instituto31.pt',
       (CURRENT_DATE + INTERVAL '6 months')::date, 1, TRUE),
      (inst31_id, 'FORM-TVDE-INI-15', '15€ desconto Formação TVDE Inicial',
       'Desconto na formação inicial obrigatória para motoristas TVDE.',
       'valor_fixo', 15, 'formacao', 'Instituto 31 — Formação', 'https://instituto31.pt',
       (CURRENT_DATE + INTERVAL '6 months')::date, 1, FALSE)
    ON CONFLICT (empresa_id, codigo) DO NOTHING;
  END IF;
END $$;

-- ── DONE ─────────────────────────────────────────────────────────────
SELECT 'Schema cupões criado!' AS resultado,
       (SELECT COUNT(*) FROM cupoes) AS cupoes_criados,
       (SELECT COUNT(*) FROM cupoes_redencoes) AS redencoes;
