-- Cada time a mais no Premium passa a custar R$ 15,00 por mês.
update public.plans set extra_team_cents = 1500 where plan = 'premium';
