-- Mural do time: avisos e enquetes.
--
-- * Quem publica: o dono e os técnicos do time. Atletas (com conta) leem,
--   reagem, comentam e votam.
-- * Aviso: texto, pode ficar fixado no topo; o dono e os técnicos veem quem
--   já leu.
-- * Enquete: opções, uma ou várias respostas, voto anônimo (só a contagem),
--   prazo para votar e lembrete para quem não votou (pelo botão ou sozinho,
--   duas horas antes do prazo).
-- * Tudo passa pelas funções abaixo (as tabelas não têm políticas de
--   escrita): elas conferem quem é do time e montam o mural de uma vez.

create table public.team_posts (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  author_id uuid references public.profiles (id) on delete set null,
  kind text not null check (kind in ('notice', 'poll')),
  body text not null check (char_length(body) between 1 and 2000),
  pinned boolean not null default false,
  multiple boolean not null default false,
  anonymous boolean not null default false,
  closes_at timestamptz,
  reminded_at timestamptz,
  created_at timestamptz not null default now(),
  check (kind = 'poll' or (not multiple and not anonymous and closes_at is null))
);

create index team_posts_team_idx on public.team_posts (team_id, created_at desc);
create index team_posts_author_idx on public.team_posts (author_id);

create table public.team_poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.team_posts (id) on delete cascade,
  label text not null check (char_length(label) between 1 and 120),
  position smallint not null,
  unique (post_id, position)
);

create table public.team_poll_votes (
  option_id uuid not null references public.team_poll_options (id) on delete cascade,
  post_id uuid not null references public.team_posts (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (option_id, profile_id)
);

create index team_poll_votes_post_idx on public.team_poll_votes (post_id, profile_id);
create index team_poll_votes_profile_idx on public.team_poll_votes (profile_id);

create table public.team_post_reads (
  post_id uuid not null references public.team_posts (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);

create index team_post_reads_profile_idx on public.team_post_reads (profile_id);

create table public.team_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.team_posts (id) on delete cascade,
  author_id uuid references public.profiles (id) on delete set null,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index team_post_comments_post_idx on public.team_post_comments (post_id, created_at);
create index team_post_comments_author_idx on public.team_post_comments (author_id);

create table public.team_post_reactions (
  post_id uuid not null references public.team_posts (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  emoji text not null check (emoji in ('👍', '❤️', '😂', '⚽')),
  primary key (post_id, profile_id, emoji)
);

create index team_post_reactions_profile_idx on public.team_post_reactions (profile_id);

-- Só pelas funções.
alter table public.team_posts enable row level security;
alter table public.team_poll_options enable row level security;
alter table public.team_poll_votes enable row level security;
alter table public.team_post_reads enable row level security;
alter table public.team_post_comments enable row level security;
alter table public.team_post_reactions enable row level security;

-- Time do aviso, conferindo que quem chama é do time (ou do staff).
create or replace function private.board_post_team(p_post uuid, p_staff boolean)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_team uuid;
begin
  select team_id into v_team from public.team_posts where id = p_post;
  if v_team is null then
    raise exception 'Aviso não encontrado.';
  end if;
  if p_staff then
    if not private.is_team_staff(v_team, (select auth.uid())) then
      raise exception 'Só o dono e os técnicos fazem isso.';
    end if;
  elsif not private.is_team_member(v_team, (select auth.uid())) then
    raise exception 'Você não é deste time.';
  end if;
  return v_team;
end;
$$;

-- Nome para mostrar: apelido, senão o nome do perfil.
create or replace function private.board_person(p_profile uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif(nickname, ''), full_name, 'Alguém')
  from public.profiles where id = p_profile;
$$;

-- O mural do time: {can_manage, posts}. Os avisos e enquetes vêm fixados
-- primeiro, depois do mais novo ao mais antigo, com votos, reações,
-- comentários e leituras; can_manage diz se quem vê publica (dono ou técnico).
create or replace function public.team_board(p_team uuid, p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  staff boolean;
begin
  if not private.is_team_member(p_team, uid) then
    raise exception 'Você não é deste time.';
  end if;
  staff := private.is_team_staff(p_team, uid);
  return jsonb_build_object('can_manage', staff, 'posts', coalesce((
    select jsonb_agg(item order by (item->>'pinned')::boolean desc, item->>'created_at' desc)
    from (
      select jsonb_build_object(
        'id', p.id,
        'kind', p.kind,
        'body', p.body,
        'pinned', p.pinned,
        'multiple', p.multiple,
        'anonymous', p.anonymous,
        'closes_at', p.closes_at,
        'closed', p.closes_at is not null and p.closes_at <= now(),
        'created_at', p.created_at,
        'author', jsonb_build_object('id', p.author_id, 'name', private.board_person(p.author_id)),
        'can_manage', staff,
        'read_by_me', exists (select 1 from public.team_post_reads r where r.post_id = p.id and r.profile_id = uid),
        'read_count', (select count(*) from public.team_post_reads r where r.post_id = p.id),
        'comments_count', (select count(*) from public.team_post_comments c where c.post_id = p.id),
        'voters_count', (select count(distinct v.profile_id) from public.team_poll_votes v where v.post_id = p.id),
        'options', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', o.id,
            'label', o.label,
            'votes', (select count(*) from public.team_poll_votes v where v.option_id = o.id),
            'mine', exists (select 1 from public.team_poll_votes v where v.option_id = o.id and v.profile_id = uid),
            'voters', case when p.anonymous then '[]'::jsonb else coalesce((
              select jsonb_agg(private.board_person(v.profile_id) order by v.created_at)
              from public.team_poll_votes v where v.option_id = o.id
            ), '[]'::jsonb) end
          ) order by o.position)
          from public.team_poll_options o where o.post_id = p.id
        ), '[]'::jsonb),
        'reactions', coalesce((
          select jsonb_agg(jsonb_build_object('emoji', x.emoji, 'count', x.n, 'mine', x.mine) order by x.emoji)
          from (
            select r.emoji, count(*) as n, bool_or(r.profile_id = uid) as mine
            from public.team_post_reactions r where r.post_id = p.id
            group by r.emoji
          ) x
        ), '[]'::jsonb)
      ) as item
      from public.team_posts p
      where p.team_id = p_team
      order by p.pinned desc, p.created_at desc
      limit greatest(1, least(p_limit, 200))
    ) posts
  ), '[]'::jsonb));
end;
$$;

-- Novo aviso ou enquete (dono ou técnico). Avisa o time.
create or replace function public.create_team_post(
  p_team uuid,
  p_kind text,
  p_body text,
  p_options text[] default null,
  p_multiple boolean default false,
  p_anonymous boolean default false,
  p_closes_at timestamptz default null,
  p_pinned boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  v_post uuid;
  v_options text[];
  i integer;
begin
  if not private.is_team_staff(p_team, uid) then
    raise exception 'Só o dono e os técnicos publicam no mural.';
  end if;
  if p_kind not in ('notice', 'poll') then
    raise exception 'Tipo inválido.';
  end if;
  if p_kind = 'poll' then
    select array_agg(trim(o)) into v_options
    from unnest(p_options) o where trim(o) <> '';
    if coalesce(array_length(v_options, 1), 0) < 2 then
      raise exception 'A enquete precisa de pelo menos duas opções.';
    end if;
    if array_length(v_options, 1) > 10 then
      raise exception 'A enquete tem no máximo dez opções.';
    end if;
    if p_closes_at is not null and p_closes_at <= now() then
      raise exception 'O prazo da enquete precisa ser no futuro.';
    end if;
  end if;

  if p_pinned then
    update public.team_posts set pinned = false where team_id = p_team and pinned;
  end if;
  insert into public.team_posts (team_id, author_id, kind, body, pinned, multiple, anonymous, closes_at)
  values (
    p_team, uid, p_kind, trim(p_body), p_pinned,
    p_kind = 'poll' and p_multiple,
    p_kind = 'poll' and p_anonymous,
    case when p_kind = 'poll' then p_closes_at end
  )
  returning id into v_post;

  if p_kind = 'poll' then
    for i in 1 .. array_length(v_options, 1) loop
      insert into public.team_poll_options (post_id, label, position)
      values (v_post, v_options[i], i);
    end loop;
  end if;

  -- Quem publicou já leu.
  insert into public.team_post_reads (post_id, profile_id) values (v_post, uid);

  perform private.notify_board(
    v_post,
    case when p_kind = 'poll' then 'Nova enquete' else 'Novo aviso' end,
    private.team_name(p_team) || ': ' || left(trim(p_body), 140),
    null
  );
  return v_post;
end;
$$;

-- Avisa as pessoas do time (dono, técnicos e atletas com conta), menos quem
-- fez a ação. Com [p_only_missing_votes], só quem ainda não votou.
create or replace function private.notify_board(
  p_post uuid,
  p_title text,
  p_body text,
  p_only_missing_votes boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid;
  person uuid;
begin
  select team_id into v_team from public.team_posts where id = p_post;
  for person in
    select private.team_people(v_team)
  loop
    if coalesce(p_only_missing_votes, false) and exists (
      select 1 from public.team_poll_votes v
      where v.post_id = p_post and v.profile_id = person
    ) then
      continue;
    end if;
    perform private.notify(person, 'board', p_title, p_body, v_team, null);
  end loop;
end;
$$;

-- Fixa (ou solta) um aviso no topo: só um fixado por time.
create or replace function public.set_team_post_pinned(p_post uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid := private.board_post_team(p_post, true);
begin
  if p_pinned then
    update public.team_posts set pinned = false where team_id = v_team and pinned and id <> p_post;
  end if;
  update public.team_posts set pinned = p_pinned where id = p_post;
end;
$$;

-- Apaga o aviso (dono ou técnico).
create or replace function public.delete_team_post(p_post uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.board_post_team(p_post, true);
  delete from public.team_posts where id = p_post;
end;
$$;

-- Marca avisos como lidos por quem chama (os que são de times dele).
create or replace function public.mark_team_posts_read(p_posts uuid[])
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.team_post_reads (post_id, profile_id)
  select p.id, (select auth.uid())
  from public.team_posts p
  where p.id = any (p_posts)
    and private.is_team_member(p.team_id, (select auth.uid()))
  on conflict do nothing;
$$;

-- Quem leu e quem ainda não leu (dono e técnicos).
create or replace function public.team_post_readers(p_post uuid)
returns table (profile_id uuid, name text, read_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select person, private.board_person(person), r.read_at
  from private.team_people(private.board_post_team(p_post, true)) as person
  left join public.team_post_reads r on r.post_id = p_post and r.profile_id = person
  where person is not null
  order by r.read_at nulls last, 2;
$$;

-- Vota (troca os votos de quem chama pelos de [p_options]). Vazio tira o
-- voto. Só com a enquete aberta.
create or replace function public.vote_team_poll(p_post uuid, p_options uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  p public.team_posts;
begin
  perform private.board_post_team(p_post, false);
  select * into p from public.team_posts where id = p_post;
  if p.kind <> 'poll' then
    raise exception 'Este aviso não é uma enquete.';
  end if;
  if p.closes_at is not null and p.closes_at <= now() then
    raise exception 'A enquete já fechou.';
  end if;
  if not p.multiple and coalesce(array_length(p_options, 1), 0) > 1 then
    raise exception 'Esta enquete aceita uma resposta só.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_options, '{}')) o
    where not exists (select 1 from public.team_poll_options x where x.id = o and x.post_id = p_post)
  ) then
    raise exception 'Opção inválida.';
  end if;
  delete from public.team_poll_votes where post_id = p_post and profile_id = uid;
  insert into public.team_poll_votes (option_id, post_id, profile_id)
  select distinct o, p_post, uid from unnest(coalesce(p_options, '{}')) o;
  -- Votar também é ler.
  insert into public.team_post_reads (post_id, profile_id) values (p_post, uid)
  on conflict do nothing;
end;
$$;

-- Lembra quem ainda não votou (dono e técnicos). Devolve quantos.
create or replace function public.remind_team_poll(p_post uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid := private.board_post_team(p_post, true);
  p public.team_posts;
  missing integer;
begin
  select * into p from public.team_posts where id = p_post;
  if p.kind <> 'poll' or (p.closes_at is not null and p.closes_at <= now()) then
    raise exception 'A enquete não está aberta.';
  end if;
  select count(*) into missing
  from private.team_people(v_team) as person
  where person is not null
    and person is distinct from (select auth.uid())
    and not exists (select 1 from public.team_poll_votes v where v.post_id = p_post and v.profile_id = person);
  perform private.notify_board(
    p_post, 'Falta o seu voto',
    private.team_name(v_team) || ': ' || left(p.body, 140), true
  );
  update public.team_posts set reminded_at = now() where id = p_post;
  return missing;
end;
$$;

-- Lembrete sozinho: enquetes que fecham nas próximas duas horas e ainda
-- não lembraram.
create or replace function private.remind_closing_polls()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.team_posts;
begin
  for p in
    select * from public.team_posts
    where kind = 'poll' and reminded_at is null
      and closes_at > now() and closes_at <= now() + interval '2 hours'
  loop
    perform private.notify_board(
      p.id, 'Enquete fechando',
      private.team_name(p.team_id) || ': ' || left(p.body, 140), true
    );
    update public.team_posts set reminded_at = now() where id = p.id;
  end loop;
end;
$$;

select cron.schedule('board-poll-reminders', '*/15 * * * *', 'select private.remind_closing_polls()');

-- Reação: liga ou desliga [p_emoji] de quem chama.
create or replace function public.toggle_team_post_reaction(p_post uuid, p_emoji text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  perform private.board_post_team(p_post, false);
  if exists (
    select 1 from public.team_post_reactions
    where post_id = p_post and profile_id = uid and emoji = p_emoji
  ) then
    delete from public.team_post_reactions
    where post_id = p_post and profile_id = uid and emoji = p_emoji;
  else
    insert into public.team_post_reactions (post_id, profile_id, emoji)
    values (p_post, uid, p_emoji);
  end if;
end;
$$;

-- Comentários do aviso, do mais antigo ao mais novo.
create or replace function public.team_post_comments(p_post uuid)
returns table (id uuid, body text, created_at timestamptz, author_name text, mine boolean, can_delete boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.body, c.created_at, private.board_person(c.author_id),
         c.author_id = (select auth.uid()),
         c.author_id = (select auth.uid())
           or private.is_team_staff(private.board_post_team(p_post, false), (select auth.uid()))
  from public.team_post_comments c
  where c.post_id = p_post
    and private.board_post_team(p_post, false) is not null
  order by c.created_at;
$$;

-- Comenta (quem é do time). Avisa quem publicou.
create or replace function public.add_team_post_comment(p_post uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid := private.board_post_team(p_post, false);
  v_id uuid;
  v_author uuid;
begin
  insert into public.team_post_comments (post_id, author_id, body)
  values (p_post, (select auth.uid()), trim(p_body))
  returning id into v_id;
  select author_id into v_author from public.team_posts where id = p_post;
  perform private.notify(
    v_author, 'board', 'Novo comentário',
    private.board_person((select auth.uid())) || ': ' || left(trim(p_body), 140),
    v_team, null
  );
  return v_id;
end;
$$;

-- Apaga o comentário (quem escreveu, o dono ou um técnico).
create or replace function public.delete_team_post_comment(p_comment uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.team_post_comments;
  v_team uuid;
begin
  select * into c from public.team_post_comments where id = p_comment;
  if c.id is null then
    return;
  end if;
  v_team := private.board_post_team(c.post_id, false);
  if c.author_id is distinct from (select auth.uid())
     and not private.is_team_staff(v_team, (select auth.uid())) then
    raise exception 'Só quem escreveu, o dono ou um técnico apaga.';
  end if;
  delete from public.team_post_comments where id = p_comment;
end;
$$;

revoke execute on function
  private.board_post_team(uuid, boolean),
  private.board_person(uuid),
  private.notify_board(uuid, text, text, boolean),
  private.remind_closing_polls()
from public, anon, authenticated;

revoke execute on function
  public.team_board(uuid, integer),
  public.create_team_post(uuid, text, text, text[], boolean, boolean, timestamptz, boolean),
  public.set_team_post_pinned(uuid, boolean),
  public.delete_team_post(uuid),
  public.mark_team_posts_read(uuid[]),
  public.team_post_readers(uuid),
  public.vote_team_poll(uuid, uuid[]),
  public.remind_team_poll(uuid),
  public.toggle_team_post_reaction(uuid, text),
  public.team_post_comments(uuid),
  public.add_team_post_comment(uuid, text),
  public.delete_team_post_comment(uuid)
from public, anon;

grant execute on function
  public.team_board(uuid, integer),
  public.create_team_post(uuid, text, text, text[], boolean, boolean, timestamptz, boolean),
  public.set_team_post_pinned(uuid, boolean),
  public.delete_team_post(uuid),
  public.mark_team_posts_read(uuid[]),
  public.team_post_readers(uuid),
  public.vote_team_poll(uuid, uuid[]),
  public.remind_team_poll(uuid),
  public.toggle_team_post_reaction(uuid, text),
  public.team_post_comments(uuid),
  public.add_team_post_comment(uuid, text),
  public.delete_team_post_comment(uuid)
to authenticated;
