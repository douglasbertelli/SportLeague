-- Texto de cada funcionalidade por plano, na tela de planos. Nulo = o texto
-- padrão do app. Mudar aqui muda a tela sem versão nova do app.
alter table public.plan_features add column description text
  check (description is null or length(trim(description)) between 1 and 300);

update public.plan_features set description =
  '1 time completo, com elenco, jogos, escalação, estatísticas e convites.'
where plan = 'free' and feature = 'teams';

update public.plan_features set description =
  'Times ilimitados na mesma conta (principal, veteranos, feminino, base…), '
  || 'cada um com elenco, jogos, escalação, estatísticas e convites. Troque '
  || 'entre eles com um toque.'
where plan = 'premium' and feature = 'teams';
