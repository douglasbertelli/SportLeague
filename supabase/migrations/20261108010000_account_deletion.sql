-- Exclusão da conta. O usuário pede pelo app; a conta fica inativa por 7
-- dias e então é apagada de vez (com tudo o que depende dela: times do
-- administrador, vínculos, notificações…). Nos 7 dias, ao entrar de novo, o
-- usuário pode reativar. Enquanto está inativa, a conta some para os outros:
-- o perfil e os times do administrador deixam de aparecer.

alter table public.profiles add column deleted_at timestamptz;

create index profiles_deleted_at on public.profiles (deleted_at)
  where deleted_at is not null;

create or replace function private.is_inactive(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles where id = uid and deleted_at is not null
  );
$$;

revoke execute on function private.is_inactive(uuid) from public, anon;
grant execute on function private.is_inactive(uuid) to authenticated;

-- O próprio usuário continua vendo o perfil (para reativar).
drop policy "Perfis visíveis para usuários autenticados" on public.profiles;
create policy "Perfis visíveis para usuários autenticados"
on public.profiles for select
to authenticated
using (deleted_at is null or id = (select auth.uid()));

drop policy "Times visíveis para usuários autenticados" on public.teams;
create policy "Times visíveis para usuários autenticados"
on public.teams for select
to authenticated
using (owner_id = (select auth.uid()) or not private.is_inactive(owner_id));

-- Pede a exclusão: a conta fica inativa e o aparelho deixa de receber push.
-- Devolve quando a exclusão vira definitiva.
create or replace function public.request_account_deletion()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  at timestamptz := now();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  update public.profiles
  set deleted_at = coalesce(deleted_at, at)
  where id = uid
  returning deleted_at into at;
  delete from public.device_tokens where user_id = uid;
  return at + interval '7 days';
end;
$$;

-- Reativa (só nos 7 dias; depois a conta já não existe).
create or replace function public.cancel_account_deletion()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles set deleted_at = null where id = auth.uid();
$$;

revoke execute on function public.request_account_deletion() from public, anon;
revoke execute on function public.cancel_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;

-- Exclusão definitiva das contas inativas há 7 dias. Apagar o usuário do
-- Auth apaga o perfil e, em cascata, o que depende dele. Os arquivos do
-- Storage que ficarem sem dono saem na limpeza diária (storage-cleanup).
create or replace function private.purge_deleted_accounts()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  purged integer;
begin
  delete from auth.users
  where id in (
    select id from public.profiles
    where deleted_at is not null
      and deleted_at <= now() - interval '7 days'
  );
  get diagnostics purged = row_count;
  return purged;
end;
$$;

revoke execute on function private.purge_deleted_accounts() from public, anon, authenticated;

-- Todo dia às 3h de Brasília (antes da limpeza do Storage, às 4h).
select cron.schedule(
  'account-purge',
  '0 6 * * *',
  $$select private.purge_deleted_accounts()$$
);

-- A vaquinha continua no time quando quem criou exclui a conta.
alter table public.fundraisers alter column created_by drop not null;
alter table public.fundraisers drop constraint fundraisers_created_by_fkey;
alter table public.fundraisers add constraint fundraisers_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete set null;
