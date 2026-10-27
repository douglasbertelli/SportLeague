-- =========================================================
-- Técnicos no perfil do time
-- O perfil do time mostra a comissão técnica (foto e nome) para quem o
-- visita, então o vínculo fica visível como os times e os perfis. Entrar e
-- sair continua restrito (aceite do convite; o técnico ou o dono removem).
-- =========================================================
drop policy "Técnico e dono veem o vínculo" on public.team_coaches;

create policy "Técnicos visíveis para usuários autenticados"
on public.team_coaches for select
to authenticated
using (true);
