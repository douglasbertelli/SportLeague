-- Foto do atleta.
-- O app exige a foto ao salvar; no banco fica opcional para não quebrar atletas
-- cadastrados antes deste campo.

alter table public.team_players add column photo_path text;

-- =========================================================
-- Fotos dos atletas (Storage), privado: são fotos de pessoas, inclusive
-- menores de idade (faixa Base). Caminho: <dono do time>/<time>/<atleta>.
-- Veem: o dono do time e os atletas do mesmo time (por URL assinada).
-- Gravam: só o dono do time.
-- =========================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'athlete-photos',
  'athlete-photos',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
);

create policy "Dono e atletas do time veem as fotos"
on storage.objects for select
to authenticated
using (
  bucket_id = 'athlete-photos'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.team_players p
      where p.team_id::text = (storage.foldername(name))[2]
        and p.profile_id = (select auth.uid())
    )
  )
);

create policy "Dono do time envia fotos dos atletas"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'athlete-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.teams t
    where t.id::text = (storage.foldername(name))[2]
      and t.owner_id = (select auth.uid())
  )
);

create policy "Dono do time troca fotos dos atletas"
on storage.objects for update
to authenticated
using (
  bucket_id = 'athlete-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'athlete-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.teams t
    where t.id::text = (storage.foldername(name))[2]
      and t.owner_id = (select auth.uid())
  )
);

create policy "Dono do time remove fotos dos atletas"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'athlete-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
