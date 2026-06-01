-- =====================================================
-- FleetPay — Trial 30 dias
-- Coluna na empresa + função activar + helper expirou
-- =====================================================

ALTER TABLE empresas
  ADD COLUMN IF NOT EXISTS trial_iniciado_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS trial_termina_em  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS trial_dias        INT DEFAULT 30;

CREATE INDEX IF NOT EXISTS idx_empresas_trial
  ON empresas(trial_termina_em)
  WHERE trial_termina_em IS NOT NULL;

-- Função para activar trial (superadmin/operador da empresa)
CREATE OR REPLACE FUNCTION activar_trial_empresa(
  p_empresa_id UUID,
  p_dias INT DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_caller_empresa uuid;
BEGIN
  -- só superadmin OU operador da própria empresa
  SELECT role, empresa_id INTO v_role, v_caller_empresa
  FROM perfis WHERE id = auth.uid();

  IF v_role NOT IN ('superadmin', 'operador') OR
     (v_role = 'operador' AND v_caller_empresa <> p_empresa_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unauthorized');
  END IF;

  UPDATE empresas
  SET trial_iniciado_em = NOW(),
      trial_termina_em  = NOW() + (p_dias || ' days')::interval,
      trial_dias = p_dias,
      plano = 'enterprise'  -- durante o trial, dá-se acesso total
  WHERE id = p_empresa_id;

  RETURN jsonb_build_object('ok', true, 'termina_em', NOW() + (p_dias || ' days')::interval);
END;
$$;

GRANT EXECUTE ON FUNCTION activar_trial_empresa(UUID, INT) TO authenticated;

-- Helper: trial expirado?
CREATE OR REPLACE FUNCTION trial_expirou(p_empresa_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT trial_termina_em IS NOT NULL
     AND trial_termina_em < NOW()
     AND COALESCE(plano,'') = 'enterprise'  -- só conta como trial quem ainda tem o plano trial
  FROM empresas WHERE id = p_empresa_id;
$$;

-- =====================================================
-- Helper para o teu lead: criar conta + activar trial
-- =====================================================
-- Quando tiveres o email + nome da empresa do lead:
--
-- 1) Cria a empresa (substitui os valores):
-- INSERT INTO empresas (id, nome, email, plano)
-- VALUES (gen_random_uuid(), 'Nome Operador Lda', 'lead@example.com', 'enterprise')
-- RETURNING id;
--
-- 2) Activa o trial com o ID que voltou:
-- SELECT activar_trial_empresa('<id-que-voltou>'::uuid, 30);
--
-- 3) Envia ao operador o link de signup com o email pré-definido:
--    https://fleetpay.pt/signup.html?email=lead@example.com&empresa=<id>
