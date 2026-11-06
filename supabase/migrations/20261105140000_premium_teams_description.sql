-- Texto mais curto para Times no Premium.
update public.plan_features set description =
  'Times ilimitados na mesma conta, cada um com elenco, jogos, escalação, '
  || 'estatísticas e convites. Troque entre eles com um toque.'
where plan = 'premium' and feature = 'teams';
