-- =====================================================
-- FleetPay — Self-healing motorista ↔ perfil ↔ empresa
-- Cada vez que o motorista abre a app, esta função é
-- chamada e LIGA tudo automaticamente se estiver partido.
-- =====================================================
-- Problema que resolve:
--   - Motorista faz signup mas o trigger on_auth_user_created
--     falha silenciosamente (RLS, race condition, email com case
--     diferente, etc.) → fica preso em "conta não associada"
--   - User tinha de andar a correr SQL manual para cada caso
--
-- Solução:
--   RPC SECURITY DEFINER que:
--   1) Cria perfil se não existir
--   2) Procura motorista por email (LOWER+TRIM)
--   3) Liga motorista.perfil_id → auth.users.id
--   4) Liga perfis.empresa_id → motorista.empresa_id
--   5) Devolve { ok, motorista_id, empresa_id, reason }
-- =====================================================

CREATE OR REPLACE FUNCTION garantir_link_motorista()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    uuid := auth.uid();
  v_email      text;
  v_motorista_id uuid;
  v_empresa_id uuid;
  v_perfil_role text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_user');
  END IF;

  -- email actual do auth.users
  SELECT LOWER(TRIM(email)) INTO v_email
  FROM auth.users
  WHERE id = v_user_id;

  IF v_email IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_email');
  END IF;

  -- 1) Garante perfil (se não existir)
  INSERT INTO perfis (id, email, role)
  VALUES (v_user_id, v_email, 'motorista')
  ON CONFLICT (id) DO NOTHING;

  -- guarda role atual (pode ser superadmin/operador → não mexer)
  SELECT role INTO v_perfil_role FROM perfis WHERE id = v_user_id;

  -- Se não for motorista, nada a fazer aqui
  IF v_perfil_role IS NOT NULL AND v_perfil_role NOT IN ('motorista') THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'nao_motorista', 'role', v_perfil_role);
  END IF;

  -- 2) Procura motorista por email match (case insensitive, trim)
  --    Prefere o que já tem perfil_id ligado (caso haja duplicados)
  SELECT id, empresa_id INTO v_motorista_id, v_empresa_id
  FROM motoristas
  WHERE LOWER(TRIM(email)) = v_email
    AND COALESCE(ativo, true) = true
  ORDER BY
    (perfil_id = v_user_id) DESC,
    (perfil_id IS NOT NULL) DESC,
    criado_em DESC NULLS LAST
  LIMIT 1;

  IF v_motorista_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_motorista', 'email', v_email);
  END IF;

  -- 3) Liga motorista → perfil se ainda não está
  UPDATE motoristas
  SET perfil_id = v_user_id
  WHERE id = v_motorista_id
    AND (perfil_id IS NULL OR perfil_id <> v_user_id);

  -- 4) Liga perfil → empresa se ainda não está (e fixa role)
  UPDATE perfis
  SET empresa_id = COALESCE(empresa_id, v_empresa_id),
      role = COALESCE(NULLIF(role,''), 'motorista'),
      email = v_email
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'ok', true,
    'motorista_id', v_motorista_id,
    'empresa_id', v_empresa_id,
    'email', v_email
  );
END;
$$;

GRANT EXECUTE ON FUNCTION garantir_link_motorista() TO authenticated;

-- =====================================================
-- Fix imediato a TODOS os motoristas atualmente partidos
-- (corre uma vez, idempotente — pode correr quantas quiseres)
-- =====================================================

-- Liga motoristas a auth.users por email match (todos os que não estão ligados)
UPDATE motoristas m
SET perfil_id = u.id
FROM auth.users u
WHERE LOWER(TRIM(m.email)) = LOWER(TRIM(u.email))
  AND m.perfil_id IS NULL
  AND COALESCE(m.ativo, true) = true;

-- Cria perfis em falta para auth.users que correspondem a motoristas
INSERT INTO perfis (id, email, role, empresa_id)
SELECT DISTINCT u.id, LOWER(TRIM(u.email)), 'motorista', m.empresa_id
FROM auth.users u
INNER JOIN motoristas m ON LOWER(TRIM(m.email)) = LOWER(TRIM(u.email))
                       AND COALESCE(m.ativo, true) = true
LEFT JOIN perfis p ON p.id = u.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- Atualiza perfis sem empresa_id
UPDATE perfis p
SET empresa_id = m.empresa_id,
    role = COALESCE(NULLIF(p.role,''), 'motorista')
FROM motoristas m
WHERE m.perfil_id = p.id
  AND p.empresa_id IS NULL
  AND m.empresa_id IS NOT NULL;

-- Relatório (opcional — corre só este se quiseres ver estado)
-- SELECT
--   (SELECT COUNT(*) FROM motoristas WHERE perfil_id IS NOT NULL AND ativo) as ligados,
--   (SELECT COUNT(*) FROM motoristas WHERE perfil_id IS NULL AND ativo) as por_ligar,
--   (SELECT COUNT(*) FROM auth.users u
--      WHERE NOT EXISTS (SELECT 1 FROM motoristas m WHERE m.perfil_id = u.id)) as auth_sem_motorista;
