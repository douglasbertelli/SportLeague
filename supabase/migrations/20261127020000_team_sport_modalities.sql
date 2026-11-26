-- Esporte do time ligado às modalidades (Etapa 5 do multiesporte,
-- docs/multiesporte-fase1.md).
--
-- Cada modalidade é de um esporte (`sport_modalities`, da migration
-- sport_stats). Como amistosos e campeonatos já exigem a mesma modalidade, o
-- time ter só modalidades do próprio esporte basta para nenhum jogo juntar
-- esportes diferentes. Os times de hoje passam: são todos de futebol, com
-- modalidades de futebol.

create or replace function private.check_team_sport()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- O esporte do time não muda depois de criado (os jogos, a súmula e os
  -- campeonatos dele são daquele esporte).
  if tg_op = 'UPDATE' and new.sport is distinct from old.sport then
    raise exception 'team_sport_locked' using errcode = '22023';
  end if;

  if exists (
    select 1
      from unnest(new.modalities) as m(modality)
      left join public.sport_modalities sm on sm.modality = m.modality
     where sm.sport is distinct from new.sport
  ) then
    raise exception 'modality_sport' using errcode = '22023';
  end if;

  return new;
end;
$$;
revoke execute on function private.check_team_sport() from public, anon, authenticated;

create trigger teams_check_sport
before insert or update of sport, modalities on public.teams
for each row execute function private.check_team_sport();
