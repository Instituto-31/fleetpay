-- Ganhos provisórios da semana em curso para o motorista autenticado (app motorista).
-- Devolve só faturação por plataforma (sem despesas nem valor final) — o detalhe
-- continua reservado até o operador publicar (publicado_em).
CREATE OR REPLACE FUNCTION public.fp_semana_em_curso()
RETURNS TABLE (
  semana_inicio date, semana_fim date, uber_bruto numeric, bolt_total numeric,
  bolt_gorjetas numeric, atualizado_em timestamptz, publicado boolean
)
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$
  WITH seg AS (
    SELECT (date_trunc('week', (now() AT TIME ZONE 'Europe/Lisbon')::date::timestamp))::date AS ini
  )
  SELECT p.semana_inicio, p.semana_fim,
         COALESCE(p.uber_bruto, 0),
         COALESCE(p.bolt_liquido,0) + COALESCE(p.bolt_gorjetas,0) + COALESCE(p.bolt_campanha,0)
           + COALESCE(p.bolt_cancelamentos,0) + COALESCE(p.bolt_reembolsos,0),
         COALESCE(p.bolt_gorjetas, 0),
         p.atualizado_em,
         p.publicado_em IS NOT NULL
  FROM pagamentos p
  JOIN motoristas m ON m.id = p.motorista_id
  CROSS JOIN seg
  WHERE m.perfil_id = auth.uid() AND p.semana_inicio = seg.ini
  ORDER BY p.atualizado_em DESC
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.fp_semana_em_curso() TO authenticated;
