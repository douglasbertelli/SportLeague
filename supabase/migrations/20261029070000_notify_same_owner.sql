-- Amistoso entre dois times do mesmo administrador: quem marca e quem recebe
-- são a mesma pessoa, e a regra "quem fez a ação não é avisado" escondia a
-- notificação do outro time. Nos amistosos (e na contestação), o outro time
-- é avisado mesmo sendo do mesmo administrador.

create or replace function private.notify(
  p_recipient uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_team uuid default null,
  p_game uuid default null,
  p_fundraiser uuid default null,
  p_even_self boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null
     or (not p_even_self
         and p_recipient is not distinct from (select auth.uid())) then
    return;
  end if;
  insert into public.notifications
    (recipient_id, kind, title, body, team_id, game_id, fundraiser_id)
  values
    (p_recipient, p_kind, p_title, p_body, p_team, p_game, p_fundraiser);
end;
$$;

-- A versão antiga (sem p_even_self) sai; as chamadas sem o parâmetro usam o
-- padrão da nova.
drop function private.notify(uuid, text, text, text, uuid, uuid, uuid);

create or replace function private.notify_game()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  host text := private.team_name(new.team_id);
  rival text := private.team_name(new.opponent_team_id);
  host_owner uuid := private.team_owner(new.team_id);
  rival_owner uuid := private.team_owner(new.opponent_team_id);
  -- Os dois times são do mesmo administrador: avisa o outro time mesmo assim.
  same_owner boolean := private.team_owner(new.team_id)
    = private.team_owner(new.opponent_team_id);
  reason text := case
    when new.cancel_reason is null then ''
    else ' Motivo: ' || new.cancel_reason
  end;
begin
  if new.opponent_team_id is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    perform private.notify(
      rival_owner, 'game_invite', 'Convite de amistoso',
      host || ' quer marcar um amistoso com o ' || rival || ' em '
        || private.game_when(new.scheduled_at) || '.',
      new.opponent_team_id, new.id, null, same_owner
    );
    return new;
  end if;

  if old.status = 'pending' and new.status = 'scheduled' then
    perform private.notify(
      host_owner, 'game_accepted', 'Amistoso aceito',
      rival || ' aceitou o amistoso de ' || private.game_when(new.scheduled_at) || '.',
      new.team_id, new.id, null, same_owner
    );
  elsif old.status <> 'canceled' and new.status = 'canceled' then
    if new.canceled_by_team_id = new.opponent_team_id then
      if old.status = 'pending' then
        perform private.notify(
          host_owner, 'game_declined', 'Amistoso recusado',
          rival || ' recusou o amistoso de ' || private.game_when(new.scheduled_at) || '.',
          new.team_id, new.id, null, same_owner
        );
      else
        perform private.notify(
          host_owner, 'game_canceled', 'Amistoso cancelado',
          rival || ' cancelou o amistoso de '
            || private.game_when(new.scheduled_at) || '.' || reason,
          new.team_id, new.id, null, same_owner
        );
      end if;
    elsif new.canceled_by_team_id = new.team_id then
      perform private.notify(
        rival_owner, 'game_canceled', 'Amistoso cancelado',
        host || ' cancelou o amistoso de '
          || private.game_when(new.scheduled_at) || '.' || reason,
        new.opponent_team_id, new.id, null, same_owner
      );
    end if;
  elsif new.scheduled_at is distinct from old.scheduled_at
        and new.status <> 'canceled' then
    perform private.notify(
      rival_owner, 'game_rescheduled', 'Amistoso remarcado',
      host || ' mudou o amistoso para ' || private.game_when(new.scheduled_at) || '.',
      new.opponent_team_id, new.id, null, same_owner
    );
  end if;

  if new.team_score is not null and new.opponent_score is not null
     and (
       (new.match_phase = 'finished'
        and old.match_phase is distinct from 'finished')
       or (
         (new.team_score is distinct from old.team_score
          or new.opponent_score is distinct from old.opponent_score)
         and (new.match_phase = 'finished'
              or (new.match_phase is null
                  and now() >= new.scheduled_at + interval '2 hours'))
       )
     ) then
    perform private.notify(
      rival_owner, 'game_score', 'Placar lançado',
      host || ' lançou o placar: ' || rival || ' ' || new.opponent_score
        || ' × ' || new.team_score || ' ' || host || '.',
      new.opponent_team_id, new.id, null, same_owner
    );
  end if;
  return new;
end;
$$;

create or replace function private.notify_score_dispute()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  game public.games;
  contester text := private.team_name(new.team_id);
  same_owner boolean;
begin
  select * into game from public.games where id = new.game_id;
  same_owner := private.team_owner(game.team_id) = private.team_owner(new.team_id);
  if tg_op = 'INSERT' then
    perform private.notify(
      private.team_owner(game.team_id), 'dispute', 'Placar contestado',
      contester || ' contestou o placar do amistoso de '
        || private.game_when(game.scheduled_at) || ': ' || new.message,
      game.team_id, new.game_id, null, same_owner
    );
    return new;
  end if;
  if old.status = 'open' and new.status in ('accepted', 'rejected') then
    perform private.notify(
      private.team_owner(new.team_id), 'dispute_answer',
      case when new.status = 'accepted' then 'Contestação aceita'
           else 'Contestação recusada' end,
      private.team_name(game.team_id)
        || case when new.status = 'accepted'
                then ' aceitou a sua contestação e corrigiu o placar.'
                else ' manteve o placar do amistoso de '
                     || private.game_when(game.scheduled_at) || '.' end,
      new.team_id, new.game_id, null, same_owner
    );
  end if;
  return new;
end;
$$;

revoke execute on function private.notify(uuid, text, text, text, uuid, uuid, uuid, boolean) from public, anon;
