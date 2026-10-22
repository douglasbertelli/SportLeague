-- Correção de dados da migration game_status (aplicada em 2026-10-22 03:00:54
-- UTC). Ela marcou todos os jogos existentes como "scheduled", inclusive os
-- convites contra times da plataforma que o adversário nunca aceitou (aceitar
-- ainda não existia). Esses convites voltam a ficar pendentes, para os dois
-- times verem em Pendentes até o adversário aceitar.
--
-- Um jogo aceito depois da game_status teria updated_at posterior a ela; os
-- que continuam com updated_at anterior nunca foram respondidos.

update public.games
set status = 'pending'
where status = 'scheduled'
  and opponent_team_id is not null
  and updated_at < timestamptz '2026-10-22 03:00:54+00';
