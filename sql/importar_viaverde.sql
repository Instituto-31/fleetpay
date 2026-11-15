-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Importação Via Verde no servidor (2026-11-15)
-- ════════════════════════════════════════════════════════════════════
-- Usada pela tarefa automática de segunda-feira (e utilizável pelo admin).
-- Replica a lógica de processViaVerde() + aplicarPrioViaVerde() do admin.html:
--   • cada linha = 1 portagem {matricula, data, hora, valor, descricao}
--   • a matrícula é procurada em TODAS as empresas (o ficheiro do alias pode
--     trazer viaturas das duas frotas); se não existir, fica na empresa
--     p_empresa_default sem motorista
--   • duplicados ignorados (UNIQUE empresa_id, matricula, data, hora, valor)
--   • semana_inicio = segunda-feira da data da portagem
--   • depois aplica Σ portagens → pagamentos.viaverde_valor nas semanas
--     afectadas; semana paga nunca é reescrita (fica nas notas se diferir)
--   • pagamentos criados mais tarde (ex.: importação Uber) herdam as
--     portagens já carregadas (ver trigger abaixo)
--
-- p_linhas: [{ "matricula":"AA-00-BB", "data":"2026-11-10", "hora":"08:15:00",
--              "valor":1.35, "descricao":"Ave → Guimaraes" }, ...]
-- ════════════════════════════════════════════════════════════════════

-- 1. Trigger: um pagamento NOVO sem viaverde_valor herda as portagens já carregadas
CREATE OR REPLACE FUNCTION public.fp_pagamento_auto_calcular()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_pct numeric; v_modelo text; v_div numeric;
  v_com_uber numeric; v_com_bolt numeric; v_com_total numeric;
  v_base_bolt numeric; v_sem_com numeric;
  v_saldo numeric; v_vv numeric;
BEGIN
  IF NEW.estado = 'pago' AND TG_OP = 'UPDATE' AND OLD.estado = 'pago' THEN RETURN NEW; END IF;

  -- Portagens já importadas para este motorista/semana (só na criação do pagamento)
  IF TG_OP = 'INSERT' AND COALESCE(NEW.viaverde_valor, 0) = 0 AND NEW.motorista_id IS NOT NULL THEN
    SELECT COALESCE(SUM(valor), 0) INTO v_vv
    FROM viaverde_portagens
    WHERE motorista_id = NEW.motorista_id AND semana_inicio = NEW.semana_inicio;
    IF v_vv > 0 THEN NEW.viaverde_valor := ROUND(v_vv, 2); END IF;
  END IF;

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
  NEW.total_despesas := v_com_total + COALESCE(NEW.slot_valor, 0) + COALESCE(NEW.aluguer_valor, 0)
                      + COALESCE(NEW.prio_valor, 0) + COALESCE(NEW.viaverde_valor, 0)
                      + COALESCE(NEW.outros_descontos, 0);
  NEW.valor_final := COALESCE(NEW.uber_bruto, 0) + v_base_bolt + v_sem_com
                   - v_com_total - COALESCE(NEW.slot_valor, 0) - COALESCE(NEW.aluguer_valor, 0)
                   - COALESCE(NEW.prio_valor, 0) - COALESCE(NEW.viaverde_valor, 0)
                   + NEW.saldo_anterior;
  RETURN NEW;
END;
$$;

-- 2. Aplicar Σ portagens de uma semana aos pagamentos (semana paga → nota)
CREATE OR REPLACE FUNCTION public.fp_aplicar_viaverde_semana(p_empresa_id uuid, p_semana date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record; v_atual integer := 0; v_pagos integer := 0; v_sem_pag integer := 0;
BEGIN
  FOR r IN
    SELECT v.motorista_id, ROUND(SUM(v.valor), 2) AS total
    FROM viaverde_portagens v
    WHERE v.empresa_id = p_empresa_id AND v.semana_inicio = p_semana AND v.motorista_id IS NOT NULL
    GROUP BY v.motorista_id
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pagamentos WHERE empresa_id = p_empresa_id AND semana_inicio = p_semana AND motorista_id = r.motorista_id) THEN
      v_sem_pag := v_sem_pag + 1;            -- o pagamento ainda não existe; herda via trigger quando for criado
      CONTINUE;
    END IF;

    UPDATE pagamentos p
       SET viaverde_valor = r.total
     WHERE p.empresa_id = p_empresa_id AND p.semana_inicio = p_semana AND p.motorista_id = r.motorista_id
       AND p.estado <> 'pago' AND COALESCE(p.viaverde_valor, 0) <> r.total;
    IF FOUND THEN v_atual := v_atual + 1; END IF;

    UPDATE pagamentos p
       SET notas = CONCAT_WS(E'\n', NULLIF(p.notas, ''),
             format('[Via Verde %s] ficheiro devolve %s € de portagens, pagamento tinha %s € → acerto %s €',
                    to_char(CURRENT_DATE, 'YYYY-MM-DD'), r.total, COALESCE(p.viaverde_valor, 0),
                    ROUND(r.total - COALESCE(p.viaverde_valor, 0), 2)))
     WHERE p.empresa_id = p_empresa_id AND p.semana_inicio = p_semana AND p.motorista_id = r.motorista_id
       AND p.estado = 'pago' AND COALESCE(p.viaverde_valor, 0) <> r.total
       AND COALESCE(p.notas, '') NOT LIKE '%[Via Verde ' || to_char(CURRENT_DATE, 'YYYY-MM-DD') || ']%';
    IF FOUND THEN v_pagos := v_pagos + 1; END IF;
  END LOOP;

  RETURN jsonb_build_object('semana', p_semana, 'atualizados', v_atual, 'pagos_com_nota', v_pagos, 'sem_pagamento', v_sem_pag);
END;
$$;

-- 3. Importação propriamente dita
CREATE OR REPLACE FUNCTION public.fp_importar_viaverde(p_empresa_default uuid, p_linhas jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  l jsonb; v_mat text; v_data date; v_hora time; v_valor numeric; v_desc text;
  v_emp uuid; v_mot uuid; v_veic uuid; v_sem date;
  v_inseridas integer := 0; v_dup integer := 0; v_sem_mot integer := 0; v_invalidas integer := 0;
  v_total numeric := 0;
  v_semanas jsonb := '[]'::jsonb; v_sem_rec record; v_aplicado jsonb := '[]'::jsonb;
  v_mats_sem_mot text[] := '{}';
BEGIN
  FOR l IN SELECT * FROM jsonb_array_elements(p_linhas) LOOP
    v_mat := upper(regexp_replace(COALESCE(l->>'matricula', ''), '[\s\-]', '', 'g'));
    BEGIN
      v_data  := (l->>'data')::date;
      v_hora  := COALESCE(NULLIF(l->>'hora', ''), '00:00:00')::time;
      v_valor := ROUND(COALESCE((l->>'valor')::numeric, 0), 2);
    EXCEPTION WHEN OTHERS THEN
      v_invalidas := v_invalidas + 1; CONTINUE;
    END;
    v_desc := NULLIF(l->>'descricao', '');
    IF v_mat = '' OR v_valor = 0 OR v_data IS NULL THEN v_invalidas := v_invalidas + 1; CONTINUE; END IF;

    -- viatura em qualquer empresa (prefere a empresa por omissão em caso de matrícula repetida)
    v_emp := NULL; v_mot := NULL; v_veic := NULL;
    SELECT ve.empresa_id, ve.motorista_id, ve.id INTO v_emp, v_mot, v_veic
    FROM veiculos ve
    WHERE upper(regexp_replace(COALESCE(ve.matricula, ''), '[\s\-]', '', 'g')) = v_mat
    ORDER BY (ve.empresa_id = p_empresa_default) DESC, ve.motorista_id IS NULL
    LIMIT 1;
    IF v_emp IS NULL THEN
      v_emp := p_empresa_default;
      v_sem_mot := v_sem_mot + 1;
      IF NOT v_mat = ANY(v_mats_sem_mot) THEN v_mats_sem_mot := v_mats_sem_mot || v_mat; END IF;
    ELSIF v_mot IS NULL THEN
      v_sem_mot := v_sem_mot + 1;
      IF NOT v_mat = ANY(v_mats_sem_mot) THEN v_mats_sem_mot := v_mats_sem_mot || v_mat; END IF;
    END IF;

    v_sem := date_trunc('week', v_data)::date;   -- segunda-feira

    INSERT INTO viaverde_portagens (empresa_id, motorista_id, veiculo_id, matricula, data, hora, valor, descricao, semana_inicio, origem)
    VALUES (v_emp, v_mot, v_veic, v_mat, v_data, v_hora, v_valor, v_desc, v_sem, 'csv')
    ON CONFLICT (empresa_id, matricula, data, hora, valor) DO NOTHING;
    IF FOUND THEN
      v_inseridas := v_inseridas + 1; v_total := v_total + v_valor;
      IF NOT v_semanas @> jsonb_build_array(jsonb_build_object('e', v_emp, 's', v_sem)) THEN
        v_semanas := v_semanas || jsonb_build_object('e', v_emp, 's', v_sem);
      END IF;
    ELSE
      v_dup := v_dup + 1;
    END IF;
  END LOOP;

  -- aplicar aos pagamentos das semanas tocadas
  FOR v_sem_rec IN SELECT (x->>'e')::uuid AS e, (x->>'s')::date AS s FROM jsonb_array_elements(v_semanas) x LOOP
    v_aplicado := v_aplicado || (fp_aplicar_viaverde_semana(v_sem_rec.e, v_sem_rec.s) || jsonb_build_object('empresa_id', v_sem_rec.e));
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'inseridas', v_inseridas, 'duplicadas', v_dup, 'invalidas', v_invalidas,
    'total_inserido', ROUND(v_total, 2),
    'sem_motorista', v_sem_mot, 'matriculas_sem_motorista', to_jsonb(v_mats_sem_mot),
    'pagamentos', v_aplicado
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fp_importar_viaverde(uuid, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.fp_importar_viaverde(uuid, jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fp_aplicar_viaverde_semana(uuid, date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.fp_aplicar_viaverde_semana(uuid, date) TO authenticated, service_role;

SELECT 'fp_importar_viaverde + fp_aplicar_viaverde_semana criadas; trigger herda portagens' AS resultado;
