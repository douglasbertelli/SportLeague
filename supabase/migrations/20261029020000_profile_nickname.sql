-- Apelido do jogador: o nome mostrado no perfil dele (o nome completo fica
-- em Config). Nulo mostra o nome completo.
alter table public.profiles
  add column nickname text
    check (nickname is null or char_length(trim(nickname)) between 1 and 40);
