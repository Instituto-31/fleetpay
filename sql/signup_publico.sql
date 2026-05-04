-- ============================================================
-- SIGNUP PÚBLICO — FleetPay
-- ============================================================
-- Permite que qualquer user autenticado crie uma empresa nova
-- e o perfil de operador associado, ao registar-se.
--
-- Plano default: 'gratuito' com limite de 2 motoristas.
-- ============================================================

CREATE OR REPLACE FUNCTION criar_empresa_publica(
  p_nome_empresa TEXT,
  p_nif TEXT,
  p_nome_responsavel TEXT,
  p_telefone TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_empresa_id UUID;
  v_email TEXT;
BEGIN
  -- User autenticado (chamou esta função)
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'É preciso estar autenticado.';
  END IF;

  -- Buscar email do user
  SELECT email INTO v_email FROM auth.users WHERE id = v_user_id;

  -- Não permitir duplicado: se já tem perfil com empresa, não cria
  IF EXISTS (SELECT 1 FROM perfis WHERE id = v_user_id AND empresa_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Já tens uma empresa associada à tua conta.';
  END IF;

  -- Criar empresa (plano gratuito, 2 motoristas máx)
  INSERT INTO empresas (
    nome, nif, email, telefone,
    plano, plano_motoristas_max
  )
  VALUES (
    p_nome_empresa, NULLIF(TRIM(p_nif), ''), v_email, p_telefone,
    'gratuito', 2
  )
  RETURNING id INTO v_empresa_id;

  -- Criar (ou actualizar) perfil ligando-o à empresa como operador
  INSERT INTO perfis (id, empresa_id, role, nome, email, telefone)
  VALUES (v_user_id, v_empresa_id, 'operador', p_nome_responsavel, v_email, p_telefone)
  ON CONFLICT (id) DO UPDATE SET
    empresa_id = EXCLUDED.empresa_id,
    role = EXCLUDED.role,
    nome = EXCLUDED.nome,
    telefone = EXCLUDED.telefone,
    atualizado_em = NOW();

  RETURN v_empresa_id;
END;
$$;

REVOKE ALL ON FUNCTION criar_empresa_publica(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION criar_empresa_publica(TEXT, TEXT, TEXT, TEXT) TO authenticated;
