-- Notificações push. O app guarda o token do aparelho (Firebase Cloud
-- Messaging); a cada notificação nova, o banco chama a Edge Function
-- `send-push`, que manda o push pelo FCM para os aparelhos do destinatário.
--
-- Depois de rodar esta migration, guarde a URL do projeto no Vault (uma vez):
--   select vault.create_secret('https://<projeto>.supabase.co', 'project_url');
-- Sem ela, as notificações continuam só dentro do app.

create extension if not exists pg_net with schema extensions;

-- Aparelhos que recebem push. O token é do aparelho: se outra conta entrar
-- nele, o token passa para ela.
create table public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_id on public.device_tokens (user_id);

-- Sem políticas: o app só mexe pelas funções abaixo; a Edge Function lê com a
-- service role.
alter table public.device_tokens enable row level security;

-- Registra (ou passa para o usuário logado) o token deste aparelho.
create or replace function public.register_device_token(
  p_token text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Not authenticated';
  end if;
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, (select auth.uid()), p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

-- Tira o token deste aparelho (ao sair da conta).
create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens
  where token = p_token and user_id = (select auth.uid());
$$;

revoke execute on function public.register_device_token(text, text)
  from public, anon;
revoke execute on function public.unregister_device_token(text)
  from public, anon;
grant execute on function public.register_device_token(text, text)
  to authenticated;
grant execute on function public.unregister_device_token(text)
  to authenticated;

-- Quando o push foi enviado. A Edge Function só envia se ainda estiver vazio,
-- então chamá-la de novo com a mesma notificação não manda outro push.
alter table public.notifications add column pushed_at timestamptz;

-- A cada notificação nova, chama a Edge Function (sem esperar a resposta).
-- Uma falha aqui nunca impede a notificação de ser criada.
create or replace function private.send_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  project_url text;
begin
  if not exists (
    select 1 from public.device_tokens where user_id = new.recipient_id
  ) then
    return null;
  end if;

  select decrypted_secret into project_url
  from vault.decrypted_secrets
  where name = 'project_url';
  if project_url is null then
    return null;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/send-push',
    body := jsonb_build_object('id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
  return null;
exception
  when others then
    return null;
end;
$$;

revoke execute on function private.send_push() from public, anon, authenticated;

create trigger notifications_send_push
after insert on public.notifications
for each row execute function private.send_push();
