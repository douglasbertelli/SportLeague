-- =========================================================
-- Fotos de perfil (Storage)
-- Público para leitura (a foto aparece para os times do usuário); cada
-- usuário grava só na própria pasta (<id do usuário>/avatar).
-- =========================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-photos',
  'profile-photos',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
);

create policy "Usuário vê a própria foto de perfil"
on storage.objects for select
to authenticated
using (
  bucket_id = 'profile-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);

create policy "Usuário envia a foto de perfil na própria pasta"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'profile-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);

create policy "Usuário troca a própria foto de perfil"
on storage.objects for update
to authenticated
using (
  bucket_id = 'profile-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'profile-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);

create policy "Usuário remove a própria foto de perfil"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'profile-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);
