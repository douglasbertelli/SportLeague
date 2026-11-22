-- Assinaturas da loja: `active` vinha de `profile_has_access_level`, que o
-- Adapty manda `true` em todos os eventos, até em `subscription_expired`. O
-- Premium só caía porque `expires_at` já tinha passado; num reembolso no meio
-- do período (vencimento no futuro) a conta continuaria Premium.
--
-- Agora:
-- - `access_level_updated` manda: usa o `is_active` dele (falso no
--   vencimento e no reembolso) e o `will_renew`;
-- - `subscription_expired` e `subscription_refunded` desligam;
-- - início, renovação e reativação ligam;
-- - os demais (ex.: `subscription_renewal_cancelled`, que chega junto com o
--   vencimento) não mexem em `active`.

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
  v_active boolean;
  v_will_renew boolean;
begin
  insert into private.adapty_events (event_type, customer_user_id, payload)
  values (ev, p ->> 'customer_user_id', p)
  returning id into v_event;

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

  v_active := case
    when ev = 'access_level_updated' and props ? 'is_active'
      then (props ->> 'is_active')::boolean
    when ev in ('subscription_expired', 'subscription_refunded')
      then false
    when ev in (
      'subscription_started', 'subscription_renewed',
      'subscription_renewal_reactivated', 'trial_started', 'trial_converted'
    ) then true
  end;

  v_will_renew := case
    when ev = 'access_level_updated' and props ? 'will_renew'
      then (props ->> 'will_renew')::boolean
    when ev in ('subscription_renewal_cancelled', 'subscription_expired',
                'subscription_refunded') then false
    when ev in ('subscription_renewal_reactivated', 'subscription_started',
                'subscription_renewed', 'trial_started', 'trial_converted') then true
  end;

  insert into public.store_subscriptions as s (
    profile_id, adapty_profile_id, store, product_id, active, expires_at,
    will_renew, environment, updated_at
  ) values (
    v_uid,
    p ->> 'profile_id',
    props ->> 'store',
    props ->> 'vendor_product_id',
    coalesce(v_active, (props ->> 'profile_has_access_level')::boolean),
    nullif(props ->> 'subscription_expires_at', '')::timestamptz,
    v_will_renew,
    props ->> 'environment',
    now()
  )
  on conflict (profile_id) do update set
    adapty_profile_id = coalesce(excluded.adapty_profile_id, s.adapty_profile_id),
    store = coalesce(excluded.store, s.store),
    product_id = coalesce(excluded.product_id, s.product_id),
    active = coalesce(v_active, s.active),
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

-- Assinaturas já vencidas que ficaram marcadas como ativas.
update public.store_subscriptions
set active = false, updated_at = now()
where active and expires_at is not null and expires_at <= now();
