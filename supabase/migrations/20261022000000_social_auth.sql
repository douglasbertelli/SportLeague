-- Login social (Google e Apple).
-- Essas contas não enviam o tipo de perfil no cadastro: o role fica nulo até
-- o usuário escolher no app, na tela "Complete seu cadastro".

alter table public.profiles alter column role drop not null;

-- Nome: full_name (cadastro por e-mail, Google e Apple) ou name (Google).
-- Foto: avatar_url ou picture (Google).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := new.raw_user_meta_data;
  name text := left(trim(coalesce(
    nullif(trim(meta ->> 'full_name'), ''),
    nullif(trim(meta ->> 'name'), ''),
    ''
  )), 120);
begin
  insert into public.profiles (id, full_name, role, avatar_url)
  values (
    new.id,
    case when char_length(name) >= 2 then name else 'Usuário' end,
    (meta ->> 'role')::public.user_role,
    coalesce(meta ->> 'avatar_url', meta ->> 'picture')
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- O plano continua exclusivo do backend. O role pode ser definido pelo próprio
-- usuário uma única vez, quando ainda está nulo (login social).
create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and (
       new.plan is distinct from old.plan
       or (new.role is distinct from old.role
           and (old.role is not null or new.role is null))
     ) then
    raise exception 'plan and role cannot be changed by the client';
  end if;
  return new;
end;
$$;
