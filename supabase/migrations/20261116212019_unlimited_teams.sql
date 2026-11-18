-- Times sem limite em todos os planos. O que separa o Gratuito do Premium
-- passa a ser só as funcionalidades; o Premium tem preço único, sem
-- cobrança por time a mais.

update public.plan_features set quota = null where feature = 'teams';

update public.plan_features set description =
  'Times ilimitados na mesma conta, cada um com elenco, jogos, escalação, '
  || 'estatísticas e convites. Troque entre eles com um toque.'
where feature = 'teams';

-- Limites de times combinados por cliente (Elite) também deixam de valer.
delete from private.plan_overrides where feature = 'teams';

-- Preço único: asaas_desired_value passa a dar só a mensalidade base, e o
-- asaas-sync acerta no Asaas quem pagava por time a mais.
update public.plans set extra_team_cents = 0;

-- Aviso do fim do teste sem falar em "mais times".
create or replace function private.send_trial_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  t record;
  days_left integer;
  sent integer := 0;
begin
  -- Faltando até 3 dias.
  for t in
    select * from private.premium_trials
    where not ending_notified
      and ends_at > now()
      and ends_at <= now() + interval '3 days'
  loop
    days_left := greatest(1, ceil(extract(epoch from t.ends_at - now()) / 86400)::int);
    update private.premium_trials set ending_notified = true
    where profile_id = t.profile_id;
    perform private.notify(
      t.profile_id, 'plan', 'Seu teste do Premium está acabando',
      case when days_left = 1 then 'Falta 1 dia' else 'Faltam ' || days_left || ' dias' end
        || ' para o fim do teste. Depois, os recursos do Premium ficam '
        || 'bloqueados no plano Gratuito.'
    );
    sent := sent + 1;
  end loop;

  -- Terminou.
  for t in
    select * from private.premium_trials
    where not ended_notified and ends_at <= now()
  loop
    update private.premium_trials set ended_notified = true, ending_notified = true
    where profile_id = t.profile_id;
    -- Quem assinou não precisa do aviso.
    if exists (
      select 1 from public.profiles where id = t.profile_id and plan = 'free'
    ) then
      perform private.notify(
        t.profile_id, 'plan', 'Seu teste do Premium terminou',
        'Seus times, campeonatos e mensalidades continuam salvos. Criar e '
          || 'editar o que é do Premium fica bloqueado no plano Gratuito.'
      );
      sent := sent + 1;
    end if;
  end loop;
  return sent;
end;
$$;
