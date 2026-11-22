-- Denúncias de conteúdo (política de conteúdo gerado por usuários do Google
-- Play e da App Store): qualquer pessoa logada denuncia um time, um local ou
-- um atleta pelo app. A denúncia guarda uma cópia do conteúdo no momento
-- (snapshot), para a análise continuar possível se ele mudar ou sumir.
--
-- Fica no schema private: só o service_role (painel do Supabase) lê. O app
-- grava pela função public.report_content.
--
-- Para analisar:
--   select * from private.content_reports where status = 'open' order by created_at;
-- Depois de agir, marque status = 'removed' (conteúdo removido) ou
-- 'dismissed' (sem problema) e reviewed_at = now().

create table private.content_reports (
  id bigint generated always as identity primary key,
  reporter_id uuid references auth.users (id) on delete set null,
  target_type text not null check (target_type in ('team', 'venue', 'athlete')),
  target_id uuid not null,
  reason text not null
    check (reason in ('offensive', 'sexual', 'violence', 'spam', 'fake', 'other')),
  details text check (char_length(details) <= 1000),
  snapshot jsonb,
  status text not null default 'open'
    check (status in ('open', 'removed', 'dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

-- Uma denúncia aberta por pessoa e conteúdo: repetir não duplica.
create unique index content_reports_open_unique
  on private.content_reports (reporter_id, target_type, target_id)
  where status = 'open';

create index content_reports_status_created
  on private.content_reports (status, created_at);

alter table private.content_reports enable row level security;
revoke all on private.content_reports from public, anon, authenticated;

create or replace function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_snapshot jsonb;
  v_details text := nullif(btrim(coalesce(p_details, '')), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- Limite contra abuso: 20 denúncias por dia por pessoa.
  if (
    select count(*) from private.content_reports
    where reporter_id = v_uid and created_at > now() - interval '1 day'
  ) >= 20 then
    raise exception 'report_limit';
  end if;

  v_snapshot := case p_target_type
    when 'team' then
      (select to_jsonb(t) from public.teams t where t.id = p_target_id)
    when 'venue' then
      (select to_jsonb(v) from public.venues v where v.id = p_target_id)
    when 'athlete' then
      (select to_jsonb(a) from public.team_players a where a.id = p_target_id)
  end;
  if v_snapshot is null then
    raise exception 'report_target_not_found';
  end if;

  insert into private.content_reports
    (reporter_id, target_type, target_id, reason, details, snapshot)
  values
    (v_uid, p_target_type, p_target_id, p_reason, left(v_details, 1000), v_snapshot)
  on conflict (reporter_id, target_type, target_id) where status = 'open'
  do nothing;
end;
$$;

revoke execute on function public.report_content(text, uuid, text, text)
  from public, anon;
grant execute on function public.report_content(text, uuid, text, text)
  to authenticated;
