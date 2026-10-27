-- Novo perfil: técnico. O valor do enum fica numa migration própria (não
-- pode ser usado na mesma transação em que é criado).
alter type public.user_role add value if not exists 'coach';
