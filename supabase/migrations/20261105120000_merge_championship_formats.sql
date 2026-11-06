-- Campeonatos é uma coisa só: quem pode organizar usa todos os formatos
-- (pontos corridos, mata-mata e grupos + mata-mata). Sai o recurso
-- separado `advanced_formats`.

delete from public.plan_features where feature = 'advanced_formats';

drop trigger championships_check_plan on public.championships;

create or replace function private.check_championship_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_feature(
    new.owner_id, 'championships',
    (
      select count(*)::int from public.championships
      where owner_id = new.owner_id and status <> 'finished'
    )
  );
  return new;
end;
$$;

create trigger championships_check_plan
before insert on public.championships
for each row execute function private.check_championship_plan();
