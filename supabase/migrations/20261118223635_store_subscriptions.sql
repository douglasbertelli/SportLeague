-- Assinatura do Premium pelas lojas (App Store / Google Play) via Adapty, no
-- app Android/iOS. No site continua o Asaas (subscriptions).
--
-- Fluxo: o app identifica a pessoa no Adapty com o id dela (customer_user_id)
-- e compra pela loja. O Adapty avisa pelo webhook (`adapty-webhook`) e
-- `adapty_apply_event` guarda o estado aqui e acerta o plano.
--
-- O plano é Premium enquanto houver uma das duas assinaturas valendo: a da
-- loja (`private.store_active`) ou a do Asaas (`private.asaas_active`).
-- Vip (`elite`) é dado pelo painel e nunca muda por aqui.

create table public.store_subscriptions (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  adapty_profile_id text,
  -- app_store, play_store…
  store text,
  product_id text,
  -- O Adapty diz se a pessoa tem o acesso (access level) agora.
  active boolean not null default false,
  expires_at timestamptz,
  will_renew boolean,
  -- Sandbox (teste e revisão das lojas) ou Production.
  environment text,
  updated_at timestamptz not null default now()
);

alter table public.store_subscriptions enable row level security;

create policy "Administrador vê a própria assinatura da loja"
on public.store_subscriptions for select
to authenticated
using (profile_id = (select auth.uid()));

-- Eventos recebidos, para conferir depois (o Adapty pode repetir).
create table private.adapty_events (
  id bigint generated always as identity primary key,
  event_type text,
  customer_user_id text,
  payload jsonb not null,
  result text,
  received_at timestamptz not null default now()
);

revoke all on private.adapty_events from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Assinatura valendo
-- ---------------------------------------------------------------------------

create or replace function private.store_active(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.store_subscriptions s
    where s.profile_id = uid
      and s.active
      and (s.expires_at is null or s.expires_at > now())
  );
$$;

-- O contrário do que `asaas_expire` devolve ao Gratuito: pago e dentro do
-- período (com 5 dias de tolerância se a assinatura continua).
create or replace function private.asaas_active(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.profile_id = uid
      and (
        (s.status in ('active', 'overdue')
          and s.paid_until + 5 >= (now() at time zone 'America/Sao_Paulo')::date)
        or (s.status in ('canceled', 'pending')
          and s.paid_until > (now() at time zone 'America/Sao_Paulo')::date)
      )
  );
$$;

-- Acerta o plano pelas duas assinaturas. Vip não muda.
create or replace function private.sync_paid_plan(uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.store_active(uid) or private.asaas_active(uid) then
    update public.profiles set plan = 'premium'
    where id = uid and plan = 'free';
  else
    update public.profiles set plan = 'free'
    where id = uid and plan = 'premium';
  end if;
end;
$$;

-- O Asaas não devolve ao Gratuito quem tem a assinatura da loja valendo.
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
    )
    and not private.store_active(p.id);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Segurança se algum evento do Adapty se perder: quem tem a assinatura da
-- loja vencida e nada no Asaas volta ao Gratuito.
create or replace function private.store_expire()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  update public.profiles p set plan = 'free'
  from public.store_subscriptions s
  where s.profile_id = p.id
    and p.plan = 'premium'
    and not private.store_active(p.id)
    and not private.asaas_active(p.id);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Eventos do webhook
-- ---------------------------------------------------------------------------

-- Um evento do Adapty (webhook). Usa só o que todo evento traz:
-- customer_user_id (o id da pessoa aqui) e, em event_properties,
-- profile_has_access_level, subscription_expires_at, store,
-- vendor_product_id e environment.
create or replace function public.adapty_apply_event(p jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  ev text := p ->> 'event_type';
  props jsonb := coalesce(p -> 'event_properties', '{}'::jsonb);
  v_uid uuid;
  v_result text;
  v_event bigint;
begin
  insert into private.adapty_events (event_type, customer_user_id, payload)
  values (ev, p ->> 'customer_user_id', p)
  returning id into v_event;

  -- Só aceita o id de quem existe aqui (identify feito pelo app).
  begin
    v_uid := (p ->> 'customer_user_id')::uuid;
  exception when invalid_text_representation then
    v_uid := null;
  end;
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    update private.adapty_events set result = 'unknown_user' where id = v_event;
    return 'unknown_user';
  end if;

  if not (props ? 'profile_has_access_level') then
    update private.adapty_events set result = 'ignored' where id = v_event;
    return 'ignored';
  end if;

  insert into public.store_subscriptions as s (
    profile_id, adapty_profile_id, store, product_id, active, expires_at,
    will_renew, environment, updated_at
  ) values (
    v_uid,
    p ->> 'profile_id',
    props ->> 'store',
    props ->> 'vendor_product_id',
    (props ->> 'profile_has_access_level')::boolean,
    nullif(props ->> 'subscription_expires_at', '')::timestamptz,
    case ev
      when 'subscription_renewal_cancelled' then false
      when 'subscription_renewal_reactivated' then true
      when 'subscription_started' then true
      when 'subscription_renewed' then true
      when 'trial_started' then true
    end,
    props ->> 'environment',
    now()
  )
  on conflict (profile_id) do update set
    adapty_profile_id = coalesce(excluded.adapty_profile_id, s.adapty_profile_id),
    store = coalesce(excluded.store, s.store),
    product_id = coalesce(excluded.product_id, s.product_id),
    active = excluded.active,
    expires_at = coalesce(excluded.expires_at, s.expires_at),
    will_renew = coalesce(excluded.will_renew, s.will_renew),
    environment = coalesce(excluded.environment, s.environment),
    updated_at = now();

  perform private.sync_paid_plan(v_uid);

  v_result := case when private.store_active(v_uid) then 'active' else 'inactive' end;
  update private.adapty_events set result = v_result where id = v_event;
  return v_result;
end;
$$;

revoke execute on function private.store_active(uuid) from public, anon, authenticated;
revoke execute on function private.asaas_active(uuid) from public, anon, authenticated;
revoke execute on function private.sync_paid_plan(uuid) from public, anon, authenticated;
revoke execute on function private.store_expire() from public, anon, authenticated;
revoke execute on function public.adapty_apply_event(jsonb) from public, anon, authenticated;
grant execute on function public.adapty_apply_event(jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- plan_status: de onde vem a assinatura (para o app e o site saberem onde
-- ela é gerenciada)
-- ---------------------------------------------------------------------------

create or replace function public.plan_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'plan', private.effective_plan(p.id),
    'paid_plan', p.plan,
    'billing_source', case
      when p.plan <> 'premium' then null
      when private.store_active(p.id) then 'store'
      when private.asaas_active(p.id) then 'asaas'
    end,
    'trial_ends_at', (
      select t.ends_at from private.premium_trials t
      where t.profile_id = p.id and t.ends_at > now()
    ),
    'trial_available', (
      p.role = 'admin'
      and p.plan = 'free'
      and not exists (
        select 1 from private.premium_trials t where t.profile_id = p.id
      )
      and exists (
        select 1 from public.plans pl
        where pl.plan = 'premium' and pl.trial_days is not null
      )
    ),
    'quotas', coalesce((
      select jsonb_object_agg(f.feature, f.quota)
      from public.plan_features f
      where f.plan = private.effective_plan(p.id)
    ), '{}'::jsonb),
    'usage', jsonb_build_object(
      'teams', (
        select count(*) from public.teams t
        where t.owner_id = p.id and t.inactive_at is null
      ),
      'championships', (
        select count(*) from public.championships c
        where c.owner_id = p.id and c.status <> 'finished'
      )
    )
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

-- Todo dia às 6h10 de Brasília, depois do asaas-expire.
select cron.schedule(
  'store-expire',
  '10 9 * * *',
  $$select private.store_expire()$$
);
