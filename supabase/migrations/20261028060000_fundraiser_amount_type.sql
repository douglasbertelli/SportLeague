-- Vaquinha: o administrador escolhe entre o valor por pessoa (como antes) e o
-- valor total do produto, que o app divide entre o administrador e os atletas
-- do time. `amount_cents` guarda o valor digitado, de um tipo ou de outro.
alter table public.fundraisers
  add column amount_type text not null default 'per_person'
    check (amount_type in ('per_person', 'total'));
