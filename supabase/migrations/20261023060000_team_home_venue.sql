-- Local do time: onde ele joga como mandante. Vem preenchido ao marcar
-- amistoso (o administrador pode trocar). Se o local for excluído, o time
-- fica sem local.

alter table public.teams
  add column home_venue_id uuid references public.venues (id) on delete set null;

create index teams_home_venue_id_idx on public.teams (home_venue_id);
