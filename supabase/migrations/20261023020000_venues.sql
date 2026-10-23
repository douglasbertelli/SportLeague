-- Locais das partidas: cadastrados uma vez e escolhidos ao marcar o amistoso.
-- São compartilhados: qualquer administrador pesquisa e usa; só quem cadastrou
-- altera ou remove. Antes de cadastrar, o app procura locais parecidos
-- (similar_venues) para sugerir o existente e evitar duplicados.

create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references public.profiles (id) on delete set null,
  name text not null check (char_length(trim(name)) between 2 and 120),
  zip_code text not null check (zip_code ~ '^\d{8}$'),
  street text not null,
  number text not null,
  complement text,
  neighborhood text not null,
  city text not null,
  state text not null check (state ~ '^[A-Z]{2}$'),
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index venues_created_by_idx on public.venues (created_by);

create trigger venues_set_updated_at
before update on public.venues
for each row execute function public.set_updated_at();

alter table public.venues enable row level security;

create policy "Locais visíveis para usuários autenticados"
on public.venues for select
to authenticated
using (true);

create policy "Administrador cadastra local"
on public.venues for insert
to authenticated
with check (
  (select auth.uid()) = created_by and private.is_admin((select auth.uid()))
);

create policy "Quem cadastrou altera o local"
on public.venues for update
to authenticated
using ((select auth.uid()) = created_by)
with check ((select auth.uid()) = created_by);

create policy "Quem cadastrou remove o local"
on public.venues for delete
to authenticated
using ((select auth.uid()) = created_by);

-- Local do amistoso. Jogos antigos ficam só com o texto em games.location;
-- se o local for removido, o jogo continua sem ele.
alter table public.games
  add column venue_id uuid references public.venues (id) on delete set null;

create index games_venue_id_idx on public.games (venue_id);

-- Texto para comparar nomes: sem acento, minúsculo e sem espaços sobrando.
create or replace function private.normalize_text(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select trim(regexp_replace(
    lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_text, ''))),
    '\s+', ' ', 'g'
  ));
$$;

revoke execute on function private.normalize_text(text) from public, anon;
grant execute on function private.normalize_text(text) to authenticated;

-- Locais que parecem ser o mesmo que está sendo cadastrado: mesmo CEP e
-- número, ou nome parecido na mesma cidade. [p_except] ignora o local em
-- edição. Roda com as permissões de quem chama (os locais já são visíveis).
create or replace function public.similar_venues(
  p_name text,
  p_zip_code text,
  p_number text,
  p_city text,
  p_state text,
  p_except uuid default null
)
returns setof public.venues
language sql
stable
set search_path = ''
as $$
  select v.*
  from public.venues v
  where (p_except is null or v.id <> p_except)
    and (
      (
        v.zip_code = regexp_replace(coalesce(p_zip_code, ''), '\D', '', 'g')
        and private.normalize_text(v.number) = private.normalize_text(p_number)
      )
      or (
        private.normalize_text(v.city) = private.normalize_text(p_city)
        and v.state = upper(trim(coalesce(p_state, '')))
        and (
          extensions.similarity(
            private.normalize_text(v.name),
            private.normalize_text(p_name)
          ) >= 0.4
          or private.normalize_text(v.name) like
            '%' || private.normalize_text(p_name) || '%'
          or private.normalize_text(p_name) like
            '%' || private.normalize_text(v.name) || '%'
        )
      )
    )
  order by extensions.similarity(
    private.normalize_text(v.name),
    private.normalize_text(p_name)
  ) desc
  limit 5;
$$;

revoke execute on function public.similar_venues(text, text, text, text, text, uuid) from public, anon;
grant execute on function public.similar_venues(text, text, text, text, text, uuid) to authenticated;

-- =========================================================
-- Fotos dos locais (Storage)
-- Público para leitura; cada administrador grava só na própria pasta
-- (<id do usuário>/<id do local>).
-- =========================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'venue-photos',
  'venue-photos',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
);

create policy "Administrador vê as próprias fotos de locais"
on storage.objects for select
to authenticated
using (
  bucket_id = 'venue-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);

create policy "Administrador envia foto de local na própria pasta"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'venue-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);

create policy "Administrador troca a própria foto de local"
on storage.objects for update
to authenticated
using (
  bucket_id = 'venue-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'venue-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);

create policy "Administrador remove a própria foto de local"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'venue-photos'
  and (storage.foldername(objects.name))[1] = (select auth.uid())::text
);
