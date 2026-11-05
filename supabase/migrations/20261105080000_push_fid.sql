-- Push pelo ID de instalação do Firebase (FID). O firebase_messaging 17
-- marcou getToken/onTokenRefresh como obsoletos (no lugar, register() e
-- onRegistered, que devolvem o FID), e a API HTTP v1 do FCM marcou o campo
-- `token` como obsoleto em favor de `fid`. O app passa a registrar o FID; a
-- Edge Function `send-push` envia com `fid` para ele e continua com `token`
-- para os aparelhos que ainda não atualizaram o app.

alter table public.device_tokens
  add column kind text not null default 'token'
    check (kind in ('token', 'fid'));

drop function public.register_device_token(text, text);

-- Registra (ou passa para o usuário logado) o ID deste aparelho. Ao
-- registrar o FID, o token antigo do mesmo usuário e sistema sai (o
-- aparelho que atualizou o app receberia o push duas vezes).
create or replace function public.register_device_token(
  p_token text,
  p_platform text,
  p_kind text default 'token'
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
  insert into public.device_tokens (token, user_id, platform, kind, updated_at)
  values (p_token, (select auth.uid()), p_platform, p_kind, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        kind = excluded.kind,
        updated_at = now();
  if p_kind = 'fid' then
    delete from public.device_tokens
    where user_id = (select auth.uid())
      and platform = p_platform
      and kind = 'token';
  end if;
end;
$$;

revoke execute on function public.register_device_token(text, text, text)
  from public, anon;
grant execute on function public.register_device_token(text, text, text)
  to authenticated;
