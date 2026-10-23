-- O calendário que vale para marcar o amistoso é o de quem joga em casa:
-- como mandante, o do próprio time; como visitante, o do adversário da
-- plataforma (contra time fictício, que não tem calendário, o do próprio
-- time). Antes valia sempre o do adversário. Agora a regra também é
-- conferida quando quem marcou troca o mando.

create or replace function public.check_game_slot()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  calendar_team uuid;
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.scheduled_at is not distinct from old.scheduled_at
     and new.host_is_home is not distinct from old.host_is_home
     and (new.opponent_team_id is null
          or new.opponent_team_id is not distinct from old.opponent_team_id)
     and (new.opponent_guest_id is null
          or new.opponent_guest_id is not distinct from old.opponent_guest_id) then
    return new;
  end if;

  calendar_team := case
    when new.host_is_home then new.team_id
    else coalesce(new.opponent_team_id, new.team_id)
  end;
  if not private.team_offers_slot(calendar_team, new.scheduled_at) then
    raise exception 'time slot not available in the calendar';
  end if;
  if private.team_slot_taken(calendar_team, new.scheduled_at, new.id) then
    raise exception 'time slot already taken';
  end if;
  return new;
end;
$$;
