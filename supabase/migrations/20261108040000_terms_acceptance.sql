-- Quando o usuário aceitou os Termos de Uso e a Política de Privacidade.
-- O app pede o aceite de novo quando a versão dos documentos muda (data
-- mais nova que esta).
alter table public.profiles add column terms_accepted_at timestamptz;
