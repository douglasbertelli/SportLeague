-- Texto da escalação no campo: os jogadores são escolhidos tocando na
-- posição (não arrastando mais).
update public.plan_features set description =
  'Monte a escalação no campo: escolha a formação e toque em cada posição '
  || 'para escolher o jogador.'
where plan = 'premium' and feature = 'tactical_lineup';
