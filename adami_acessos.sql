-- ============================================================
--  ADAMI — passo 2: liberar acessos
--  Rodar SÓ DEPOIS que as contas existirem em Authentication > Users.
--  Casa pelo nome antes do @, então não importa se o domínio é
--  adamicaptal.com.br ou adamicapital.com.br.
-- ============================================================

-- ------------------------------------------------------------
--  A) Quem existe hoje. Olhe esta lista antes de seguir.
-- ------------------------------------------------------------
select u.email, p.nome, p.admin as administrador, p.mesa_rv as edita_rv, u.created_at
from auth.users u
left join public.perfis p on p.user_id = u.id
order by u.created_at;

-- ------------------------------------------------------------
--  B) Administrador — vê todos os clientes, backups e auditoria
-- ------------------------------------------------------------
update public.perfis set admin = true
where user_id in (
  select id from auth.users
  where lower(split_part(email,'@',1)) = 'emil.stade'
);

-- ------------------------------------------------------------
--  C) Mesa RV — escreve nas operações e alocações
--     O admin já entra por herança, não precisa repetir.
-- ------------------------------------------------------------
update public.perfis set mesa_rv = true
where user_id in (
  select id from auth.users
  where lower(split_part(email,'@',1)) = 'thiago.miranda'
);

-- ------------------------------------------------------------
--  D) Nome na barra lateral, para quem ficou em branco
-- ------------------------------------------------------------
update public.perfis p
set nome = initcap(replace(split_part(u.email,'@',1),'.',' '))
from auth.users u
where u.id = p.user_id and coalesce(p.nome,'') = '';

-- ------------------------------------------------------------
--  E) Conferência final — é ESTA tabela que importa
--     emil.stade precisa sair com administrador = true
--     thiago.miranda precisa sair com edita_rv = true
--     Se algum sair false, o e-mail cadastrado é outro:
--     confira na lista do item A e me avise.
-- ------------------------------------------------------------
select u.email, p.nome, p.admin as administrador, p.mesa_rv as edita_rv
from public.perfis p
join auth.users u on u.id = p.user_id
order by p.admin desc, p.mesa_rv desc, u.email;
