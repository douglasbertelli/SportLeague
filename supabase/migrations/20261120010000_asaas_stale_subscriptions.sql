-- Assinaturas do Asaas que nunca foram pagas (Pix escolhido e não pago, ou a
-- volta de quem cancelou e não pagou). Sem isso, o Asaas continua gerando uma
-- cobrança por mês e mandando por e-mail para sempre. O `asaas-sync` apaga
-- essas assinaturas no Asaas e depois solta o id aqui.
--
-- Parada: sem mexer há 7 dias e o primeiro vencimento (hoje, no checkout, ou
-- o fim do período já pago, para quem tinha cancelado) passou há 7 dias.

create or replace function public.asaas_stale_subscriptions()
returns table (profile_id uuid, asaas_subscription_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.profile_id, s.asaas_subscription_id
  from public.subscriptions s
  where s.status in ('pending', 'canceled')
    and s.asaas_subscription_id is not null
    and s.updated_at < now() - interval '7 days'
    and coalesce(s.paid_until, s.updated_at::date)
      < (now() at time zone 'America/Sao_Paulo')::date - 7;
$$;

-- Depois de apagada no Asaas. Só solta se nada mudou (um pagamento que
-- chegou no meio do caminho deixa a assinatura ativa).
create or replace function public.asaas_clear_subscription(
  p_profile uuid, p_id text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.subscriptions
  set asaas_subscription_id = null, updated_at = now()
  where profile_id = p_profile
    and asaas_subscription_id = p_id
    and status in ('pending', 'canceled');
$$;

revoke execute on function public.asaas_stale_subscriptions() from public, anon, authenticated;
revoke execute on function public.asaas_clear_subscription(uuid, text) from public, anon, authenticated;
grant execute on function public.asaas_stale_subscriptions() to service_role;
grant execute on function public.asaas_clear_subscription(uuid, text) to service_role;
