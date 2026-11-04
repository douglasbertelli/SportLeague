-- A mensalidade no fluxo das notificações (como a vaquinha). Além dos
-- lembretes de vencimento e atraso ('dues'):
--   * 'dues_new': o time passou a cobrar (atletas com conta e técnicos);
--   * 'dues_changed': o valor, o vencimento ou a chave PIX mudou (os mesmos);
--   * 'dues_paid': o dono marcou o mês do atleta como pago (o atleta).
-- Quem fez a ação (o dono) não é avisado.

-- "R$ 1.250,00".
create or replace function private.format_money(p_cents integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'R$ ' || translate(
    to_char(p_cents / 100.0, 'FM999,999,990.00'), ',.', '.,'
  );
$$;

-- "novembro".
create or replace function private.month_name(p_month date)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array[
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
    'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ])[extract(month from p_month)::int];
$$;

-- Atletas com conta e técnicos do time.
create or replace function private.team_followers(p_team uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.profile_id from public.team_players p
  where p.team_id = p_team and p.profile_id is not null
  union
  select c.profile_id from public.team_coaches c where c.team_id = p_team;
$$;

create or replace function private.notify_dues()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  member uuid;
  details text := private.format_money(new.amount_cents)
    || ' por mês, vence todo dia ' || new.due_day
    || case when new.pix_key is null then '' else '. PIX: ' || new.pix_key end
    || '.';
begin
  if tg_op = 'UPDATE'
     and new.amount_cents = old.amount_cents
     and new.due_day = old.due_day
     and new.pix_key is not distinct from old.pix_key then
    return new;
  end if;
  for member in select private.team_followers(new.team_id) loop
    if tg_op = 'INSERT' then
      perform private.notify(
        member, 'dues_new', 'Mensalidade do time',
        'O ' || private.team_name(new.team_id)
          || ' passou a cobrar mensalidade: ' || details,
        new.team_id
      );
    else
      perform private.notify(
        member, 'dues_changed', 'Mensalidade alterada',
        'A mensalidade do ' || private.team_name(new.team_id)
          || ' agora é ' || details,
        new.team_id
      );
    end if;
  end loop;
  return new;
end;
$$;

create trigger team_dues_notify
after insert or update on public.team_dues
for each row execute function private.notify_dues();

create or replace function private.notify_due_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  player uuid;
begin
  select profile_id into player from public.team_players where id = new.athlete_id;
  perform private.notify(
    player, 'dues_paid', 'Pagamento confirmado',
    'Sua mensalidade de ' || private.month_name(new.month) || ' do '
      || private.team_name(new.team_id) || ' foi confirmada.',
    new.team_id
  );
  return new;
end;
$$;

create trigger team_due_payments_notify
after insert on public.team_due_payments
for each row execute function private.notify_due_payment();

revoke execute on function private.format_money(integer) from public, anon;
revoke execute on function private.month_name(date) from public, anon;
revoke execute on function private.team_followers(uuid) from public, anon;
revoke execute on function private.notify_dues() from public, anon;
revoke execute on function private.notify_due_payment() from public, anon;
