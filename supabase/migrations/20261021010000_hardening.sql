-- Ajustes apontados pelo Security/Performance Advisor do Supabase.

-- search_path fixo nas funções de trigger.
alter function public.set_updated_at() set search_path = '';
alter function public.protect_profile_fields() set search_path = '';

-- handle_new_user só deve rodar pelo trigger, nunca via /rest/v1/rpc.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Funções auxiliares das políticas RLS saem do schema exposto pela API.
-- As políticas continuam funcionando: referenciam as funções pelo OID.
create schema if not exists private;
grant usage on schema private to authenticated;

alter function public.is_admin(uuid) set schema private;
alter function public.is_team_owner(uuid, uuid) set schema private;

revoke execute on function private.is_admin(uuid) from public, anon;
revoke execute on function private.is_team_owner(uuid, uuid) from public, anon;
grant execute on function private.is_admin(uuid) to authenticated;
grant execute on function private.is_team_owner(uuid, uuid) to authenticated;

-- Índices para as FKs de convites (busca de "meus convites").
create index if not exists team_invites_profile_id_idx on public.team_invites (profile_id);
create index if not exists team_invites_created_by_idx on public.team_invites (created_by);
