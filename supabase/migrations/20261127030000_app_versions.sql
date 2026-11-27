-- Versão mínima do app (Etapa 0 da Fase 2 do multiesporte,
-- docs/multiesporte-fase2-volei.md).
--
-- O app lê, ao abrir, o build mínimo da plataforma dele; abaixo dele, mostra
-- a tela de atualizar, com o link da loja. Serve para liberar o vôlei só
-- quando os apps instalados souberem lidar com ele, e para a fase de limpeza
-- da Fase 1. Começa em 0: ninguém é bloqueado até alguém subir o número.
-- Quem muda é o dono do SportLeague, pelo SQL Editor (service role):
--
--   update public.app_versions set min_build = 8 where platform = 'android';

create table public.app_versions (
  platform text primary key check (platform in ('android', 'ios')),
  -- O número depois do "+" da versão (pubspec: 0.1.0+8 → 8).
  min_build integer not null default 0 check (min_build >= 0),
  -- Link da loja para o botão de atualizar; nulo esconde o botão.
  store_url text check (store_url is null or store_url ~ '^https://'),
  updated_at timestamptz not null default now()
);

insert into public.app_versions (platform, min_build, store_url) values
  ('android', 0, 'https://play.google.com/store/apps/details?id=com.sportleague.sport_league'),
  ('ios', 0, null);

create trigger app_versions_set_updated_at
before update on public.app_versions
for each row execute function public.set_updated_at();

alter table public.app_versions enable row level security;

-- Todos leem (também antes do login: a tela de atualizar vem antes de tudo).
create policy "Todos veem a versão mínima do app"
on public.app_versions for select
to anon, authenticated
using (true);
