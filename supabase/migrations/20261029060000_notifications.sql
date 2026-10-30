-- Central de notificações (dentro do app). O banco cria as notificações nos
-- acontecimentos (gatilhos abaixo); cada usuário só vê, marca como lida e
-- apaga as dele. Quem fez a ação não é avisado da própria ação.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  team_id uuid references public.teams (id) on delete set null,
  game_id uuid references public.games (id) on delete set null,
  fundraiser_id uuid references public.fundraisers (id) on delete set null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_recipient on public.notifications (recipient_id, created_at desc);
create index notifications_team_id on public.notifications (team_id);
create index notifications_game_id on public.notifications (game_id);
create index notifications_fundraiser_id on public.notifications (fundraiser_id);

alter table public.notifications enable row level security;

create policy "Usuário vê as próprias notificações"
on public.notifications for select
to authenticated
using (recipient_id = (select auth.uid()));

create policy "Usuário marca as próprias notificações como lidas"
on public.notifications for update
to authenticated
using (recipient_id = (select auth.uid()))
with check (recipient_id = (select auth.uid()));

create policy "Usuário apaga as próprias notificações"
on public.notifications for delete
to authenticated
using (recipient_id = (select auth.uid()));

-- O app recebe as novas na hora (o número do sino).
alter publication supabase_realtime add table public.notifications;

-- ---------------------------------------------------------------------------
-- Ajudantes
-- ---------------------------------------------------------------------------

-- Cria a notificação, menos para quem fez a ação (ou sem destinatário).
create or replace function private.notify(
  p_recipient uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_team uuid default null,
  p_game uuid default null,
  p_fundraiser uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null
     or p_recipient is not distinct from (select auth.uid()) then
    return;
  end if;
  insert into public.notifications
    (recipient_id, kind, title, body, team_id, game_id, fundraiser_id)
  values
    (p_recipient, p_kind, p_title, p_body, p_team, p_game, p_fundraiser);
end;
$$;

create or replace function private.team_name(p_team uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select name from public.teams where id = p_team), 'Um time');
$$;

create or replace function private.team_owner(p_team uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select owner_id from public.teams where id = p_team;
$$;

-- Apelido do jogador (ou o nome).
create or replace function private.person_name(p_profile uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select coalesce(nickname, full_name) from public.profiles where id = p_profile),
    'Alguém'
  );
$$;

-- "07/11 às 15:00", no horário de Brasília.
create or replace function private.game_when(p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(p_at at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI');
$$;

-- ---------------------------------------------------------------------------
-- Convites e pedidos para entrar no time
-- ---------------------------------------------------------------------------

create or replace function private.notify_team_invite()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  team text := private.team_name(new.team_id);
  as_coach text := case when new.kind = 'coach' then ' como técnico' else '' end;
  answer text;
begin
  if tg_op = 'INSERT' then
    -- A entrada com código já nasce aceita: não avisa.
    if new.status <> 'pending' then
      return new;
    end if;
    if new.direction = 'invite' then
      perform private.notify(
        new.profile_id, 'invite', 'Convite de time',
        team || ' convidou você para entrar no time' || as_coach || '.',
        new.team_id
      );
    else
      perform private.notify(
        private.team_owner(new.team_id), 'request', 'Pedido para entrar',
        private.person_name(new.profile_id) || ' pediu para entrar no '
          || team || as_coach || '.',
        new.team_id
      );
    end if;
    return new;
  end if;

  if old.status <> 'pending' or new.status not in ('accepted', 'declined') then
    return new;
  end if;
  answer := case when new.status = 'accepted' then 'aceito' else 'recusado' end;
  if new.direction = 'request' then
    perform private.notify(
      new.profile_id, 'request_answer', 'Pedido ' || answer,
      'Seu pedido para entrar no ' || team || ' foi ' || answer || '.',
      new.team_id
    );
  else
    perform private.notify(
      private.team_owner(new.team_id), 'invite_answer', 'Convite ' || answer,
      private.person_name(new.profile_id)
        || case when new.status = 'accepted' then ' aceitou' else ' recusou' end
        || ' o convite para o ' || team || '.',
      new.team_id
    );
  end if;
  return new;
end;
$$;

create trigger team_invites_notify
after insert or update of status on public.team_invites
for each row execute function private.notify_team_invite();

-- ---------------------------------------------------------------------------
-- Amistosos (contra time da plataforma): convite, resposta, cancelamento,
-- data alterada e placar lançado. Avisa o dono do outro time.
-- ---------------------------------------------------------------------------

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
      host || ' quer marcar um amistoso em ' || private.game_when(new.scheduled_at) || '.',
      new.opponent_team_id, new.id
    );
    return new;
  end if;

  -- O adversário aceitou.
  if old.status = 'pending' and new.status = 'scheduled' then
    perform private.notify(
      host_owner, 'game_accepted', 'Amistoso aceito',
      rival || ' aceitou o amistoso de ' || private.game_when(new.scheduled_at) || '.',
      new.team_id, new.id
    );
  -- Recusado ou cancelado: avisa o outro lado, com o motivo.
  elsif old.status <> 'canceled' and new.status = 'canceled' then
    if new.canceled_by_team_id = new.opponent_team_id then
      if old.status = 'pending' then
        perform private.notify(
          host_owner, 'game_declined', 'Amistoso recusado',
          rival || ' recusou o amistoso de ' || private.game_when(new.scheduled_at) || '.',
          new.team_id, new.id
        );
      else
        perform private.notify(
          host_owner, 'game_canceled', 'Amistoso cancelado',
          rival || ' cancelou o amistoso de '
            || private.game_when(new.scheduled_at) || '.' || reason,
          new.team_id, new.id
        );
      end if;
    elsif new.canceled_by_team_id = new.team_id then
      perform private.notify(
        rival_owner, 'game_canceled', 'Amistoso cancelado',
        host || ' cancelou o amistoso de '
          || private.game_when(new.scheduled_at) || '.' || reason,
        new.opponent_team_id, new.id
      );
    end if;
  -- Quem marcou mudou a data.
  elsif new.scheduled_at is distinct from old.scheduled_at
        and new.status <> 'canceled' then
    perform private.notify(
      rival_owner, 'game_rescheduled', 'Amistoso remarcado',
      host || ' mudou o amistoso para ' || private.game_when(new.scheduled_at) || '.',
      new.opponent_team_id, new.id
    );
  end if;

  -- Placar de quem marcou, para o adversário. Não avisa gol a gol: só no fim
  -- de jogo do relógio, ou quando o placar é lançado (ou corrigido) depois
  -- do jogo.
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
      new.opponent_team_id, new.id
    );
  end if;
  return new;
end;
$$;

create trigger games_notify
after insert or update on public.games
for each row execute function private.notify_game();

-- ---------------------------------------------------------------------------
-- Contestação do placar e a resposta
-- ---------------------------------------------------------------------------

create or replace function private.notify_score_dispute()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  game public.games;
  contester text := private.team_name(new.team_id);
begin
  select * into game from public.games where id = new.game_id;
  if tg_op = 'INSERT' then
    perform private.notify(
      private.team_owner(game.team_id), 'dispute', 'Placar contestado',
      contester || ' contestou o placar do amistoso de '
        || private.game_when(game.scheduled_at) || ': ' || new.message,
      game.team_id, new.game_id
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
      new.team_id, new.game_id
    );
  end if;
  return new;
end;
$$;

create trigger score_disputes_notify
after insert or update of status on public.score_disputes
for each row execute function private.notify_score_dispute();

-- ---------------------------------------------------------------------------
-- Vaquinha: nova vaquinha (atletas com conta e técnicos) e pagamento marcado
-- (o próprio atleta)
-- ---------------------------------------------------------------------------

create or replace function private.notify_fundraiser()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  team text := private.team_name(new.team_id);
  item text := case new.item
    when 'ball' then 'Bola'
    when 'bib' then 'Colete'
    when 'kit' then 'Uniforme'
    when 'barbecue' then 'Churrasco'
    else coalesce(new.description, 'Outros')
  end;
  member uuid;
begin
  for member in
    select distinct p.profile_id from public.team_players p
    where p.team_id = new.team_id and p.profile_id is not null
    union
    select c.profile_id from public.team_coaches c where c.team_id = new.team_id
  loop
    perform private.notify(
      member, 'fundraiser', 'Nova vaquinha',
      'O ' || team || ' abriu a vaquinha ' || item || '.',
      new.team_id, null, new.id
    );
  end loop;
  return new;
end;
$$;

create trigger fundraisers_notify
after insert on public.fundraisers
for each row execute function private.notify_fundraiser();

create or replace function private.notify_fundraiser_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.fundraisers;
  player uuid;
begin
  if new.athlete_id is null then
    return new;
  end if;
  select * into f from public.fundraisers where id = new.fundraiser_id;
  select profile_id into player from public.team_players where id = new.athlete_id;
  perform private.notify(
    player, 'fundraiser_paid', 'Pagamento confirmado',
    'Seu pagamento na vaquinha ' || case f.item
      when 'ball' then 'Bola'
      when 'bib' then 'Colete'
      when 'kit' then 'Uniforme'
      when 'barbecue' then 'Churrasco'
      else coalesce(f.description, 'Outros')
    end || ' do ' || private.team_name(f.team_id) || ' foi confirmado.',
    f.team_id, null, f.id
  );
  return new;
end;
$$;

create trigger fundraiser_payments_notify
after insert on public.fundraiser_payments
for each row execute function private.notify_fundraiser_payment();

revoke execute on function private.notify(uuid, text, text, text, uuid, uuid, uuid) from public, anon;
revoke execute on function private.team_name(uuid) from public, anon;
revoke execute on function private.team_owner(uuid) from public, anon;
revoke execute on function private.person_name(uuid) from public, anon;
revoke execute on function private.game_when(timestamptz) from public, anon;
revoke execute on function private.notify_team_invite() from public, anon;
revoke execute on function private.notify_game() from public, anon;
revoke execute on function private.notify_score_dispute() from public, anon;
revoke execute on function private.notify_fundraiser() from public, anon;
revoke execute on function private.notify_fundraiser_payment() from public, anon;
