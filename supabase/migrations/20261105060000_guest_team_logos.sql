-- Símbolo (logo) dos times fictícios, enviado pelo administrador dono (no
-- bucket público team-logos, na pasta dele). Como os fictícios só são
-- visíveis para o dono, a inscrição no campeonato guarda uma cópia do logo
-- (como já faz com o nome), atualizada quando o dono troca o símbolo.

alter table public.guest_teams add column logo_url text;

alter table public.championship_teams add column logo_url text;

-- Inscrição: além do nome, o logo do fictício.
create or replace function private.prepare_championship_team()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.team_id is not null then
    select t.name,
           case when t.owner_id = c.owner_id then 'accepted' else 'invited' end
    into new.name, new.status
    from public.teams t, public.championships c
    where t.id = new.team_id and c.id = new.championship_id;
    new.logo_url := null;
  else
    select name, logo_url into new.name, new.logo_url
    from public.guest_teams where id = new.guest_team_id;
    new.status := 'accepted';
  end if;
  return new;
end;
$$;

-- O dono troca o nome ou o símbolo do fictício: as inscrições acompanham.
create or replace function private.sync_guest_team_entries()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.championship_teams
  set name = new.name, logo_url = new.logo_url
  where guest_team_id = new.id
    and (name, logo_url) is distinct from (new.name, new.logo_url);
  return new;
end;
$$;

revoke execute on function private.sync_guest_team_entries() from public, anon;

create trigger guest_teams_sync_entries
after update of name, logo_url on public.guest_teams
for each row execute function private.sync_guest_team_entries();
