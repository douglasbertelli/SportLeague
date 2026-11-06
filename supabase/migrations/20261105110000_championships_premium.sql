-- Organizar campeonatos passa a ser só do Premium. No Gratuito o time
-- continua participando dos campeonatos para os quais for convidado; os
-- campeonatos que já existem continuam (só não dá para criar outro).
update public.plan_features set quota = 0
where plan = 'free' and feature = 'championships';
