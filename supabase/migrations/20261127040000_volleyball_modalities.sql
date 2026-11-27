-- Modalidades do vôlei no banco (Etapa 2 da Fase 2 do multiesporte,
-- docs/multiesporte-fase2-volei.md).
--
-- Valores novos de enum ficam numa migration própria: não podem ser usados
-- na mesma transação em que foram criados. A migration seguinte
-- (volleyball_sets) os usa.

alter type public.team_modality add value if not exists 'volleyball_indoor';
alter type public.team_modality add value if not exists 'volleyball_beach';
