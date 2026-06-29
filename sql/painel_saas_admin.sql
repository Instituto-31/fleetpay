-- =====================================================
-- FleetPay — Painel SaaS Admin (superadmin)
-- Audit log + view agregada de empresas
-- =====================================================

-- 1) Tabela audit_log para registar acções do superadmin
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id UUID REFERENCES auth.users(id),
  actor_email TEXT,
  action TEXT NOT NULL,
  target_type TEXT,
  target_id UUID,
  target_label TEXT,
  detalhes JSONB,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log(actor_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_audit_target ON audit_log(target_type, target_id);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS audit_log_superadmin ON audit_log;
CREATE POLICY audit_log_superadmin ON audit_log
  FOR ALL TO authenticated
  USING (get_role() = 'superadmin')
  WITH CHECK (get_role() = 'superadmin');

-- 2) RPC: lista empresas com estatísticas agregadas (para painel SaaS)
CREATE OR REPLACE FUNCTION fp_empresas_dashboard()
RETURNS TABLE(
  id UUID, nome TEXT, plano TEXT, demo BOOLEAN,
  trial_termina_em TIMESTAMPTZ, dias_trial_restantes INT,
  modelo_comissao TEXT, criado_em TIMESTAMPTZ,
  motoristas_ativos BIGINT,
  pagamentos_30d BIGINT,
  ultima_actividade TIMESTAMPTZ,
  mrr_estimado NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id, e.nome, e.plano, COALESCE(e.demo, false) AS demo,
    e.trial_termina_em,
    CASE WHEN e.trial_termina_em IS NULL THEN NULL
         ELSE GREATEST(0, EXTRACT(DAY FROM (e.trial_termina_em - NOW()))::int)
    END AS dias_trial_restantes,
    COALESCE(e.modelo_comissao, 'directo') AS modelo_comissao,
    e.criado_em,
    (SELECT COUNT(*) FROM motoristas m WHERE m.empresa_id = e.id AND COALESCE(m.ativo, true)) AS motoristas_ativos,
    (SELECT COUNT(*) FROM pagamentos p WHERE p.empresa_id = e.id AND p.criado_em > NOW() - INTERVAL '30 days') AS pagamentos_30d,
    GREATEST(
      e.criado_em,
      (SELECT MAX(criado_em) FROM pagamentos WHERE empresa_id = e.id),
      (SELECT MAX(criado_em) FROM motoristas WHERE empresa_id = e.id)
    ) AS ultima_actividade,
    CASE e.plano
      WHEN 'starter' THEN 20
      WHEN 'pro' THEN 49
      WHEN 'enterprise' THEN
        CASE WHEN e.trial_termina_em > NOW() THEN 0 ELSE 99 END
      ELSE 0
    END AS mrr_estimado
  FROM empresas e
  ORDER BY e.criado_em DESC;
$$;

GRANT EXECUTE ON FUNCTION fp_empresas_dashboard() TO authenticated;

-- 3) RPC: KPIs globais do SaaS
CREATE OR REPLACE FUNCTION fp_kpis_saas()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'total_empresas', (SELECT COUNT(*) FROM empresas WHERE COALESCE(demo,false) = false),
    'em_trial', (SELECT COUNT(*) FROM empresas WHERE trial_termina_em > NOW() AND COALESCE(demo,false) = false),
    'pagas', (SELECT COUNT(*) FROM empresas WHERE plano IN ('starter','pro','enterprise') AND (trial_termina_em IS NULL OR trial_termina_em < NOW()) AND COALESCE(demo,false) = false),
    'free', (SELECT COUNT(*) FROM empresas WHERE COALESCE(plano,'free') = 'free' AND COALESCE(demo,false) = false),
    'motoristas_total', (SELECT COUNT(*) FROM motoristas m JOIN empresas e ON e.id = m.empresa_id WHERE COALESCE(m.ativo,true) AND COALESCE(e.demo,false) = false),
    'pagamentos_semana', (SELECT COUNT(*) FROM pagamentos p JOIN empresas e ON e.id = p.empresa_id WHERE p.criado_em > NOW() - INTERVAL '7 days' AND COALESCE(e.demo,false) = false),
    'mrr_total', (
      SELECT COALESCE(SUM(
        CASE plano
          WHEN 'starter' THEN 20
          WHEN 'pro' THEN 49
          WHEN 'enterprise' THEN 99
          ELSE 0
        END
      ), 0)
      FROM empresas
      WHERE plano IN ('starter','pro','enterprise')
        AND (trial_termina_em IS NULL OR trial_termina_em < NOW())
        AND COALESCE(demo,false) = false
    )
  );
$$;

GRANT EXECUTE ON FUNCTION fp_kpis_saas() TO authenticated;
