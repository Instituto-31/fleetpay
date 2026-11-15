-- ════════════════════════════════════════════════════════════════════
CREATE EXTENSION IF NOT EXISTS unaccent;
-- FleetPay — Importação Uber (relatório "Pagamentos de motorista") no servidor
-- ════════════════════════════════════════════════════════════════════
-- Usada pela tarefa automática de segunda-feira (e utilizável pelo admin).
-- Replica a lógica do importador CSV do admin.html:
--   • uber_bruto = Σ "Pago a si" − gorjetas (gorjetas ficam em uber_gorjetas, SEM comissão)
--   • match do motorista: uber_driver_id → nome exato (uber_nome ou nome) → nome normalizado
--   • semana paga nunca é reescrita (fica nas notas se diferir)
--   • na criação, slot/aluguer vêm da ficha do motorista
--   • grava uber_driver_id/uber_nome no motorista se ainda não tinha
--
-- p_linhas: [{ "uuid": "...", "nome": "Nome Apelido", "pago": 215.68, "gorjeta": 3.00 }, ...]
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE pagamentos ADD COLUMN IF NOT EXISTS uber_gorjetas NUMERIC(10,2) DEFAULT 0;

-- Trigger de cálculo: gorjetas Uber entram sem comissão (como as da Bolt)
CREATE OR REPLACE FUNCTION public.fp_pagamento_auto_calcular()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_pct numeric; v_modelo text; v_div numeric;
  v_com_uber numeric; v_com_bolt numeric; v_com_total numeric;
  v_base_bolt numeric; v_sem_com numeric;
  v_saldo numeric;
BEGIN
  IF NEW.estado = 'pago' AND TG_OP = 'UPDATE' AND OLD.estado = 'pago' THEN RETURN NEW; END IF;
  SELECT COALESCE(comissao_pct, 6), COALESCE(modelo_comissao, 'directo')
    INTO v_pct, v_modelo FROM motoristas WHERE id = NEW.motorista_id;
  IF v_pct IS NULL THEN v_pct := 6; END IF;
  IF v_modelo IS NULL THEN v_modelo := 'directo'; END IF;
  v_div := CASE WHEN v_modelo = 'inclusivo' THEN (100 + v_pct) ELSE 100 END;
  v_base_bolt := COALESCE(NEW.bolt_liquido, 0) + COALESCE(NEW.bolt_campanha, 0) + COALESCE(NEW.bolt_cancelamentos, 0);
  v_sem_com   := COALESCE(NEW.bolt_gorjetas, 0) + COALESCE(NEW.bolt_reembolsos, 0) + COALESCE(NEW.uber_gorjetas, 0);
  v_com_uber  := COALESCE(NEW.uber_bruto, 0) * v_pct / v_div;
  v_com_bolt  := v_base_bolt * v_pct / v_div;
  v_com_total := v_com_uber + v_com_bolt;

  v_saldo := 0;
  IF NEW.semana_inicio >= DATE '2026-11-09' THEN
    SELECT LEAST(0, COALESCE(p.valor_final, 0)) INTO v_saldo
    FROM pagamentos p
    WHERE p.motorista_id = NEW.motorista_id
      AND p.semana_inicio < NEW.semana_inicio
      AND p.semana_inicio >= DATE '2026-11-02'
      AND (TG_OP = 'INSERT' OR p.id <> NEW.id)
    ORDER BY p.semana_inicio DESC
    LIMIT 1;
  END IF;
  NEW.saldo_anterior := ROUND(COALESCE(v_saldo, 0), 2);

  NEW.uber_iva_valor := v_com_uber;
  NEW.bolt_iva := v_com_bolt;
  NEW.iva_cobrar := v_com_total;
  NEW.rendimento_liquido := COALESCE(NEW.uber_bruto, 0) + v_base_bolt + v_sem_com;
  NEW.valor_final := COALESCE(NEW.uber_bruto, 0) + v_base_bolt + v_sem_com
                   - v_com_total - COALESCE(NEW.slot_valor, 0) - COALESCE(NEW.aluguer_valor, 0)
                   - COALESCE(NEW.prio_valor, 0) - COALESCE(NEW.viaverde_valor, 0)
                   + NEW.saldo_anterior;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fp_importar_uber(p_empresa_id uuid, p_semana_inicio date, p_linhas jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb; v_uuid text; v_nome text; v_pago numeric; v_gorj numeric; v_bruto numeric;
  v_mot RECORD; v_pag RECORD; v_seg date; v_dom date;
  v_criados int := 0; v_atualizados int := 0; v_pagos int := 0; v_sem_mot text[] := '{}'; v_ignorados int := 0;
  v_norm text;
BEGIN
  v_seg := p_semana_inicio - ((EXTRACT(ISODOW FROM p_semana_inicio)::int) - 1);
  v_dom := v_seg + 6;

  FOR r IN SELECT * FROM jsonb_array_elements(p_linhas) LOOP
    v_uuid := NULLIF(trim(r->>'uuid'), '');
    v_nome := trim(coalesce(r->>'nome', ''));
    v_pago := COALESCE((r->>'pago')::numeric, 0);
    v_gorj := COALESCE((r->>'gorjeta')::numeric, 0);
    IF v_nome = '' THEN v_ignorados := v_ignorados + 1; CONTINUE; END IF;
    -- linhas de empresa (não motorista)
    IF lower(v_nome) ~ '(lda|unipessoal|formacao|formação|instituto)' THEN v_ignorados := v_ignorados + 1; CONTINUE; END IF;
    v_bruto := ROUND(v_pago - v_gorj, 2);

    -- match: uber_driver_id → nome exato → normalizado
    v_mot := NULL;
    IF v_uuid IS NOT NULL THEN
      SELECT m.* INTO v_mot FROM motoristas m WHERE m.empresa_id = p_empresa_id AND m.uber_driver_id = v_uuid LIMIT 1;
    END IF;
    IF v_mot IS NULL THEN
      SELECT m.* INTO v_mot FROM motoristas m WHERE m.empresa_id = p_empresa_id
        AND (lower(trim(m.uber_nome)) = lower(v_nome) OR lower(trim(m.nome)) = lower(v_nome)) LIMIT 1;
    END IF;
    IF v_mot IS NULL THEN
      v_norm := lower(regexp_replace(unaccent(v_nome), '[^a-z ]', '', 'g'));
      SELECT m.* INTO v_mot FROM motoristas m WHERE m.empresa_id = p_empresa_id
        AND lower(regexp_replace(unaccent(coalesce(m.uber_nome, m.nome)), '[^a-z ]', '', 'g')) = v_norm LIMIT 1;
    END IF;
    IF v_mot IS NULL THEN
      -- último recurso: primeiro + último nome
      SELECT m.* INTO v_mot FROM motoristas m WHERE m.empresa_id = p_empresa_id
        AND split_part(lower(unaccent(m.nome)), ' ', 1) = split_part(lower(unaccent(v_nome)), ' ', 1)
        AND regexp_replace(lower(unaccent(m.nome)), '^.* ', '') = regexp_replace(lower(unaccent(v_nome)), '^.* ', '')
      LIMIT 1;
    END IF;
    IF v_mot IS NULL THEN v_sem_mot := array_append(v_sem_mot, v_nome || ' (' || v_pago || ' €)'); CONTINUE; END IF;

    -- memorizar identificadores Uber
    UPDATE motoristas SET uber_driver_id = COALESCE(uber_driver_id, v_uuid), uber_nome = COALESCE(uber_nome, v_nome)
    WHERE id = v_mot.id AND (uber_driver_id IS NULL OR uber_nome IS NULL);

    SELECT * INTO v_pag FROM pagamentos WHERE empresa_id = p_empresa_id AND motorista_id = v_mot.id AND semana_inicio = v_seg;
    IF v_pag.id IS NOT NULL THEN
      IF v_pag.estado = 'pago' THEN
        IF abs(COALESCE(v_pag.uber_bruto,0) - v_bruto) >= 0.01 OR abs(COALESCE(v_pag.uber_gorjetas,0) - v_gorj) >= 0.01 THEN
          UPDATE pagamentos SET notas = COALESCE(notas || ' | ', '') || '[Uber ' || to_char(now(),'YYYY-MM-DD') || '] relatório devolve '
            || v_bruto || ' + gorjetas ' || v_gorj || ' ≠ pago (' || COALESCE(v_pag.uber_bruto,0) || ' + ' || COALESCE(v_pag.uber_gorjetas,0) || ')'
          WHERE id = v_pag.id;
        END IF;
        v_pagos := v_pagos + 1;
      ELSE
        UPDATE pagamentos SET uber_bruto = v_bruto, uber_liquido = v_bruto, uber_gorjetas = v_gorj,
          uber_iva_pct = COALESCE(v_mot.comissao_pct, 6), origem = CASE WHEN origem = 'api' THEN 'api+csv' ELSE 'csv' END
        WHERE id = v_pag.id;
        v_atualizados := v_atualizados + 1;
      END IF;
    ELSE
      INSERT INTO pagamentos (empresa_id, motorista_id, semana_inicio, semana_fim, origem,
        uber_bruto, uber_liquido, uber_gorjetas, uber_iva_pct, slot_valor, aluguer_valor, estado)
      VALUES (p_empresa_id, v_mot.id, v_seg, v_dom, 'csv',
        v_bruto, v_bruto, v_gorj, COALESCE(v_mot.comissao_pct, 6), COALESCE(v_mot.slot_semanal, 0), COALESCE(v_mot.aluguer_semanal, 0), 'pendente');
      v_criados := v_criados + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'semana', v_seg, 'criados', v_criados, 'atualizados', v_atualizados,
                            'pagos_intocados', v_pagos, 'ignorados', v_ignorados, 'sem_motorista', to_jsonb(v_sem_mot));
END $$;
