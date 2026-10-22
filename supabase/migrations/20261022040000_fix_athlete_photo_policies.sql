-- Correção das regras do bucket athlete-photos (20261022030000_athlete_photos).
-- Nas subconsultas em teams/team_players, "name" era resolvido como a coluna
-- name dessas tabelas, não o nome do arquivo; com isso o dono não conseguia
-- enviar fotos e os atletas do time não conseguiam vê-las. Agora o nome do
-- arquivo é sempre objects.name.

drop policy "Dono e atletas do time veem as fotos" on storage.objects;
drop policy "Dono do time envia fotos dos atletas" on storage.objects;
drop policy "Dono do time troca fotos dos atletas" on storage.objects;

create policy "Dono e atletas do time veem as fotos"
on storage.objects for select
to authenticated
using (
  bucket_id = 'athlete-photos'
  and (
    (storage.foldername(objects.name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.team_players p
      where p.team_id::text = (storage.foldername(objects.name))[2]
        and p.profile_id = (select auth.uid())
    )
  )
);

create policy "Dono do time envia fotos dos atletas"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'athlete-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.teams t
    where t.id::text = (storage.foldername(objects.name))[2]
      and t.owner_id = (select auth.uid())
  )
);

create policy "Dono do time troca fotos dos atletas"
on storage.objects for update
to authenticated
using (
  bucket_id = 'athlete-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'athlete-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.teams t
    where t.id::text = (storage.foldername(objects.name))[2]
      and t.owner_id = (select auth.uid())
  )
);
