-- =====================================================
-- FleetPay — RPC definir password motorista (universal)
-- Substitui Edge Function por chamada SQL directa.
-- Cria ou actualiza auth.users com password fornecida.
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION definir_password_motorista(
  p_motorista_id UUID,
  p_password TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role text;
  v_caller_empresa uuid;
  v_mot record;
  v_user_id uuid;
  v_encrypted text;
  v_instance_id uuid;
BEGIN
  -- 1. Auth: operador/superadmin
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao');
  END IF;

  SELECT role, empresa_id INTO v_caller_role, v_caller_empresa
  FROM perfis WHERE id = v_caller_id;

  IF v_caller_role NOT IN ('operador','admin','superadmin') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_permissao', 'role', v_caller_role);
  END IF;

  -- 2. Buscar motorista
  SELECT id, email, nome, empresa_id, perfil_id INTO v_mot
  FROM motoristas WHERE id = p_motorista_id;

  IF v_mot.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'motorista_nao_existe');
  END IF;

  IF v_mot.email IS NULL OR TRIM(v_mot.email) = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'motorista_sem_email');
  END IF;

  -- Superadmin pode mexer em qualquer empresa; operador só na sua
  IF v_caller_role <> 'superadmin' AND v_mot.empresa_id <> v_caller_empresa THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'outra_empresa');
  END IF;

  IF LENGTH(p_password) < 6 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'password_curta');
  END IF;

  -- 3. Encriptar password (bcrypt)
  v_encrypted := crypt(p_password, gen_salt('bf'));

  -- 4. Procurar auth.user pelo email (case-insensitive)
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE LOWER(TRIM(email)) = LOWER(TRIM(v_mot.email))
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    -- UPDATE password
    UPDATE auth.users
    SET encrypted_password = v_encrypted,
        email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
        confirmed_at = COALESCE(confirmed_at, NOW()),
        updated_at = NOW()
    WHERE id = v_user_id;
  ELSE
    -- CREATE user novo
    v_instance_id := COALESCE(
      (SELECT instance_id FROM auth.users LIMIT 1),
      '00000000-0000-0000-0000-000000000000'::uuid
    );
    v_user_id := gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, email, encrypted_password,
      email_confirmed_at, confirmed_at, created_at, updated_at,
      aud, role, raw_app_meta_data, raw_user_meta_data,
      is_super_admin
    ) VALUES (
      v_user_id,
      v_instance_id,
      LOWER(TRIM(v_mot.email)),
      v_encrypted,
      NOW(), NOW(), NOW(), NOW(),
      'authenticated', 'authenticated',
      jsonb_build_object('provider', 'email', 'providers', ARRAY['email']),
      jsonb_build_object('nome', v_mot.nome, 'role', 'motorista', 'empresa_id', v_mot.empresa_id),
      false
    );

    -- Inserir identidade email (necessário para Supabase Auth)
    INSERT INTO auth.identities (
      id, user_id, provider_id, identity_data, provider,
      created_at, updated_at, last_sign_in_at
    ) VALUES (
      gen_random_uuid(),
      v_user_id,
      v_user_id::text,
      jsonb_build_object('sub', v_user_id::text, 'email', LOWER(TRIM(v_mot.email))),
      'email',
      NOW(), NOW(), NOW()
    );
  END IF;

  -- 5. Upsert perfil + liga motorista
  INSERT INTO perfis (id, email, role, empresa_id, nome)
  VALUES (v_user_id, LOWER(TRIM(v_mot.email)), 'motorista', v_mot.empresa_id, v_mot.nome)
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    empresa_id = COALESCE(perfis.empresa_id, EXCLUDED.empresa_id),
    nome = COALESCE(perfis.nome, EXCLUDED.nome);

  UPDATE motoristas SET perfil_id = v_user_id WHERE id = p_motorista_id;

  RETURN jsonb_build_object(
    'ok', true,
    'auth_user_id', v_user_id,
    'email', LOWER(TRIM(v_mot.email)),
    'criado_novo', v_user_id IS NOT NULL
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'excecao', 'erro', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION definir_password_motorista(UUID, TEXT) TO authenticated;

-- Verificação
SELECT proname, prosecdef FROM pg_proc WHERE proname = 'definir_password_motorista';
