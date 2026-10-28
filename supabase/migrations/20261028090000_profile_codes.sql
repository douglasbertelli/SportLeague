-- Código pessoal do jogador (JG + 6) e do técnico (TC + 6), como o código do
-- time. Aparece no Perfil para copiar, compartilhar e gerar outro; o
-- administrador digita o código em Convidar para mandar o convite direto. O
-- app não escolhe o código: ele nasce com o papel e só muda por
-- `regenerate_my_code`.

alter table public.profiles add column code text unique;

-- Prefixo + 6 caracteres sem os parecidos (0/O, 1/I/L), que não exista ainda.
create or replace function private.new_profile_code(p_prefix text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  new_code text;
begin
  loop
    new_code := p_prefix;
    for i in 1..6 loop
      new_code := new_code
        || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (
      select 1 from public.profiles p where p.code = new_code
    );
  end loop;
  return new_code;
end;
$$;

-- Jogador JG, técnico TC, administrador (e quem ainda não escolheu) sem
-- código. O cliente não muda o código: só `regenerate_my_code`.
create or replace function private.set_profile_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  prefix text := case new.role
    when 'player' then 'JG'
    when 'coach' then 'TC'
  end;
begin
  if coalesce(current_setting('app.new_profile_code', true), '') <> 'on' then
    new.code := case when tg_op = 'UPDATE' then old.code end;
  end if;
  if prefix is null then
    new.code := null;
  elsif new.code is null or left(new.code, 2) <> prefix then
    new.code := private.new_profile_code(prefix);
  end if;
  return new;
end;
$$;

create trigger profiles_set_code
before insert or update on public.profiles
for each row execute function private.set_profile_code();

-- Gera outro código para o usuário logado; o antigo deixa de valer.
create or replace function public.regenerate_my_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_code text;
begin
  select private.new_profile_code(case p.role
      when 'player' then 'JG'
      when 'coach' then 'TC'
    end)
  into new_code
  from public.profiles p
  where p.id = (select auth.uid()) and p.role in ('player', 'coach');
  if new_code is null then
    raise exception 'only players and coaches have a code';
  end if;
  perform set_config('app.new_profile_code', 'on', true);
  update public.profiles set code = new_code where id = (select auth.uid());
  perform set_config('app.new_profile_code', '', true);
  return new_code;
end;
$$;

revoke execute on function private.new_profile_code(text) from public, anon;
revoke execute on function private.set_profile_code() from public, anon;
revoke execute on function public.regenerate_my_code() from public, anon;
grant execute on function public.regenerate_my_code() to authenticated;

-- Jogadores e técnicos que já existem ganham o código.
update public.profiles set code = null where role in ('player', 'coach');

-- O convite do dono a um técnico (pelo código) também é de técnico: aceito,
-- ele entra na comissão técnica, não no elenco.
create or replace function private.set_invite_kind()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.kind := case
    when exists (
      select 1 from public.profiles p
      where p.id = new.profile_id and p.role = 'coach'
    ) then 'coach'
    else 'player'
  end;
  return new;
end;
$$;
