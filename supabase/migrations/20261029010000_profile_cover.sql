-- Capa do perfil do jogador: a imagem larga atrás da foto. Fica no Storage
-- público `profile-photos`, na pasta do próprio usuário (<id>/cover), com as
-- mesmas regras da foto de perfil.
alter table public.profiles add column cover_url text;
