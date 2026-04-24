-- ============================================================
-- FLEETPAY — Schema SQL Completo para Supabase
-- Copia este ficheiro e executa no SQL Editor do Supabase
-- Project: udqddasbfqbeeaxtnsoj
-- ============================================================

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. EMPRESAS (multi-tenant)
-- ============================================================
CREATE TABLE empresas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nome TEXT NOT NULL,
  nif TEXT UNIQUE,
  email TEXT,
  telefone TEXT,
  morada TEXT,
  logo_url TEXT,
  plano TEXT DEFAULT 'gratuito' CHECK (plano IN ('gratuito','pro','enterprise')),
  plano_motoristas_max INT DEFAULT 3,
  -- Integrações API
  bolt_client_id TEXT,
  bolt_client_secret TEXT,
  bolt_api_ativo BOOLEAN DEFAULT false,
  uber_api_token TEXT,
  uber_org_id TEXT,
  uber_api_ativo BOOLEAN DEFAULT false,
  -- Configurações globais
  iva_uber_pct NUMERIC(5,2) DEFAULT 23,
  slot_semanal_default NUMERIC(10,2) DEFAULT 0,
  -- Metadados
  ativo BOOLEAN DEFAULT true,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. PERFIS (ligados ao Supabase Auth)
-- ============================================================
CREATE TABLE perfis (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id UUID REFERENCES empresas(id),
  role TEXT DEFAULT 'motorista' CHECK (role IN ('superadmin','operador','motorista')),
  nome TEXT,
  email TEXT,
  telefone TEXT,
  avatar_url TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. MOTORISTAS
-- ============================================================
CREATE TABLE motoristas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  perfil_id UUID REFERENCES perfis(id), -- NULL até ter login
  nome TEXT NOT NULL,
  email TEXT,
  telefone TEXT,
  whatsapp TEXT,
  nif TEXT,
  iban TEXT,
  morada TEXT,
  -- Dados TVDE
  licenca_tvde TEXT,
  licenca_tvde_validade DATE,
  carta_conducao TEXT,
  carta_conducao_validade DATE,
  cartao_cidadao_validade DATE,
  registo_criminal_validade DATE,
  cert_motorista_tvde_validade DATE,
  -- Configurações financeiras
  slot_semanal NUMERIC(10,2) DEFAULT 0,
  aluguer_semanal NUMERIC(10,2) DEFAULT 0,
  iva_pct NUMERIC(5,2) DEFAULT 23,
  -- Dados de associação às plataformas
  uber_driver_id TEXT,
  bolt_driver_id TEXT,
  -- Estado
  ativo BOOLEAN DEFAULT true,
  notas TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. VEÍCULOS (frota)
-- ============================================================
CREATE TABLE veiculos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  matricula TEXT NOT NULL,
  marca TEXT,
  modelo TEXT,
  ano INT,
  cor TEXT,
  tipo TEXT DEFAULT 'electrico' CHECK (tipo IN ('electrico','hibrido','combustao')),
  estado TEXT DEFAULT 'ativo' CHECK (estado IN ('ativo','manutencao','inativo')),
  -- Motorista atual
  motorista_id UUID REFERENCES motoristas(id),
  -- Documentos
  seguro_validade DATE,
  inspecao_validade DATE,
  extintor_validade DATE,
  -- Manutenção
  km_atuais INT DEFAULT 0,
  ultima_revisao_data DATE,
  ultima_revisao_km INT,
  proxima_revisao_km INT,
  proxima_revisao_data DATE,
  custo_ultima_manutencao NUMERIC(10,2),
  descricao_ultima_manutencao TEXT,
  -- Via Verde
  via_verde_id TEXT,
  -- Metadados
  notas TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. PAGAMENTOS SEMANAIS
-- ============================================================
CREATE TABLE pagamentos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID NOT NULL REFERENCES motoristas(id),
  veiculo_id UUID REFERENCES veiculos(id),
  semana_inicio DATE NOT NULL,
  semana_fim DATE NOT NULL,
  -- Origem dos dados
  origem TEXT DEFAULT 'csv' CHECK (origem IN ('csv','api','manual')),
  -- UBER
  uber_bruto NUMERIC(10,2) DEFAULT 0,
  uber_iva_pct NUMERIC(5,2) DEFAULT 23,
  uber_iva_valor NUMERIC(10,2) DEFAULT 0,
  uber_liquido NUMERIC(10,2) DEFAULT 0,
  -- BOLT
  bolt_bruto NUMERIC(10,2) DEFAULT 0,
  bolt_iva NUMERIC(10,2) DEFAULT 0,
  bolt_taxa NUMERIC(10,2) DEFAULT 0,
  bolt_liquido NUMERIC(10,2) DEFAULT 0,
  -- IVA a cobrar (ao motorista)
  iva_cobrar NUMERIC(10,2) DEFAULT 0,
  -- Rendimento líquido total antes de despesas
  rendimento_liquido NUMERIC(10,2) DEFAULT 0,
  -- Despesas
  slot_valor NUMERIC(10,2) DEFAULT 0,
  aluguer_valor NUMERIC(10,2) DEFAULT 0,
  prio_valor NUMERIC(10,2) DEFAULT 0,
  viaverde_valor NUMERIC(10,2) DEFAULT 0,
  outros_descontos NUMERIC(10,2) DEFAULT 0,
  total_despesas NUMERIC(10,2) DEFAULT 0,
  -- Valor final a pagar ao motorista
  valor_final NUMERIC(10,2) DEFAULT 0,
  -- Estado
  estado TEXT DEFAULT 'pendente' CHECK (estado IN ('pendente','pago','cancelado')),
  data_pagamento TIMESTAMPTZ,
  referencia_transferencia TEXT,
  -- Recibo
  recibo_pdf_url TEXT,
  recibo_enviado_em TIMESTAMPTZ,
  recibo_enviado_via TEXT, -- 'email','whatsapp'
  -- Metadados
  notas TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, motorista_id, semana_inicio)
);

-- ============================================================
-- 6. CARREGAMENTOS PRIO
-- ============================================================
CREATE TABLE prio_carregamentos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID REFERENCES motoristas(id),
  veiculo_id UUID REFERENCES veiculos(id),
  matricula TEXT,
  data DATE NOT NULL,
  valor NUMERIC(10,2) NOT NULL,
  descricao TEXT,
  semana_inicio DATE,
  pagamento_id UUID REFERENCES pagamentos(id),
  origem TEXT DEFAULT 'csv' CHECK (origem IN ('csv','manual')),
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 7. PORTAGENS VIA VERDE
-- ============================================================
CREATE TABLE viaverde_portagens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID REFERENCES motoristas(id),
  veiculo_id UUID REFERENCES veiculos(id),
  matricula TEXT,
  data DATE NOT NULL,
  valor NUMERIC(10,2) NOT NULL,
  descricao TEXT,
  local TEXT,
  semana_inicio DATE,
  pagamento_id UUID REFERENCES pagamentos(id),
  origem TEXT DEFAULT 'csv' CHECK (origem IN ('csv','manual')),
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 8. CONTRATOS
-- ============================================================
CREATE TABLE contratos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID NOT NULL REFERENCES motoristas(id),
  veiculo_id UUID REFERENCES veiculos(id),
  tipo TEXT NOT NULL CHECK (tipo IN (
    'slot_semanal',
    'comissao',
    'comodato_bolt',
    'declaracao_uber'
  )),
  data_assinatura DATE,
  data_inicio DATE,
  data_fim DATE,
  local_assinatura TEXT,
  slot_valor NUMERIC(10,2),
  pdf_url TEXT,
  estado TEXT DEFAULT 'ativo' CHECK (estado IN ('ativo','expirado','cancelado')),
  notas TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 9. HISTÓRICO (log de todas as ações)
-- ============================================================
CREATE TABLE historico (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES empresas(id),
  perfil_id UUID REFERENCES perfis(id),
  tabela TEXT,
  registo_id UUID,
  acao TEXT, -- 'criar','editar','eliminar','enviar'
  dados_anteriores JSONB,
  dados_novos JSONB,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 10. NOTIFICAÇÕES
-- ============================================================
CREATE TABLE notificacoes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES empresas(id),
  perfil_id UUID REFERENCES perfis(id),
  tipo TEXT, -- 'recibo','alerta_doc','alerta_veiculo','pagamento'
  titulo TEXT,
  mensagem TEXT,
  lida BOOLEAN DEFAULT false,
  dados JSONB,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TRIGGERS — atualizar atualizado_em automaticamente
-- ============================================================
CREATE OR REPLACE FUNCTION atualizar_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_empresas_ts BEFORE UPDATE ON empresas FOR EACH ROW EXECUTE FUNCTION atualizar_timestamp();
CREATE TRIGGER tr_perfis_ts BEFORE UPDATE ON perfis FOR EACH ROW EXECUTE FUNCTION atualizar_timestamp();
CREATE TRIGGER tr_motoristas_ts BEFORE UPDATE ON motoristas FOR EACH ROW EXECUTE FUNCTION atualizar_timestamp();
CREATE TRIGGER tr_veiculos_ts BEFORE UPDATE ON veiculos FOR EACH ROW EXECUTE FUNCTION atualizar_timestamp();
CREATE TRIGGER tr_pagamentos_ts BEFORE UPDATE ON pagamentos FOR EACH ROW EXECUTE FUNCTION atualizar_timestamp();

-- ============================================================
-- TRIGGER — criar perfil automaticamente após registo
-- ============================================================
CREATE OR REPLACE FUNCTION criar_perfil_novo_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO perfis (id, email, role)
  VALUES (NEW.id, NEW.email, 'motorista');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER tr_novo_user_perfil
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION criar_perfil_novo_user();

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

-- Ativar RLS em todas as tabelas
ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE perfis ENABLE ROW LEVEL SECURITY;
ALTER TABLE motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE veiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE prio_carregamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE viaverde_portagens ENABLE ROW LEVEL SECURITY;
ALTER TABLE contratos ENABLE ROW LEVEL SECURITY;
ALTER TABLE historico ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificacoes ENABLE ROW LEVEL SECURITY;

-- Helper: obter empresa do user autenticado
CREATE OR REPLACE FUNCTION get_empresa_id()
RETURNS UUID AS $$
  SELECT empresa_id FROM perfis WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: obter role do user autenticado
CREATE OR REPLACE FUNCTION get_role()
RETURNS TEXT AS $$
  SELECT role FROM perfis WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: obter motorista_id do user autenticado
CREATE OR REPLACE FUNCTION get_motorista_id()
RETURNS UUID AS $$
  SELECT id FROM motoristas WHERE perfil_id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- POLÍTICAS: empresas
CREATE POLICY "superadmin_tudo_empresas" ON empresas
  FOR ALL USING (get_role() = 'superadmin');

CREATE POLICY "operador_propria_empresa" ON empresas
  FOR SELECT USING (id = get_empresa_id() AND get_role() = 'operador');

CREATE POLICY "operador_edita_propria_empresa" ON empresas
  FOR UPDATE USING (id = get_empresa_id() AND get_role() = 'operador');

-- POLÍTICAS: perfis
CREATE POLICY "proprio_perfil" ON perfis
  FOR ALL USING (id = auth.uid());

CREATE POLICY "operador_ve_perfis_empresa" ON perfis
  FOR SELECT USING (empresa_id = get_empresa_id() AND get_role() IN ('operador','superadmin'));

-- POLÍTICAS: motoristas
CREATE POLICY "superadmin_tudo_motoristas" ON motoristas
  FOR ALL USING (get_role() = 'superadmin');

CREATE POLICY "operador_motoristas_empresa" ON motoristas
  FOR ALL USING (empresa_id = get_empresa_id() AND get_role() = 'operador');

CREATE POLICY "motorista_proprios_dados" ON motoristas
  FOR SELECT USING (perfil_id = auth.uid());

-- POLÍTICAS: veículos
CREATE POLICY "superadmin_tudo_veiculos" ON veiculos
  FOR ALL USING (get_role() = 'superadmin');

CREATE POLICY "operador_veiculos_empresa" ON veiculos
  FOR ALL USING (empresa_id = get_empresa_id() AND get_role() = 'operador');

CREATE POLICY "motorista_ve_veiculo" ON veiculos
  FOR SELECT USING (motorista_id = get_motorista_id());

-- POLÍTICAS: pagamentos
CREATE POLICY "superadmin_tudo_pagamentos" ON pagamentos
  FOR ALL USING (get_role() = 'superadmin');

CREATE POLICY "operador_pagamentos_empresa" ON pagamentos
  FOR ALL USING (empresa_id = get_empresa_id() AND get_role() = 'operador');

CREATE POLICY "motorista_proprios_pagamentos" ON pagamentos
  FOR SELECT USING (motorista_id = get_motorista_id());

-- POLÍTICAS: prio
CREATE POLICY "operador_prio_empresa" ON prio_carregamentos
  FOR ALL USING (empresa_id = get_empresa_id() AND get_role() IN ('operador','superadmin'));

CREATE POLICY "motorista_proprio_prio" ON prio_carregamentos
  FOR SELECT USING (motorista_id = get_motorista_id());

-- POLÍTICAS: via verde
CREATE POLICY "operador_viaverde_empresa" ON viaverde_portagens
  FOR ALL USING (empresa_id = get_empresa_id() AND get_role() IN ('operador','superadmin'));

CREATE POLICY "motorista_propria_viaverde" ON viaverde_portagens
  FOR SELECT USING (motorista_id = get_motorista_id());

-- POLÍTICAS: contratos
CREATE POLICY "operador_contratos_empresa" ON contratos
  FOR ALL USING (empresa_id = get_empresa_id() AND get_role() IN ('operador','superadmin'));

CREATE POLICY "motorista_proprios_contratos" ON contratos
  FOR SELECT USING (motorista_id = get_motorista_id());

-- POLÍTICAS: notificações
CREATE POLICY "proprias_notificacoes" ON notificacoes
  FOR ALL USING (perfil_id = auth.uid() OR empresa_id = get_empresa_id());

-- ============================================================
-- DADOS INICIAIS — Instituto 31 (empresa demo)
-- ============================================================
INSERT INTO empresas (
  id, nome, nif, email, plano, plano_motoristas_max,
  iva_uber_pct, slot_semanal_default
) VALUES (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Instituto 31, Lda',
  '515285471',
  'coordenacao@instituto31.pt',
  'pro',
  15,
  23,
  0
);

-- ============================================================
-- ÍNDICES para performance
-- ============================================================
CREATE INDEX idx_motoristas_empresa ON motoristas(empresa_id);
CREATE INDEX idx_motoristas_perfil ON motoristas(perfil_id);
CREATE INDEX idx_pagamentos_empresa ON pagamentos(empresa_id);
CREATE INDEX idx_pagamentos_motorista ON pagamentos(motorista_id);
CREATE INDEX idx_pagamentos_semana ON pagamentos(semana_inicio);
CREATE INDEX idx_prio_empresa ON prio_carregamentos(empresa_id);
CREATE INDEX idx_prio_semana ON prio_carregamentos(semana_inicio);
CREATE INDEX idx_viaverde_empresa ON viaverde_portagens(empresa_id);
CREATE INDEX idx_viaverde_semana ON viaverde_portagens(semana_inicio);
CREATE INDEX idx_veiculos_empresa ON veiculos(empresa_id);
CREATE INDEX idx_veiculos_matricula ON veiculos(matricula);

-- ============================================================
-- FIM DO SCHEMA
-- Próximo passo: executar este SQL no Supabase SQL Editor
-- ============================================================
