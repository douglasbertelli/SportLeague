-- Assinatura do Premium pelo Asaas (só no site; o app não vende nada).
--
-- Fluxo: o administrador informa o CPF/CNPJ no site, a Edge Function
-- `asaas-checkout` cria o cliente no Asaas e um checkout recorrente (cartão
-- ou Pix) e o site leva ao link. O Asaas avisa pelo webhook
-- (`asaas-webhook`) e `asaas_apply_event` atualiza a assinatura, o plano e
-- os pagamentos. Todo dia `asaas-sync` acerta o valor com os times ativos e
-- `asaas_expire` devolve ao Gratuito quem não pagou.
--
-- Atraso: o Premium continua até 5 dias depois do vencimento sem pagamento.
-- Cancelamento: continua até o fim do período já pago.

create table public.subscriptions (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  asaas_customer_id text not null,
  asaas_subscription_id text unique,
  -- pending: checkout criado, nada pago ainda.
  status text not null default 'pending'
    check (status in ('pending', 'active', 'overdue', 'canceled')),
  -- Valor que está no Asaas e quantos times ativos ele cobre.
  value_cents integer check (value_cents >= 0),
  teams smallint check (teams >= 0),
  -- Próximo vencimento do que já foi pago: o Premium vale até aqui (+ 5
  -- dias de tolerância se a assinatura continua).
  paid_until date,
  canceled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

create policy "Administrador vê a própria assinatura"
on public.subscriptions for select
to authenticated
using (profile_id = (select auth.uid()));

-- Pagamentos: ligação com a cobrança do Asaas, link da fatura e vencido.
alter table public.subscription_payments
  add column asaas_payment_id text unique,
  add column invoice_url text,
  add column due_date date;

alter table public.subscription_payments
  drop constraint subscription_payments_status_check,
  add constraint subscription_payments_status_check
    check (status in ('pending', 'overdue', 'paid', 'failed', 'refunded'));

-- Eventos recebidos (o Asaas pode mandar o mesmo mais de uma vez).
create table private.asaas_events (
  id text primary key,
  event text not null,
  payload jsonb not null,
  result text,
  received_at timestamptz not null default now()
);

revoke all on private.asaas_events from public, anon, authenticated;

-- Assinaturas de contas apagadas: a Edge Function cancela no Asaas.
create table private.asaas_orphans (
  asaas_subscription_id text primary key,
  created_at timestamptz not null default now()
);

revoke all on private.asaas_orphans from public, anon, authenticated;

create or replace function private.keep_asaas_orphan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.asaas_subscription_id is not null and old.status <> 'canceled' then
    insert into private.asaas_orphans (asaas_subscription_id)
    values (old.asaas_subscription_id)
    on conflict do nothing;
  end if;
  return old;
end;
$$;

create trigger subscriptions_keep_orphan
after delete on public.subscriptions
for each row execute function private.keep_asaas_orphan();

-- ---------------------------------------------------------------------------
-- Valor
-- ---------------------------------------------------------------------------

-- Mensalidade do Premium com os times ativos da pessoa (o primeiro já está
-- no valor base).
create or replace function public.asaas_desired_value(uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'teams', n.teams,
    'value_cents', pl.monthly_cents + pl.extra_team_cents * greatest(0, n.teams - 1)
  )
  from public.plans pl,
    lateral (
      select count(*)::int as teams from public.teams t
      where t.owner_id = uid and t.inactive_at is null
    ) n
  where pl.plan = 'premium';
$$;

-- Assinaturas cujo valor no Asaas ficou diferente dos times ativos.
create or replace function public.asaas_value_changes()
returns table (
  profile_id uuid,
  asaas_subscription_id text,
  teams integer,
  value_cents integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.profile_id, s.asaas_subscription_id,
    (d.v ->> 'teams')::int, (d.v ->> 'value_cents')::int
  from public.subscriptions s,
    lateral (select public.asaas_desired_value(s.profile_id) as v) d
  where s.status in ('active', 'overdue')
    and s.asaas_subscription_id is not null
    and s.value_cents is distinct from (d.v ->> 'value_cents')::int;
$$;

create or replace function public.asaas_set_value(
  p_profile uuid, p_teams integer, p_value_cents integer
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.subscriptions
  set teams = p_teams, value_cents = p_value_cents, updated_at = now()
  where profile_id = p_profile;
$$;

-- ---------------------------------------------------------------------------
-- Eventos do webhook
-- ---------------------------------------------------------------------------

create or replace function public.asaas_apply_event(p jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  ev text := p ->> 'event';
  pay jsonb := p -> 'payment';
  sub jsonb := p -> 'subscription';
  s public.subscriptions;
  v_due date;
  v_method text;
  v_result text;
  v_old boolean := false;
begin
  if p ->> 'id' is null or ev is null then
    return 'invalid';
  end if;
  insert into private.asaas_events (id, event, payload)
  values (p ->> 'id', ev, p)
  on conflict (id) do nothing;
  if not found then
    return 'duplicate';
  end if;

  -- De quem é: pela assinatura do Asaas ou pelo cliente que criamos.
  select * into s from public.subscriptions x
  where x.asaas_subscription_id = coalesce(pay ->> 'subscription', sub ->> 'id')
     or x.asaas_customer_id = coalesce(pay ->> 'customer', sub ->> 'customer')
  order by (x.asaas_subscription_id = coalesce(pay ->> 'subscription', sub ->> 'id')) desc nulls last
  limit 1;

  if s.profile_id is null then
    v_result := 'unknown_customer';
  elsif pay is not null and pay ->> 'subscription' is null then
    -- Cobrança avulsa (não é da assinatura): não mexe no plano.
    v_result := 'not_subscription';
  elsif pay is not null then
    v_due := (pay ->> 'dueDate')::date;
    v_method := case pay ->> 'billingType'
      when 'CREDIT_CARD' then 'Cartão'
      when 'PIX' then 'Pix'
      when 'BOLETO' then 'Boleto'
      else null end;

    -- A assinatura nova (do checkout) passa a ser a da pessoa, se ela não
    -- tem outra valendo. Eventos atrasados de uma assinatura antiga só
    -- atualizam a lista de pagamentos.
    if s.asaas_subscription_id is distinct from pay ->> 'subscription' then
      if (s.asaas_subscription_id is null or s.status in ('pending', 'canceled'))
        and ev in ('PAYMENT_CREATED', 'PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED') then
        update public.subscriptions
        set asaas_subscription_id = pay ->> 'subscription', status = 'pending',
          canceled_at = null, updated_at = now()
        where profile_id = s.profile_id;
      else
        v_old := true;
      end if;
    end if;

    if v_old then
      v_result := 'old_subscription';
    elsif ev in ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED') then
      update public.subscriptions
      set status = 'active',
        canceled_at = null,
        value_cents = coalesce(value_cents, round((pay ->> 'value')::numeric * 100)::int),
        paid_until = greatest(coalesce(paid_until, v_due), (v_due + interval '1 month')::date),
        updated_at = now()
      where profile_id = s.profile_id;
      -- Elite é dado pelo painel: não troca.
      update public.profiles set plan = 'premium'
      where id = s.profile_id and plan = 'free';
      v_result := 'paid';
    elsif ev = 'PAYMENT_OVERDUE' then
      update public.subscriptions set status = 'overdue', updated_at = now()
      where profile_id = s.profile_id and status = 'active';
      v_result := 'overdue';
    else
      v_result := 'payment';
    end if;

    if ev = 'PAYMENT_DELETED' then
      delete from public.subscription_payments
      where asaas_payment_id = pay ->> 'id' and status <> 'paid';
    elsif ev like 'PAYMENT_%' then
      insert into public.subscription_payments as sp (
        profile_id, plan, amount_cents, teams, period_start, period_end,
        status, method, paid_at, asaas_payment_id, invoice_url, due_date
      ) values (
        s.profile_id, 'premium',
        round((pay ->> 'value')::numeric * 100)::int,
        coalesce(s.teams, 1),
        v_due, ((v_due + interval '1 month')::date - 1),
        case
          when ev in ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED') then 'paid'
          when ev in ('PAYMENT_REFUNDED') then 'refunded'
          when ev = 'PAYMENT_OVERDUE' then 'overdue'
          when ev = 'PAYMENT_CREDIT_CARD_CAPTURE_REFUSED' then 'failed'
          else 'pending' end,
        v_method,
        case when ev in ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED') then now() end,
        pay ->> 'id', pay ->> 'invoiceUrl', v_due
      )
      on conflict (asaas_payment_id) do update set
        amount_cents = excluded.amount_cents,
        method = coalesce(excluded.method, sp.method),
        invoice_url = coalesce(excluded.invoice_url, sp.invoice_url),
        due_date = excluded.due_date,
        period_start = excluded.period_start,
        period_end = excluded.period_end,
        -- Pago só muda com estorno; as outras mudam com o evento.
        status = case
          when sp.status = 'paid' and excluded.status <> 'refunded' then 'paid'
          when ev in ('PAYMENT_UPDATED', 'PAYMENT_CREATED', 'PAYMENT_RESTORED')
            and sp.status <> 'pending' then sp.status
          else excluded.status end,
        paid_at = coalesce(sp.paid_at, excluded.paid_at);
    end if;
  elsif ev in ('SUBSCRIPTION_DELETED', 'SUBSCRIPTION_INACTIVATED') then
    update public.subscriptions
    set status = 'canceled', canceled_at = coalesce(canceled_at, now()),
      updated_at = now()
    where profile_id = s.profile_id
      and asaas_subscription_id = sub ->> 'id';
    v_result := 'canceled';
  elsif sub is not null then
    if s.asaas_subscription_id = sub ->> 'id' then
      update public.subscriptions
      set value_cents = round((sub ->> 'value')::numeric * 100)::int,
        updated_at = now()
      where profile_id = s.profile_id;
    end if;
    v_result := 'subscription';
  else
    v_result := 'ignored';
  end if;

  update private.asaas_events set result = v_result
  where id = p ->> 'id';
  return v_result;
end;
$$;

-- Cancelado pelo site: a Edge Function apaga no Asaas e marca aqui.
create or replace function public.asaas_mark_canceled(p_profile uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.subscriptions
  set status = 'canceled', canceled_at = coalesce(canceled_at, now()),
    updated_at = now()
  where profile_id = p_profile;
$$;

-- Volta ao Gratuito quem cancelou e passou do período pago, ou quem está
-- 5 dias depois do vencimento sem pagar. Elite não muda.
create or replace function private.asaas_expire()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  today date := (now() at time zone 'America/Sao_Paulo')::date;
  n integer;
begin
  update public.profiles p set plan = 'free'
  from public.subscriptions s
  where s.profile_id = p.id
    and p.plan = 'premium'
    and (
      (s.status in ('canceled', 'pending') and coalesce(s.paid_until, today) <= today)
      or (s.status in ('active', 'overdue') and s.paid_until + 5 < today)
    );
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.asaas_desired_value(uuid) from public, anon, authenticated;
revoke execute on function public.asaas_value_changes() from public, anon, authenticated;
revoke execute on function public.asaas_set_value(uuid, integer, integer) from public, anon, authenticated;
revoke execute on function public.asaas_apply_event(jsonb) from public, anon, authenticated;
revoke execute on function public.asaas_mark_canceled(uuid) from public, anon, authenticated;
revoke execute on function private.asaas_expire() from public, anon, authenticated;
grant execute on function public.asaas_desired_value(uuid) to service_role;
grant execute on function public.asaas_value_changes() to service_role;
grant execute on function public.asaas_set_value(uuid, integer, integer) to service_role;
grant execute on function public.asaas_apply_event(jsonb) to service_role;
grant execute on function public.asaas_mark_canceled(uuid) to service_role;

-- Os órfãos são lidos e apagados pela Edge Function (service role).
create or replace function public.asaas_take_orphans()
returns setof text
language sql
security definer
set search_path = ''
as $$
  delete from private.asaas_orphans returning asaas_subscription_id;
$$;

create or replace function public.asaas_put_orphan(p_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.asaas_orphans (asaas_subscription_id) values (p_id)
  on conflict do nothing;
$$;

revoke execute on function public.asaas_take_orphans() from public, anon, authenticated;
revoke execute on function public.asaas_put_orphan(text) from public, anon, authenticated;
grant execute on function public.asaas_take_orphans() to service_role;
grant execute on function public.asaas_put_orphan(text) to service_role;

-- Todo dia às 6h de Brasília (9h UTC): expira e acerta os valores.
select cron.schedule(
  'asaas-expire',
  '0 9 * * *',
  $$select private.asaas_expire()$$
);

select cron.schedule(
  'asaas-sync',
  '5 9 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name = 'project_url') || '/functions/v1/asaas-sync',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json')
  )
  $$
);
