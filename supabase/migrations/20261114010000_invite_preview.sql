-- Prévia do convite por link (/convite/<código>): o time ativo do código,
-- para quem ainda não entrou no site. Só nome, símbolo, cidade e modalidades.
create or replace function public.invite_preview(p_code text)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'logo_url', t.logo_url,
    'city', t.city,
    'state', t.state,
    'modalities', t.modalities
  )
  from public.team_invite_codes c
  join public.teams t on t.id = c.team_id and t.inactive_at is null
  where c.code = upper(trim(p_code));
$$;

revoke all on function public.invite_preview(text) from public;
grant execute on function public.invite_preview(text) to anon, authenticated;
