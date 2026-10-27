-- Vaquinha: novo item Churrasco, entre Uniforme e Outros.
alter table public.fundraisers drop constraint fundraisers_item_check;
alter table public.fundraisers
  add constraint fundraisers_item_check
    check (item in ('ball', 'bib', 'kit', 'barbecue', 'other'));
