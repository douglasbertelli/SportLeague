-- Inadimplente: 5 dias depois do vencimento sem pagar a conta volta ao
-- Gratuito (`asaas_expire`), mas a assinatura no Asaas continuava gerando
-- uma cobrança por mês. Com 30 dias sem pagar, o `asaas-sync` cancela a
-- assinatura no Asaas, marca aqui e avisa a pessoa (o aviso aparece também
-- no app, então não fala do site). Para voltar, ela assina de novo.

-- Assinaturas com o vencimento em aberto há mais de 30 dias.
create or replace function public.asaas_overdue_subscriptions()
returns table (profile_id uuid, asaas_subscription_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.profile_id, s.asaas_subscription_id
  from public.subscriptions s
  where s.status in ('active', 'overdue')
    and s.asaas_subscription_id is not null
    and s.paid_until < (now() at time zone 'America/Sao_Paulo')::date - 30;
$$;

-- Depois de cancelada no Asaas: marca e avisa. Só se nada mudou (um
-- pagamento que chegou no meio do caminho deixa a assinatura em dia). O
-- webhook SUBSCRIPTION_DELETED pode chegar antes e já ter marcado: aí só
-- avisa.
create or replace function public.asaas_cancel_overdue(p_profile uuid, p_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_late date := (now() at time zone 'America/Sao_Paulo')::date - 30;
begin
  update public.subscriptions
  set status = 'canceled', canceled_at = coalesce(canceled_at, now()),
    updated_at = now()
  where profile_id = p_profile
    and asaas_subscription_id = p_id
    and status in ('active', 'overdue')
    and paid_until < v_late;
  if found or exists (
    select 1 from public.subscriptions
    where profile_id = p_profile
      and asaas_subscription_id = p_id
      and status = 'canceled'
      and paid_until < v_late
      and canceled_at > now() - interval '10 minutes'
  ) then
    perform private.notify(
      p_profile, 'plan', 'Assinatura do Premium cancelada',
      'A mensalidade do Premium ficou 30 dias sem pagamento e a assinatura '
        || 'foi cancelada. Seus dados continuam salvos; para voltar ao '
        || 'Premium, é só assinar de novo.'
    );
  end if;
end;
$$;

revoke execute on function public.asaas_overdue_subscriptions() from public, anon, authenticated;
revoke execute on function public.asaas_cancel_overdue(uuid, text) from public, anon, authenticated;
grant execute on function public.asaas_overdue_subscriptions() to service_role;
grant execute on function public.asaas_cancel_overdue(uuid, text) to service_role;
