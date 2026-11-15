-- ════════════════════════════════════════════════════════════════════
-- FleetPay — Fecho automático de sessões de condução esquecidas
-- ════════════════════════════════════════════════════════════════════
-- Corre de hora a hora (pg_cron). Fecha registos_conducao sem fim:
--   • pausa     aberta há mais de 12 h
--   • conducao  aberta há mais de 14 h
-- Fecha com fim = inicio + 1 minuto (não inventa horas de condução), anota
-- o motivo e envia uma mensagem ao motorista no chat do FleetPay.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fp_fechar_sessoes_esquecidas()
RETURNS TABLE (fechadas INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_n INT := 0;
  v_tipo_txt TEXT;
  v_inicio_txt TEXT;
BEGIN
  FOR r IN
    SELECT rc.id, rc.motorista_id, rc.empresa_id, rc.tipo, rc.inicio
    FROM registos_conducao rc
    WHERE rc.fim IS NULL
      AND (
        (rc.tipo = 'pausa'    AND rc.inicio < now() - interval '12 hours') OR
        (rc.tipo = 'conducao' AND rc.inicio < now() - interval '14 hours')
      )
  LOOP
    UPDATE registos_conducao
    SET fim = r.inicio + interval '1 minute',
        duracao_segundos = 60,
        notas = COALESCE(notas || ' | ', '') || 'Fechada automaticamente (sessão esquecida) em '
                || to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI'),
        atualizado_em = now()
    WHERE id = r.id;

    v_tipo_txt := CASE WHEN r.tipo = 'conducao' THEN 'condução' ELSE 'pausa' END;
    v_inicio_txt := to_char(r.inicio AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI');

    INSERT INTO mensagens (empresa_id, motorista_id, autor, autor_nome, mensagem)
    VALUES (
      r.empresa_id, r.motorista_id, 'operador', 'FleetPay',
      '⏱️ A sua sessão de ' || v_tipo_txt || ' de ' || v_inicio_txt
      || ' ficou aberta e fechámo-la automaticamente, sem horas contadas. '
      || 'Acontece aos melhores (e aos cafés fortes). Da próxima, termine a sessão ao acabar o serviço — '
      || 'numa fiscalização, os tempos de condução são da sua responsabilidade. Boas corridas! 🚕'
    );

    v_n := v_n + 1;
  END LOOP;

  RETURN QUERY SELECT v_n;
END;
$$;

-- Agendamento: todas as horas aos 20 min
SELECT cron.unschedule('fleetpay-fechar-sessoes-esquecidas')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fleetpay-fechar-sessoes-esquecidas');
SELECT cron.schedule('fleetpay-fechar-sessoes-esquecidas', '20 * * * *', $$ SELECT fp_fechar_sessoes_esquecidas(); $$);
