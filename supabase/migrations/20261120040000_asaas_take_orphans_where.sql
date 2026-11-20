-- `asaas_take_orphans` nunca funcionou pela API: o Supabase recusa DELETE sem
-- WHERE nas chamadas do PostgREST ("DELETE requires a WHERE clause"), e o
-- `asaas-sync` ignorava o erro. Com isso, as assinaturas de contas apagadas
-- nunca eram canceladas no Asaas. O `where true` deixa explícito que é para
-- apagar a fila toda.

create or replace function public.asaas_take_orphans()
returns setof text
language sql
security definer
set search_path = ''
as $$
  delete from private.asaas_orphans where true returning asaas_subscription_id;
$$;

revoke execute on function public.asaas_take_orphans() from public, anon, authenticated;
grant execute on function public.asaas_take_orphans() to service_role;
