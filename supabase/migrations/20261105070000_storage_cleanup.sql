-- Limpeza das imagens órfãs no Storage. O app já apaga a imagem ao trocar
-- (mesmo caminho, sobrescrito), ao remover e ao excluir time, atleta e
-- local; sobram arquivos quando apagar falha (rede) ou quando o banco exclui
-- em cascata sem passar pelo app (conta excluída leva times, atletas e
-- fictícios). Todo dia às 4h de Brasília, a Edge Function `storage-cleanup`
-- pede a lista abaixo e apaga os arquivos pela API do Storage (apagar só a
-- linha de storage.objects deixaria o arquivo no disco).

-- Arquivos que nenhuma tabela usa, criados há mais de [p_min_age] (a imagem
-- recém-enviada ainda pode estar sendo gravada no cadastro).
create or replace function public.storage_orphans(
  p_min_age interval default interval '1 day'
)
returns table (bucket_id text, name text)
language sql
stable
security definer
set search_path = ''
as $$
  with used as (
    select 'team-logos' as bucket,
           split_part(split_part(url, '/team-logos/', 2), '?', 1) as path
    from (
      select logo_url as url from public.teams
      union all select cover_url from public.teams
      union all select unnest(kit_urls) from public.teams
      union all select logo_url from public.guest_teams
    ) u
    where url like '%/team-logos/%'
    union all
    select 'profile-photos',
           split_part(split_part(url, '/profile-photos/', 2), '?', 1)
    from (
      select avatar_url as url from public.profiles
      union all select cover_url from public.profiles
    ) p
    where url like '%/profile-photos/%'
    union all
    select 'venue-photos',
           split_part(split_part(photo_url, '/venue-photos/', 2), '?', 1)
    from public.venues
    where photo_url like '%/venue-photos/%'
    union all
    select 'athlete-photos', photo_path
    from public.team_players
    where photo_path is not null
  )
  select o.bucket_id, o.name
  from storage.objects o
  where o.bucket_id in ('team-logos', 'profile-photos', 'venue-photos', 'athlete-photos')
    and coalesce(o.updated_at, o.created_at) < now() - p_min_age
    and not exists (
      select 1 from used u where u.bucket = o.bucket_id and u.path = o.name
    );
$$;

-- Só o backend (a Edge Function, com a service role) consulta.
revoke execute on function public.storage_orphans(interval)
  from public, anon, authenticated;
grant execute on function public.storage_orphans(interval) to service_role;

-- Todo dia às 4h de Brasília (7h UTC). A função só apaga órfãos antigos,
-- então chamá-la de novo não faz mal.
select cron.schedule(
  'storage-cleanup',
  '0 7 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name = 'project_url') || '/functions/v1/storage-cleanup',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json')
  )
  $$
);
