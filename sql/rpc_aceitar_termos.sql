-- =====================================================
-- FleetPay — RPC aceitar_termos (universal, resolve travamento)
-- Substitui INSERT pelo cliente + RLS lento por chamada
-- directa SECURITY DEFINER.
-- =====================================================

-- 1) Index em motoristas.perfil_id (acelera tudo)
CREATE INDEX IF NOT EXISTS idx_motoristas_perfil_id
  ON motoristas(perfil_id)
  WHERE perfil_id IS NOT NULL;

-- 2) RPC: SECURITY DEFINER, bypassa RLS lento, idempotente
CREATE OR REPLACE FUNCTION aceitar_termos(p_versao_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_motorista_id uuid;
  v_empresa_id uuid;
  v_versao_empresa uuid;
  v_aceite_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_user');
  END IF;

  -- 1. Procurar motorista deste user (rápido com novo index)
  SELECT id, empresa_id INTO v_motorista_id, v_empresa_id
  FROM motoristas
  WHERE perfil_id = v_user_id
    AND COALESCE(ativo, true) = true
  ORDER BY criado_em DESC NULLS LAST
  LIMIT 1;

  IF v_motorista_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_motorista');
  END IF;

  -- 2. Validar versão dos termos pertence à empresa do motorista
  SELECT empresa_id INTO v_versao_empresa
  FROM termos_versoes WHERE id = p_versao_id;

  IF v_versao_empresa IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'versao_inexistente');
  END IF;

  IF v_versao_empresa <> v_empresa_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'versao_de_outra_empresa');
  END IF;

  -- 3. INSERT idempotente (ignora se já tinha aceitado)
  INSERT INTO termos_aceitacoes (motorista_id, termos_versao_id, user_agent)
  VALUES (v_motorista_id, p_versao_id, 'rpc-aceitar-termos')
  ON CONFLICT (motorista_id, termos_versao_id) DO UPDATE
    SET aceito_em = COALESCE(termos_aceitacoes.aceito_em, NOW())
  RETURNING id INTO v_aceite_id;

  RETURN jsonb_build_object(
    'ok', true,
    'aceite_id', v_aceite_id,
    'motorista_id', v_motorista_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'excecao', 'erro', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION aceitar_termos(UUID) TO authenticated;

-- 3) Verificação
SELECT proname, prosecdef AS is_security_definer
FROM pg_proc WHERE proname = 'aceitar_termos';
