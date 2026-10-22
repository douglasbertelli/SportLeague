-- Detalhes do time: modalidade, gênero, fundação, faixa de idade e logo.

create type public.team_modality as enum ('futsal', 'society', 'field', 'beach');
create type public.team_gender as enum ('male', 'female');
create type public.age_group as enum ('open', 'youth', 'master');

-- O app exige modalidade e gênero ao salvar; no banco ficam opcionais para não
-- quebrar times criados antes destes campos.
alter table public.teams
  add column modalities public.team_modality[] not null default '{}',
  add column gender public.team_gender,
  add column founded_on date check (founded_on <= current_date),
  add column age_group public.age_group not null default 'open';

-- =========================================================
-- Logos dos times (Storage)
-- Público para leitura; cada administrador grava só na própria pasta
-- (<id do usuário>/<id do time>).
-- =========================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'team-logos',
  'team-logos',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
);

create policy "Administrador vê os próprios logos"
on storage.objects for select
to authenticated
using (
  bucket_id = 'team-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Administrador envia logo na própria pasta"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'team-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Administrador troca o próprio logo"
on storage.objects for update
to authenticated
using (
  bucket_id = 'team-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'team-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Administrador remove o próprio logo"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'team-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
