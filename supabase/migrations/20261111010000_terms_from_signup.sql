-- Quem cria a conta pelo site aceita os Termos e a Política no próprio
-- cadastro (vai em `terms_accepted_at` nos metadados). O perfil já nasce com
-- esse aceite, para o app não pedir de novo no primeiro login. Valor fora do
-- formato é ignorado (o app pede o aceite como antes); nunca no futuro.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := new.raw_user_meta_data;
  name text := left(trim(coalesce(
    nullif(trim(meta ->> 'full_name'), ''),
    nullif(trim(meta ->> 'name'), ''),
    ''
  )), 120);
  accepted text := meta ->> 'terms_accepted_at';
begin
  insert into public.profiles (id, full_name, role, avatar_url, terms_accepted_at)
  values (
    new.id,
    case when char_length(name) >= 2 then name else 'Usuário' end,
    (meta ->> 'role')::public.user_role,
    coalesce(meta ->> 'avatar_url', meta ->> 'picture'),
    case
      when accepted ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$'
        then least(accepted::timestamptz, now())
    end
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
