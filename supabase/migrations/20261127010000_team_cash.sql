-- Dinheiro do time:
--
-- * Caixa (Premium, como a mensalidade): o dono lança entradas e saídas
--   (campo, árbitro, uniforme...). Mensalidades e vaquinhas pagas entram
--   sozinhas. Todos do time veem o saldo e a lista.
-- * Comprovante: o atleta paga pelo Pix (QR e copia-e-cola gerados no app
--   com a chave do time, direto para o time) e envia a foto do
--   comprovante; o dono confere e confirma (marca o pagamento) ou recusa.
--   Vale para a mensalidade e a vaquinha.

-- ---------------------------------------------------------------------------
-- Caixa
-- ---------------------------------------------------------------------------

create table public.team_cash_entries (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  kind text not null check (kind in ('in', 'out')),
  category text not null check (char_length(category) between 2 and 30),
  description text check (char_length(description) <= 120),
  amount_cents integer not null check (amount_cents between 1 and 100000000),
  happened_on date not null default ((now() at time zone 'America/Sao_Paulo')::date),
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create index team_cash_entries_team_idx on public.team_cash_entries (team_id, happened_on desc);
create index team_cash_entries_created_by_idx on public.team_cash_entries (created_by);

alter table public.team_cash_entries enable row level security;

create policy "Membros do time veem o caixa"
on public.team_cash_entries for select
to authenticated
using (private.is_team_member(team_id, (select auth.uid())));

-- O dono lança (com o Premium, como a mensalidade).
create policy "Dono lança no caixa"
on public.team_cash_entries for insert
to authenticated
with check (
  private.is_team_owner(team_id, (select auth.uid()))
  and private.has_feature((select auth.uid()), 'dues')
);

create policy "Dono corrige o caixa"
on public.team_cash_entries for update
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())))
with check (private.is_team_owner(team_id, (select auth.uid())));

create policy "Dono apaga do caixa"
on public.team_cash_entries for delete
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())));

-- Pessoas que dividem a vaquinha: os atletas do time e o dono (se não for
-- atleta), como no app.
create or replace function private.fundraiser_people(p_team uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select (select count(*) from public.team_players p where p.team_id = p_team)::int
       + case when exists (
           select 1 from public.team_players p join public.teams t on t.id = p.team_id
           where p.team_id = p_team and p.profile_id = t.owner_id
         ) then 0 else 1 end;
$$;

-- Parte de cada um na vaquinha (no total, arredonda o centavo para cima).
create or replace function private.fundraiser_share(f public.fundraisers, p_people integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when f.amount_type = 'total'
    then ceil(f.amount_cents::numeric / greatest(p_people, 1))::int
    else f.amount_cents end;
$$;

-- Caixa do time: saldo de tudo e os lançamentos (do mais novo ao mais
-- antigo): os do dono e, sozinhos, as mensalidades e vaquinhas pagas.
-- Sem o Premium do dono, só {locked: true}.
create or replace function public.team_cash(p_team uuid, p_limit integer default 300)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  v_owner uuid := private.team_owner(p_team);
  v_people integer := private.fundraiser_people(p_team);
  v_due integer := (select amount_cents from public.team_dues where team_id = p_team);
begin
  if not private.is_team_member(p_team, uid) then
    raise exception 'Você não é deste time.';
  end if;
  if not private.has_feature(v_owner, 'dues') then
    return jsonb_build_object('locked', true, 'can_manage', v_owner = uid);
  end if;
  return (
    with entries as (
      select e.id::text as id, e.happened_on as day, e.created_at as at, e.kind, e.category,
             e.description, e.amount_cents as amount, false as auto
      from public.team_cash_entries e where e.team_id = p_team
      union all
      select 'due-' || p.athlete_id || '-' || p.month, (p.paid_at at time zone 'America/Sao_Paulo')::date, p.paid_at,
             'in', 'Mensalidade',
             private.month_name(p.month) || ' · ' || coalesce(nullif(pr.nickname, ''), a.name),
             v_due, true
      from public.team_due_payments p
      join public.team_players a on a.id = p.athlete_id
      left join public.profiles pr on pr.id = a.profile_id
      where p.team_id = p_team and v_due is not null
      union all
      select 'fund-' || fp.id, (fp.paid_at at time zone 'America/Sao_Paulo')::date, fp.paid_at,
             'in', 'Vaquinha',
             case when f.item = 'other' then coalesce(f.description, 'Outros')
                  else (array['Bola', 'Colete', 'Uniforme', 'Churrasco'])[array_position(array['ball', 'bib', 'kit', 'barbecue'], f.item)] end
               || ' · ' || coalesce(nullif(pr.nickname, ''), a.name, pr.full_name, 'Alguém'),
             private.fundraiser_share(f, v_people), true
      from public.fundraiser_payments fp
      join public.fundraisers f on f.id = fp.fundraiser_id
      left join public.team_players a on a.id = fp.athlete_id
      left join public.profiles pr on pr.id = coalesce(a.profile_id, fp.profile_id)
      where f.team_id = p_team
    )
    select jsonb_build_object(
      'locked', false,
      'can_manage', v_owner = uid,
      'balance', coalesce(sum(case when kind = 'in' then amount else -amount end), 0),
      'total_in', coalesce(sum(amount) filter (where kind = 'in'), 0),
      'total_out', coalesce(sum(amount) filter (where kind = 'out'), 0),
      'entries', coalesce((
        select jsonb_agg(to_jsonb(x) order by x.day desc, x.at desc)
        from (select * from entries order by day desc, at desc limit greatest(1, least(p_limit, 1000))) x
      ), '[]'::jsonb)
    )
    from entries
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Comprovantes
-- ---------------------------------------------------------------------------

-- Fotos dos comprovantes (Storage, privado): <time>/<quem enviou>/<arquivo>.
-- Veem: quem enviou e o dono do time. Enviam: os membros do time, na pasta
-- deles.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-receipts', 'payment-receipts', false, 4194304,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "Quem enviou e o dono veem os comprovantes"
on storage.objects for select
to authenticated
using (
  bucket_id = 'payment-receipts'
  and (
    (storage.foldername(name))[2] = (select auth.uid())::text
    or exists (
      select 1 from public.teams t
      where t.id::text = (storage.foldername(name))[1] and t.owner_id = (select auth.uid())
    )
  )
);

create policy "Membros do time enviam comprovantes"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'payment-receipts'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1 from public.teams t
    where t.id::text = (storage.foldername(name))[1]
      and private.is_team_member(t.id, (select auth.uid()))
  )
);

create policy "Quem enviou e o dono apagam comprovantes"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'payment-receipts'
  and (
    (storage.foldername(name))[2] = (select auth.uid())::text
    or exists (
      select 1 from public.teams t
      where t.id::text = (storage.foldername(name))[1] and t.owner_id = (select auth.uid())
    )
  )
);

create table public.team_payment_receipts (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  kind text not null check (kind in ('dues', 'fundraiser')),
  month date check (month is null or extract(day from month) = 1),
  fundraiser_id uuid references public.fundraisers (id) on delete cascade,
  athlete_id uuid references public.team_players (id) on delete cascade,
  payer_id uuid not null references public.profiles (id) on delete cascade,
  image_path text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  note text check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  check ((kind = 'dues' and month is not null and athlete_id is not null)
      or (kind = 'fundraiser' and fundraiser_id is not null))
);

create index team_payment_receipts_team_idx on public.team_payment_receipts (team_id, status, created_at desc);
create index team_payment_receipts_payer_idx on public.team_payment_receipts (payer_id);
create index team_payment_receipts_fundraiser_idx on public.team_payment_receipts (fundraiser_id);
create index team_payment_receipts_athlete_idx on public.team_payment_receipts (athlete_id);

-- Só pelas funções.
alter table public.team_payment_receipts enable row level security;

-- Envia o comprovante (o atleta, ou o dono na vaquinha). Avisa o dono.
create or replace function public.submit_payment_receipt(
  p_team uuid,
  p_kind text,
  p_month date,
  p_fundraiser uuid,
  p_image_path text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  v_athlete uuid;
  v_id uuid;
  v_what text;
begin
  if not private.is_team_member(p_team, uid) then
    raise exception 'Você não é deste time.';
  end if;
  if p_image_path is null or split_part(p_image_path, '/', 1) <> p_team::text
     or split_part(p_image_path, '/', 2) <> uid::text then
    raise exception 'Comprovante inválido.';
  end if;
  select id into v_athlete from public.team_players
  where team_id = p_team and profile_id = uid and inactive_at is null limit 1;

  if p_kind = 'dues' then
    if v_athlete is null then
      raise exception 'Só atletas do time pagam a mensalidade.';
    end if;
    if not exists (select 1 from public.team_dues where team_id = p_team) then
      raise exception 'O time não tem mensalidade.';
    end if;
    if exists (select 1 from public.team_due_payments
               where athlete_id = v_athlete and month = date_trunc('month', p_month)::date) then
      raise exception 'Esta mensalidade já está paga.';
    end if;
    v_what := 'a mensalidade de ' || private.month_name(date_trunc('month', p_month)::date);
  elsif p_kind = 'fundraiser' then
    if not exists (select 1 from public.fundraisers
                   where id = p_fundraiser and team_id = p_team and not closed) then
      raise exception 'Esta vaquinha não está aberta.';
    end if;
    if exists (select 1 from public.fundraiser_payments
               where fundraiser_id = p_fundraiser
                 and (athlete_id = v_athlete or profile_id = uid)) then
      raise exception 'Você já pagou esta vaquinha.';
    end if;
    v_what := 'a vaquinha';
  else
    raise exception 'Tipo inválido.';
  end if;

  -- Um pendente por pagamento: o novo troca o antigo.
  delete from public.team_payment_receipts
  where payer_id = uid and status = 'pending' and kind = p_kind
    and (month is not distinct from date_trunc('month', p_month)::date or p_kind <> 'dues')
    and (fundraiser_id is not distinct from p_fundraiser or p_kind <> 'fundraiser');

  insert into public.team_payment_receipts (team_id, kind, month, fundraiser_id, athlete_id, payer_id, image_path)
  values (p_team, p_kind,
          case when p_kind = 'dues' then date_trunc('month', p_month)::date end,
          case when p_kind = 'fundraiser' then p_fundraiser end,
          v_athlete, uid, p_image_path)
  returning id into v_id;

  perform private.notify(
    private.team_owner(p_team), 'receipt', 'Comprovante para conferir',
    private.person_name(uid) || ' enviou o comprovante de ' || v_what || '.',
    p_team, null
  );
  return v_id;
end;
$$;

-- Comprovantes: o dono vê os do time; os outros, os seus.
create or replace function public.team_payment_receipts_list(p_team uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  owner boolean := private.is_team_owner(p_team, uid);
begin
  if not private.is_team_member(p_team, uid) then
    raise exception 'Você não é deste time.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'kind', r.kind,
      'month', r.month,
      'fundraiser_id', r.fundraiser_id,
      'fundraiser', case when f.id is null then null
        when f.item = 'other' then coalesce(f.description, 'Outros')
        else (array['Bola', 'Colete', 'Uniforme', 'Churrasco'])[array_position(array['ball', 'bib', 'kit', 'barbecue'], f.item)] end,
      'payer', private.person_name(r.payer_id),
      'mine', r.payer_id = uid,
      'image_path', r.image_path,
      'status', r.status,
      'note', r.note,
      'created_at', r.created_at
    ) order by (r.status = 'pending') desc, r.created_at desc)
    from public.team_payment_receipts r
    left join public.fundraisers f on f.id = r.fundraiser_id
    where r.team_id = p_team
      and (owner or r.payer_id = uid)
      and (r.status = 'pending' or r.created_at > now() - interval '60 days')
  ), '[]'::jsonb);
end;
$$;

-- Confere o comprovante (o dono): confirmado marca o pagamento; recusado
-- avisa quem enviou (com o motivo).
create or replace function public.answer_payment_receipt(p_receipt uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.team_payment_receipts;
begin
  select * into r from public.team_payment_receipts where id = p_receipt;
  if r.id is null or not private.is_team_owner(r.team_id, (select auth.uid())) then
    raise exception 'Só o dono do time confere os comprovantes.';
  end if;
  if r.status <> 'pending' then
    raise exception 'Este comprovante já foi conferido.';
  end if;
  if p_approve then
    if r.kind = 'dues' then
      insert into public.team_due_payments (team_id, athlete_id, month)
      values (r.team_id, r.athlete_id, r.month)
      on conflict do nothing;
    else
      if r.athlete_id is not null then
        insert into public.fundraiser_payments (fundraiser_id, athlete_id)
        values (r.fundraiser_id, r.athlete_id) on conflict do nothing;
      else
        insert into public.fundraiser_payments (fundraiser_id, profile_id)
        values (r.fundraiser_id, r.payer_id) on conflict do nothing;
      end if;
    end if;
  end if;
  update public.team_payment_receipts
     set status = case when p_approve then 'approved' else 'rejected' end,
         note = nullif(trim(coalesce(p_note, '')), ''),
         answered_at = now()
   where id = r.id;
  perform private.notify(
    r.payer_id, 'receipt_answer',
    case when p_approve then 'Pagamento confirmado' else 'Comprovante recusado' end,
    case when p_approve
      then 'O ' || private.team_name(r.team_id) || ' confirmou o seu pagamento.'
      else 'O ' || private.team_name(r.team_id) || ' recusou o comprovante'
        || coalesce(': ' || nullif(trim(coalesce(p_note, '')), ''), '.') end,
    r.team_id, null, null, true
  );
end;
$$;

revoke execute on function
  private.fundraiser_people(uuid),
  private.fundraiser_share(public.fundraisers, integer)
from public, anon, authenticated;

revoke execute on function
  public.team_cash(uuid, integer),
  public.submit_payment_receipt(uuid, text, date, uuid, text),
  public.team_payment_receipts_list(uuid),
  public.answer_payment_receipt(uuid, boolean, text)
from public, anon;
grant execute on function
  public.team_cash(uuid, integer),
  public.submit_payment_receipt(uuid, text, date, uuid, text),
  public.team_payment_receipts_list(uuid),
  public.answer_payment_receipt(uuid, boolean, text)
to authenticated;
