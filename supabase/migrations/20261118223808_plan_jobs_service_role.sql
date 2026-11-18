-- `protect_profile_fields` só deixa mudar o plano quando o papel é
-- service_role. Os crons (asaas_expire, store_expire) rodam sem JWT, então
-- falhariam no dia em que precisassem devolver alguém ao Gratuito. As
-- funções que acertam o plano se declaram service_role só nesta transação.

create or replace function private.sync_paid_plan(uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  if private.store_active(uid) or private.asaas_active(uid) then
    update public.profiles set plan = 'premium'
    where id = uid and plan = 'free';
  else
    update public.profiles set plan = 'free'
    where id = uid and plan = 'premium';
  end if;
end;
$$;

create or replace function private.asaas_expire()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  today date := (now() at time zone 'America/Sao_Paulo')::date;
  n integer;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.profiles p set plan = 'free'
  from public.subscriptions s
  where s.profile_id = p.id
    and p.plan = 'premium'
    and (
      (s.status in ('canceled', 'pending') and coalesce(s.paid_until, today) <= today)
      or (s.status in ('active', 'overdue') and s.paid_until + 5 < today)
    )
    and not private.store_active(p.id);
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function private.store_expire()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.profiles p set plan = 'free'
  from public.store_subscriptions s
  where s.profile_id = p.id
    and p.plan = 'premium'
    and not private.store_active(p.id)
    and not private.asaas_active(p.id);
  get diagnostics n = row_count;
  return n;
end;
$$;
