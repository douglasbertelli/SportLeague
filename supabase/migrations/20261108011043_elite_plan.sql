-- Plano Elite: para clientes VIP, dado só pelo painel do dono. Sem cobrança,
-- sem teste e com tudo liberado.
--
-- Não aparece na comparação dos planos (sem linha em `plans`) e não tem
-- linhas em `plan_features`: sem linha = sem limite, então toda
-- funcionalidade, inclusive as que vierem depois, já vale para ele.
-- O teste grátis continua só para o Gratuito (start_premium_trial e
-- plan_status já exigem plan = 'free').

alter type public.subscription_plan add value if not exists 'elite';

-- Plano que vale agora: o assinado (Premium ou Elite) ou o Premium do teste
-- em andamento. Compara com 'free' para não usar o valor novo do enum nesta
-- mesma transação.
create or replace function private.effective_plan(uid uuid)
returns public.subscription_plan
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p.plan <> 'free' then p.plan
    when exists (
      select 1 from private.premium_trials t
      where t.profile_id = p.id and t.ends_at > now()
    ) then 'premium'::public.subscription_plan
    else p.plan
  end
  from public.profiles p
  where p.id = uid;
$$;
