-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Pedidos do motorista ao operador
-- (férias, documento, adiantamento, troca de carro, outro)
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS pedidos_motorista (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID NOT NULL REFERENCES motoristas(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('ferias','documento','adiantamento','troca_carro','outro')),
  descricao TEXT,
  data_inicio DATE,
  data_fim DATE,
  valor NUMERIC(10,2),
  estado TEXT NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente','aprovado','recusado','cancelado')),
  resposta TEXT,
  respondido_em TIMESTAMPTZ,
  respondido_por UUID REFERENCES auth.users(id),
  criado_em TIMESTAMPTZ DEFAULT now(),
  atualizado_em TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pedidos_empresa_estado ON pedidos_motorista(empresa_id, estado, criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_motorista ON pedidos_motorista(motorista_id, criado_em DESC);

ALTER TABLE pedidos_motorista ENABLE ROW LEVEL SECURITY;

-- superadmin: tudo
CREATE POLICY pedidos_superadmin_all ON pedidos_motorista
  FOR ALL TO authenticated
  USING (get_role() = 'superadmin') WITH CHECK (get_role() = 'superadmin');

-- operador: tudo na sua empresa
CREATE POLICY pedidos_operador_all ON pedidos_motorista
  FOR ALL TO authenticated
  USING (get_role() IN ('operador','admin') AND empresa_id = get_empresa_id())
  WITH CHECK (get_role() IN ('operador','admin') AND empresa_id = get_empresa_id());

-- motorista: vê os seus
CREATE POLICY pedidos_motorista_select ON pedidos_motorista
  FOR SELECT TO authenticated
  USING (motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()));

-- motorista: cria os seus (sempre pendente)
CREATE POLICY pedidos_motorista_insert ON pedidos_motorista
  FOR INSERT TO authenticated
  WITH CHECK (
    estado = 'pendente' AND resposta IS NULL AND respondido_em IS NULL
    AND motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid())
    AND empresa_id IN (SELECT m.empresa_id FROM motoristas m WHERE m.perfil_id = auth.uid())
  );

-- motorista: só pode cancelar um pedido seu ainda pendente
CREATE POLICY pedidos_motorista_cancelar ON pedidos_motorista
  FOR UPDATE TO authenticated
  USING (estado = 'pendente' AND motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()))
  WITH CHECK (estado = 'cancelado' AND motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()));

-- Ao responder (aprovado/recusado), avisa o motorista no chat
CREATE OR REPLACE FUNCTION fp_pedido_notificar()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tipo TEXT; v_txt TEXT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.estado IN ('aprovado','recusado') AND OLD.estado = 'pendente' THEN
    v_tipo := CASE NEW.tipo WHEN 'ferias' THEN 'férias' WHEN 'documento' THEN 'documento'
                            WHEN 'adiantamento' THEN 'adiantamento' WHEN 'troca_carro' THEN 'troca de viatura' ELSE 'pedido' END;
    v_txt := CASE WHEN NEW.estado = 'aprovado' THEN '✅ Boas notícias: o seu pedido de ' || v_tipo || ' foi aprovado! 🎉'
                  ELSE '❌ Desta vez não foi possível aprovar o seu pedido de ' || v_tipo || '.' END;
    IF NEW.resposta IS NOT NULL AND length(trim(NEW.resposta)) > 0 THEN v_txt := v_txt || ' ' || NEW.resposta; END IF;
    INSERT INTO mensagens (empresa_id, motorista_id, autor, autor_nome, mensagem)
    VALUES (NEW.empresa_id, NEW.motorista_id, 'operador', 'FleetPay', v_txt);
    NEW.respondido_em := COALESCE(NEW.respondido_em, now());
  END IF;
  NEW.atualizado_em := now();
  RETURN NEW;
END; $$;

CREATE OR REPLACE TRIGGER tr_pedido_notificar
BEFORE UPDATE ON pedidos_motorista
FOR EACH ROW EXECUTE FUNCTION fp_pedido_notificar();
