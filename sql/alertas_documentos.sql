-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Alertas de validade de documentos (motorista + viatura)
-- ════════════════════════════════════════════════════════════════════
-- Diariamente (pg_cron 08:30 Lisboa ≈ 08:30 UTC no inverno): para cada documento
-- com validade a 30 dias, 7 dias, no próprio dia, ou já expirado (1 aviso),
-- envia mensagem no chat ao motorista (documento dele, ou da viatura que conduz).
-- Dedupe em notificacoes_enviadas (tipo 'doc_validade', referencia_id = documento,
-- assunto = patamar).
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fp_alertar_documentos()
RETURNS TABLE (enviados INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r RECORD; v_n INT := 0; v_patamar TEXT; v_dias INT; v_txt TEXT; v_doc TEXT; v_mot UUID;
BEGIN
  FOR r IN
    SELECT d.id, d.empresa_id, d.motorista_id, d.veiculo_id, d.tipo, d.nome, d.validade,
           v.matricula, v.motorista_id AS motorista_viatura
    FROM documentos d
    LEFT JOIN veiculos v ON v.id = d.veiculo_id
    WHERE d.validade IS NOT NULL
      AND d.validade <= current_date + 30
      AND d.validade >= current_date - 1
  LOOP
    v_dias := r.validade - current_date;
    v_patamar := CASE WHEN v_dias < 0 THEN 'expirado' WHEN v_dias = 0 THEN 'hoje'
                      WHEN v_dias <= 7 THEN '7d' ELSE '30d' END;
    -- 30d só entre 25 e 30 dias; 7d só entre 1 e 7; evita avisar todos os dias
    IF v_patamar = '30d' AND v_dias < 25 THEN CONTINUE; END IF;

    v_mot := COALESCE(r.motorista_id, r.motorista_viatura);
    IF v_mot IS NULL THEN CONTINUE; END IF;

    IF EXISTS (SELECT 1 FROM notificacoes_enviadas n
               WHERE n.tipo = 'doc_validade' AND n.referencia_id = r.id AND n.assunto = v_patamar) THEN
      CONTINUE;
    END IF;

    v_doc := CASE r.tipo
      WHEN 'cc_motorista' THEN 'Cartão de Cidadão'
      WHEN 'carta_conducao' THEN 'carta de condução'
      WHEN 'certificado_motorista' THEN 'certificado de motorista TVDE'
      WHEN 'seguro_auto' THEN 'seguro da viatura' || COALESCE(' ' || r.matricula, '')
      WHEN 'dua' THEN 'DUA da viatura' || COALESCE(' ' || r.matricula, '')
      WHEN 'inspecao' THEN 'inspeção da viatura' || COALESCE(' ' || r.matricula, '')
      WHEN 'licenca_tvde_veiculo' THEN 'licença TVDE da viatura' || COALESCE(' ' || r.matricula, '')
      ELSE COALESCE(r.nome, r.tipo) END;

    v_txt := CASE v_patamar
      WHEN '30d' THEN '📅 Aviso com tempo: o seu ' || v_doc || ' expira a ' || to_char(r.validade, 'DD/MM/YYYY') || ' (daqui a ' || v_dias || ' dias). Trate da renovação com calma — depois carregue o novo na app, em Os meus documentos.'
      WHEN '7d'  THEN '⏳ Última semana: o seu ' || v_doc || ' expira a ' || to_char(r.validade, 'DD/MM/YYYY') || '. Se já tem o novo, carregue-o na app; se não, está na hora de tratar disso.'
      WHEN 'hoje' THEN '🚨 O seu ' || v_doc || ' expira HOJE. Sem documento válido não pode trabalhar — carregue o novo na app assim que o tiver.'
      ELSE '⛔ O seu ' || v_doc || ' expirou a ' || to_char(r.validade, 'DD/MM/YYYY') || '. Não circule sem o renovar; carregue o novo na app, em Os meus documentos.' END;

    INSERT INTO mensagens (empresa_id, motorista_id, autor, autor_nome, mensagem)
    VALUES (r.empresa_id, v_mot, 'operador', 'FleetPay', v_txt);

    INSERT INTO notificacoes_enviadas (empresa_id, motorista_id, tipo, referencia_id, canal, assunto, enviado_em, sucesso)
    VALUES (r.empresa_id, v_mot, 'doc_validade', r.id, 'chat', v_patamar, now(), true);

    v_n := v_n + 1;
  END LOOP;
  RETURN QUERY SELECT v_n;
END; $$;

SELECT cron.schedule('fleetpay-alertas-documentos', '30 8 * * *', $$ SELECT fp_alertar_documentos(); $$);
