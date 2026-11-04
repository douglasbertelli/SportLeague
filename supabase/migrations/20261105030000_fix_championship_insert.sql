-- Criar campeonato falhava: o app insere e lê a linha de volta (RETURNING),
-- e a política de leitura passava só por private.can_see_championship, que
-- consulta a tabela e ainda não enxerga a linha recém-inserida no mesmo
-- comando. O organizador agora é conferido direto pela coluna.

drop policy "Organizador e times inscritos veem o campeonato"
on public.championships;

create policy "Organizador e times inscritos veem o campeonato"
on public.championships for select
to authenticated
using (
  owner_id = (select auth.uid())
  or private.can_see_championship(id, (select auth.uid()))
);
