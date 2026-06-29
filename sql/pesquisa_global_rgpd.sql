-- =====================================================
-- FleetPay — Pesquisa Global de motoristas/viaturas
-- RGPD-safe: opt-in pelo motorista + autorização explícita
-- =====================================================

-- 1) Coluna opt-in no motorista (default false)
ALTER TABLE motoristas
  ADD COLUMN IF NOT EXISTS partilhar_publico BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS partilhar_atualizado_em TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_motoristas_partilhar
  ON motoristas(partilhar_publico, nif)
  WHERE partilhar_publico = TRUE;

-- 2) Tabela pedidos de importação (operador A pede a motorista do operador B)
CREATE TABLE IF NOT EXISTS pedidos_importacao_motorista (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  motorista_origem_id UUID REFERENCES motoristas(id) ON DELETE CASCADE,
  empresa_solicitante_id UUID REFERENCES empresas(id) ON DELETE CASCADE,
  solicitante_user_id UUID REFERENCES auth.users(id),
  estado TEXT DEFAULT 'pendente' CHECK (estado IN ('pendente','aprovado','rejeitado','cancelado')),
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  respondido_em TIMESTAMPTZ,
  motorista_destino_id UUID REFERENCES motoristas(id) ON DELETE SET NULL,
  notas TEXT
);
CREATE INDEX IF NOT EXISTS idx_pedidos_motorista ON pedidos_importacao_motorista(motorista_origem_id, estado);
CREATE INDEX IF NOT EXISTS idx_pedidos_empresa ON pedidos_importacao_motorista(empresa_solicitante_id, criado_em DESC);

ALTER TABLE pedidos_importacao_motorista ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pedidos_motorista_proprio_ver ON pedidos_importacao_motorista;
CREATE POLICY pedidos_motorista_proprio_ver ON pedidos_importacao_motorista
  FOR SELECT TO authenticated
  USING (motorista_origem_id IN (
    SELECT id FROM motoristas WHERE perfil_id = auth.uid()
  ));

DROP POLICY IF EXISTS pedidos_solicitante_ver ON pedidos_importacao_motorista;
CREATE POLICY pedidos_solicitante_ver ON pedidos_importacao_motorista
  FOR SELECT TO authenticated
  USING (
    empresa_solicitante_id IN (SELECT empresa_id FROM perfis WHERE id = auth.uid())
    OR get_role() = 'superadmin'
  );

-- 3) Função: ofuscar email (j***@gmail.com)
CREATE OR REPLACE FUNCTION fp_ofuscar_email(p_email text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_email IS NULL OR p_email = '' THEN NULL
    WHEN POSITION('@' IN p_email) < 2 THEN '***'
    ELSE LEFT(p_email, 1) || '***@' || SPLIT_PART(p_email, '@', 2)
  END;
$$;

-- 4) Função: ofuscar telefone (+351 91x xxx 123 → últimos 3)
CREATE OR REPLACE FUNCTION fp_ofuscar_telefone(p_tel text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_tel IS NULL OR p_tel = '' THEN NULL
    WHEN LENGTH(REGEXP_REPLACE(p_tel, '[^0-9]', '', 'g')) < 4 THEN '***'
    ELSE '*** *** ' || RIGHT(REGEXP_REPLACE(p_tel, '[^0-9]', '', 'g'), 3)
  END;
$$;

-- 5) RPC pesquisa global por NIF — devolve info ofuscada
CREATE OR REPLACE FUNCTION pesquisar_motorista_global(p_nif TEXT)
RETURNS TABLE(
  id UUID,
  nome_partial TEXT,
  email_ofuscado TEXT,
  telefone_ofuscado TEXT,
  empresa_atual TEXT,
  pode_pedir BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role text;
  v_caller_empresa uuid;
BEGIN
  SELECT role, empresa_id INTO v_caller_role, v_caller_empresa
  FROM perfis WHERE id = auth.uid();

  IF v_caller_role NOT IN ('operador','admin','superadmin') THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    m.id,
    -- Nome: 1º nome completo + iniciais do resto (João S. F.)
    SPLIT_PART(m.nome, ' ', 1) || ' ' ||
    STRING_AGG(LEFT(p.token, 1) || '.', ' ') AS nome_partial,
    fp_ofuscar_email(m.email) AS email_ofuscado,
    fp_ofuscar_telefone(m.telefone) AS telefone_ofuscado,
    e.nome AS empresa_atual,
    -- pode_pedir: TRUE se não é da própria empresa do operador
    (m.empresa_id <> v_caller_empresa OR v_caller_role = 'superadmin') AS pode_pedir
  FROM motoristas m
  JOIN empresas e ON e.id = m.empresa_id
  LATERAL (
    SELECT unnest(STRING_TO_ARRAY(SUBSTRING(m.nome FROM POSITION(' ' IN m.nome)+1), ' ')) AS token
  ) p
  WHERE m.nif = TRIM(p_nif)
    AND m.partilhar_publico = TRUE
    AND m.ativo = TRUE
  GROUP BY m.id, m.nome, m.email, m.telefone, e.nome, m.empresa_id;
END;
$$;
GRANT EXECUTE ON FUNCTION pesquisar_motorista_global(TEXT) TO authenticated;

-- 6) RPC: criar pedido de importação
CREATE OR REPLACE FUNCTION pedir_importar_motorista(p_motorista_origem_id UUID, p_notas TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_empresa uuid;
  v_existe_pedido uuid;
  v_motorista record;
  v_pedido_id uuid;
BEGIN
  SELECT empresa_id INTO v_caller_empresa FROM perfis WHERE id = v_caller_id;
  IF v_caller_empresa IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_empresa');
  END IF;

  SELECT id, empresa_id, nome, partilhar_publico INTO v_motorista
  FROM motoristas WHERE id = p_motorista_origem_id;
  IF v_motorista.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'motorista_inexistente');
  END IF;
  IF NOT v_motorista.partilhar_publico THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'motorista_nao_partilha');
  END IF;
  IF v_motorista.empresa_id = v_caller_empresa THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'mesma_empresa');
  END IF;

  -- Já existe pedido pendente?
  SELECT id INTO v_existe_pedido FROM pedidos_importacao_motorista
  WHERE motorista_origem_id = p_motorista_origem_id
    AND empresa_solicitante_id = v_caller_empresa
    AND estado = 'pendente';

  IF v_existe_pedido IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'pedido_id', v_existe_pedido, 'ja_pendente', true);
  END IF;

  INSERT INTO pedidos_importacao_motorista (
    motorista_origem_id, empresa_solicitante_id, solicitante_user_id, notas
  ) VALUES (
    p_motorista_origem_id, v_caller_empresa, v_caller_id, p_notas
  ) RETURNING id INTO v_pedido_id;

  RETURN jsonb_build_object('ok', true, 'pedido_id', v_pedido_id, 'motorista_nome', v_motorista.nome);
END;
$$;
GRANT EXECUTE ON FUNCTION pedir_importar_motorista(UUID, TEXT) TO authenticated;

-- 7) RPC: motorista aprovar/rejeitar pedido
CREATE OR REPLACE FUNCTION responder_pedido_importacao(p_pedido_id UUID, p_aprovar BOOLEAN)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_pedido record;
  v_origem motoristas%ROWTYPE;
  v_novo_id uuid;
BEGIN
  SELECT * INTO v_pedido FROM pedidos_importacao_motorista WHERE id = p_pedido_id;
  IF v_pedido.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'pedido_inexistente');
  END IF;
  IF v_pedido.estado <> 'pendente' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'pedido_ja_respondido', 'estado', v_pedido.estado);
  END IF;

  -- Confirma que o caller é o motorista do pedido
  SELECT * INTO v_origem FROM motoristas
  WHERE id = v_pedido.motorista_origem_id AND perfil_id = v_caller_id;
  IF v_origem.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nao_es_o_motorista');
  END IF;

  IF p_aprovar THEN
    -- Cria novo motorista na empresa solicitante (copia dados)
    INSERT INTO motoristas (
      empresa_id, nome, email, telefone, whatsapp, nif, iban,
      slot_semanal, aluguer_semanal, comissao_pct, modelo_comissao,
      carta_conducao_validade, cartao_cidadao_validade,
      certificado_tvde_validade, registo_criminal_validade,
      ativo
    )
    SELECT
      v_pedido.empresa_solicitante_id, v_origem.nome, v_origem.email,
      v_origem.telefone, v_origem.whatsapp, v_origem.nif, v_origem.iban,
      COALESCE(v_origem.slot_semanal, 0), COALESCE(v_origem.aluguer_semanal, 0),
      COALESCE(v_origem.comissao_pct, 10), COALESCE(v_origem.modelo_comissao, 'directo'),
      v_origem.carta_conducao_validade, v_origem.cartao_cidadao_validade,
      v_origem.certificado_tvde_validade, v_origem.registo_criminal_validade,
      true
    RETURNING id INTO v_novo_id;

    UPDATE pedidos_importacao_motorista
    SET estado = 'aprovado', respondido_em = NOW(), motorista_destino_id = v_novo_id
    WHERE id = p_pedido_id;

    RETURN jsonb_build_object('ok', true, 'novo_motorista_id', v_novo_id);
  ELSE
    UPDATE pedidos_importacao_motorista
    SET estado = 'rejeitado', respondido_em = NOW()
    WHERE id = p_pedido_id;
    RETURN jsonb_build_object('ok', true, 'rejeitado', true);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION responder_pedido_importacao(UUID, BOOLEAN) TO authenticated;

-- 8) RPC: pesquisa local (dentro da empresa) por NIF — usado para autocomplete
CREATE OR REPLACE FUNCTION pesquisar_motorista_local(p_nif TEXT DEFAULT NULL, p_email TEXT DEFAULT NULL)
RETURNS TABLE(id UUID, nome TEXT, nif TEXT, email TEXT, telefone TEXT, ativo BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_empresa uuid;
BEGIN
  SELECT empresa_id INTO v_empresa FROM perfis WHERE id = auth.uid();
  IF v_empresa IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT m.id, m.nome, m.nif, m.email, m.telefone, m.ativo
  FROM motoristas m
  WHERE m.empresa_id = v_empresa
    AND (
      (p_nif IS NOT NULL AND m.nif = TRIM(p_nif))
      OR (p_email IS NOT NULL AND LOWER(TRIM(m.email)) = LOWER(TRIM(p_email)))
    )
  LIMIT 5;
END;
$$;
GRANT EXECUTE ON FUNCTION pesquisar_motorista_local(TEXT, TEXT) TO authenticated;
