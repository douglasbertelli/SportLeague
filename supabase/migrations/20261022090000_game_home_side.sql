-- Mando do amistoso: quem marca escolhe jogar como mandante (padrão) ou
-- visitante. host_is_home é do ponto de vista do time que marcou; o
-- adversário fica com o lado oposto.

alter table public.games
  add column host_is_home boolean not null default true;

-- Mesma regra da game_status, agora tratando o mando como a data: se quem
-- marcou muda o mando de um jogo contra time da plataforma, ele volta a
-- aguardar o adversário aceitar. O adversário continua sem poder mudá-lo.
create or replace function public.check_game_status()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  is_host boolean;
begin
  -- Ao marcar: contra time da plataforma fica pendente; contra fictício, marcado.
  if tg_op = 'INSERT' then
    new.status := case
      when new.opponent_team_id is not null then 'pending'::public.game_status
      else 'scheduled'::public.game_status
    end;
    new.canceled_by_team_id := null;
    return new;
  end if;

  -- O backend passa.
  if uid is null or coalesce((select auth.role()), '') = 'service_role' then
    return new;
  end if;

  -- Exclusão de um time ou time fictício (on delete set null): só as
  -- referências ficam vazias. Um pendente sem adversário vira cancelado.
  if (to_jsonb(new) - array['opponent_team_id', 'opponent_guest_id', 'canceled_by_team_id', 'updated_at'])
     = (to_jsonb(old) - array['opponent_team_id', 'opponent_guest_id', 'canceled_by_team_id', 'updated_at'])
     and (new.opponent_team_id is null or new.opponent_team_id = old.opponent_team_id)
     and (new.opponent_guest_id is null or new.opponent_guest_id = old.opponent_guest_id)
     and (new.canceled_by_team_id is null or new.canceled_by_team_id = old.canceled_by_team_id) then
    if old.status = 'pending'
       and old.opponent_team_id is not null
       and new.opponent_team_id is null then
      new.status := 'canceled';
    end if;
    return new;
  end if;

  if old.status = 'canceled' then
    raise exception 'canceled games cannot be changed';
  end if;

  is_host := exists (
    select 1 from public.teams t
    where t.id = old.team_id and t.owner_id = uid
  );

  if is_host then
    if new.status = 'canceled' then
      -- Quem marcou cancelou.
      new.canceled_by_team_id := old.team_id;
      return new;
    end if;
    if new.status is distinct from old.status then
      -- Amistoso entre dois times do mesmo administrador: ele também é o
      -- adversário e pode aceitar (sem mudar mais nada).
      if new.status = 'scheduled' and old.status = 'pending'
         and exists (
           select 1 from public.teams t
           where t.id = old.opponent_team_id and t.owner_id = uid
         )
         and (to_jsonb(new) - array['status', 'canceled_by_team_id', 'updated_at'])
             = (to_jsonb(old) - array['status', 'canceled_by_team_id', 'updated_at']) then
        new.canceled_by_team_id := null;
        return new;
      end if;
      raise exception 'only the opponent can accept the game';
    end if;
    -- Mudou adversário, data ou mando de um jogo contra time da plataforma: volta a
    -- aguardar o adversário aceitar.
    if new.opponent_team_id is distinct from old.opponent_team_id
       or new.opponent_guest_id is distinct from old.opponent_guest_id
       or new.scheduled_at is distinct from old.scheduled_at
       or new.host_is_home is distinct from old.host_is_home then
      new.status := case
        when new.opponent_team_id is not null then 'pending'::public.game_status
        else 'scheduled'::public.game_status
      end;
    end if;
    new.canceled_by_team_id := null;
    return new;
  end if;

  -- Adversário: só muda a situação (aceitar, recusar, cancelar).
  if (to_jsonb(new) - array['status', 'canceled_by_team_id', 'updated_at'])
     is distinct from
     (to_jsonb(old) - array['status', 'canceled_by_team_id', 'updated_at']) then
    raise exception 'the opponent can only accept or cancel the game';
  end if;
  if new.status = 'scheduled' and old.status = 'pending' then
    new.canceled_by_team_id := null;
    return new;
  end if;
  if new.status = 'canceled' then
    new.canceled_by_team_id := old.opponent_team_id;
    return new;
  end if;
  raise exception 'invalid game status change';
end;
$$;

