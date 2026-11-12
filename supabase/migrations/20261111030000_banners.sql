-- Banners do time (Premium): o administrador monta no app, a partir de
-- modelos (anúncio de jogo, resultado, convocação, aniversariante, campeão,
-- aviso), com as cores, as fontes e o escudo do time, e compartilha a imagem.
-- O banner é gerado e guardado só no aparelho: o banco só diz se o plano
-- libera o recurso. No Elite (sem linha) fica liberado.

insert into public.plan_features (plan, feature, quota, description) values
  ('free', 'banners', 0, null),
  ('premium', 'banners', null,
   'Crie banners para as redes a partir de modelos (jogo, resultado, '
   || 'convocação, aniversariante, campeão), com as cores, as fontes e o '
   || 'escudo do time.')
on conflict (plan, feature) do nothing;
