-- Estorno ou chargeback de um pagamento da assinatura: o Premium sai na hora
-- (antes ficava até o fim do período pago). A assinatura é marcada como
-- cancelada, o período pago termina hoje, o plano é acertado pelas duas
-- assinaturas (quem também assina pelo app continua Premium) e a pessoa é
-- avisada. O `asaas-webhook` cancela a assinatura no Asaas quando o
-- resultado é `revoked`, para não cobrar de novo no mês seguinte.
--
-- Estorno parcial (PAYMENT_PARTIALLY_REFUNDED) não retira o Premium.

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
  v_today date := (now() at time zone 'America/Sao_Paulo')::date;
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
    elsif ev in ('PAYMENT_REFUNDED', 'PAYMENT_CHARGEBACK_REQUESTED') then
      -- Estorno: o Premium sai agora.
      update public.subscriptions
      set status = 'canceled',
        canceled_at = coalesce(canceled_at, now()),
        paid_until = least(coalesce(paid_until, v_today), v_today),
        updated_at = now()
      where profile_id = s.profile_id;
      perform private.sync_paid_plan(s.profile_id);
      perform private.notify(
        s.profile_id, 'plan', 'Assinatura do Premium encerrada',
        'O pagamento da assinatura do Premium foi estornado e a assinatura '
          || 'foi encerrada. Seus dados continuam salvos; para voltar ao '
          || 'Premium, é só assinar de novo.'
      );
      v_result := 'revoked';
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
          when ev in ('PAYMENT_REFUNDED', 'PAYMENT_CHARGEBACK_REQUESTED') then 'refunded'
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

revoke execute on function public.asaas_apply_event(jsonb) from public, anon, authenticated;
grant execute on function public.asaas_apply_event(jsonb) to service_role;
