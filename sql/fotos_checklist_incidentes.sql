-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Fotos no checklist diário + Registo de incidentes
-- ════════════════════════════════════════════════════════════════════
-- Bucket privado "fotos": <empresa_id>/checklist/<motorista_id>/<data>/<angulo>.jpg
--                         <empresa_id>/incidentes/<incidente_id>/<n>.jpg
-- Motorista: insere/lê no seu próprio prefixo; operador: tudo na sua empresa.
-- ════════════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('fotos', 'fotos', false, 8388608, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY fotos_superadmin_all ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'fotos' AND get_role() = 'superadmin')
  WITH CHECK (bucket_id = 'fotos' AND get_role() = 'superadmin');

CREATE POLICY fotos_operador_all ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'fotos' AND get_role() IN ('operador','admin')
         AND ((storage.foldername(name))[1])::uuid = get_empresa_id())
  WITH CHECK (bucket_id = 'fotos' AND get_role() IN ('operador','admin')
         AND ((storage.foldername(name))[1])::uuid = get_empresa_id());

-- motorista: só dentro da sua empresa e (checklist) na sua pasta, (incidentes) nos seus incidentes
CREATE POLICY fotos_motorista_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'fotos'
    AND ((storage.foldername(name))[1])::uuid IN (SELECT m.empresa_id FROM motoristas m WHERE m.perfil_id = auth.uid())
    AND (
      ((storage.foldername(name))[2] = 'checklist'
        AND ((storage.foldername(name))[3])::uuid IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()))
      OR
      ((storage.foldername(name))[2] = 'incidentes'
        AND ((storage.foldername(name))[3])::uuid IN (SELECT i.id FROM incidentes i JOIN motoristas m ON m.id = i.motorista_id WHERE m.perfil_id = auth.uid()))
    )
  );
CREATE POLICY fotos_motorista_select ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'fotos'
    AND ((storage.foldername(name))[1])::uuid IN (SELECT m.empresa_id FROM motoristas m WHERE m.perfil_id = auth.uid())
    AND (
      ((storage.foldername(name))[2] = 'checklist'
        AND ((storage.foldername(name))[3])::uuid IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()))
      OR
      ((storage.foldername(name))[2] = 'incidentes'
        AND ((storage.foldername(name))[3])::uuid IN (SELECT i.id FROM incidentes i JOIN motoristas m ON m.id = i.motorista_id WHERE m.perfil_id = auth.uid()))
    )
  );

-- Checklist: fotos (jsonb: {frente, tras, esquerda, direita, painel} → path) + km
ALTER TABLE checklists_diarios ADD COLUMN IF NOT EXISTS fotos JSONB;
ALTER TABLE checklists_diarios ADD COLUMN IF NOT EXISTS km INTEGER;
ALTER TABLE checklists_diarios ADD COLUMN IF NOT EXISTS veiculo_id UUID REFERENCES veiculos(id) ON DELETE SET NULL;

-- Incidentes
CREATE TABLE IF NOT EXISTS incidentes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  motorista_id UUID NOT NULL REFERENCES motoristas(id) ON DELETE CASCADE,
  veiculo_id UUID REFERENCES veiculos(id) ON DELETE SET NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('acidente','multa','avaria','dano','passageiro','outro')),
  descricao TEXT,
  ocorrido_em TIMESTAMPTZ DEFAULT now(),
  local TEXT,
  gps_lat DOUBLE PRECISION,
  gps_lng DOUBLE PRECISION,
  fotos JSONB DEFAULT '[]'::jsonb,
  estado TEXT NOT NULL DEFAULT 'aberto' CHECK (estado IN ('aberto','em_analise','resolvido')),
  resposta TEXT,
  criado_em TIMESTAMPTZ DEFAULT now(),
  atualizado_em TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_incidentes_empresa ON incidentes(empresa_id, estado, criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_incidentes_motorista ON incidentes(motorista_id, criado_em DESC);
ALTER TABLE incidentes ENABLE ROW LEVEL SECURITY;

CREATE POLICY incidentes_superadmin_all ON incidentes FOR ALL TO authenticated
  USING (get_role() = 'superadmin') WITH CHECK (get_role() = 'superadmin');
CREATE POLICY incidentes_operador_all ON incidentes FOR ALL TO authenticated
  USING (get_role() IN ('operador','admin') AND empresa_id = get_empresa_id())
  WITH CHECK (get_role() IN ('operador','admin') AND empresa_id = get_empresa_id());
CREATE POLICY incidentes_motorista_select ON incidentes FOR SELECT TO authenticated
  USING (motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()));
CREATE POLICY incidentes_motorista_insert ON incidentes FOR INSERT TO authenticated
  WITH CHECK (estado = 'aberto' AND resposta IS NULL
    AND motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid())
    AND empresa_id IN (SELECT m.empresa_id FROM motoristas m WHERE m.perfil_id = auth.uid()));
-- motorista pode acrescentar fotos/descrição enquanto está aberto
CREATE POLICY incidentes_motorista_update ON incidentes FOR UPDATE TO authenticated
  USING (estado = 'aberto' AND motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()))
  WITH CHECK (estado = 'aberto' AND resposta IS NULL AND motorista_id IN (SELECT m.id FROM motoristas m WHERE m.perfil_id = auth.uid()));

-- Aviso ao operador (mensagem no chat do motorista fica como registo) e ao motorista quando o estado muda
CREATE OR REPLACE FUNCTION fp_incidente_notificar()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tipo TEXT;
BEGIN
  v_tipo := CASE NEW.tipo WHEN 'acidente' THEN 'acidente' WHEN 'multa' THEN 'multa' WHEN 'avaria' THEN 'avaria'
                          WHEN 'dano' THEN 'dano na viatura' WHEN 'passageiro' THEN 'incidente com passageiro' ELSE 'incidente' END;
  IF TG_OP = 'UPDATE' AND NEW.estado <> OLD.estado AND NEW.estado IN ('em_analise','resolvido') THEN
    INSERT INTO mensagens (empresa_id, motorista_id, autor, autor_nome, mensagem)
    VALUES (NEW.empresa_id, NEW.motorista_id, 'operador', 'FleetPay',
      CASE WHEN NEW.estado = 'resolvido' THEN '✅ O seu registo de ' || v_tipo || ' está resolvido. Obrigado por ter reportado — é assim que a frota anda direita.'
           ELSE '🔎 Recebemos o seu registo de ' || v_tipo || ' e já estamos a tratar dele. Damos notícias em breve.' END
      || COALESCE(' ' || NULLIF(trim(NEW.resposta), ''), ''));
  END IF;
  NEW.atualizado_em := now();
  RETURN NEW;
END; $$;
CREATE OR REPLACE TRIGGER tr_incidente_notificar BEFORE UPDATE ON incidentes
FOR EACH ROW EXECUTE FUNCTION fp_incidente_notificar();
