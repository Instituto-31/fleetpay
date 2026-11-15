-- Média da frota numa semana (só agregados; nunca valores individuais de terceiros).
CREATE OR REPLACE FUNCTION public.fp_media_frota_semana(p_semana_inicio date)
RETURNS TABLE (media_rendimento numeric, n_motoristas integer, meu_rendimento numeric)
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$
  WITH eu AS (
    SELECT m.id AS motorista_id, m.empresa_id FROM motoristas m WHERE m.perfil_id = auth.uid()
    ORDER BY m.ativo DESC NULLS LAST, m.criado_em DESC LIMIT 1
  ),
  base AS (
    SELECT p.motorista_id,
           COALESCE(p.uber_bruto,0) + COALESCE(p.bolt_liquido,0) + COALESCE(p.bolt_gorjetas,0)
             + COALESCE(p.bolt_campanha,0) + COALESCE(p.bolt_cancelamentos,0) + COALESCE(p.bolt_reembolsos,0) AS rend
    FROM pagamentos p, eu
    WHERE p.empresa_id = eu.empresa_id AND p.semana_inicio = p_semana_inicio AND p.publicado_em IS NOT NULL
  )
  SELECT ROUND(AVG(b.rend) FILTER (WHERE b.rend > 0), 2),
         COUNT(*) FILTER (WHERE b.rend > 0)::int,
         (SELECT b2.rend FROM base b2, eu WHERE b2.motorista_id = eu.motorista_id LIMIT 1)
  FROM base b;
$$;
GRANT EXECUTE ON FUNCTION public.fp_media_frota_semana(date) TO authenticated;
