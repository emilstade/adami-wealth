-- ============================================================
--  CRM — passo 2: perfis para quem JÁ existe
--
--  O gatilho do CRM só dispara quando um usuário novo é criado.
--  Você e a equipe já existem em auth.users desde o portal, então
--  ficariam sem linha em profiles — e o CRM abriria vazio, porque
--  is_ativo() devolve falso para quem não tem perfil.
--
--  Rodar DEPOIS do supabase-schema-v2.sql. Pode rodar de novo.
-- ============================================================

-- ------------------------------------------------------------
--  1. Protege a criação de usuário
--     Um erro no gatilho aborta o INSERT em auth.users. Como o
--     portal tem o próprio gatilho na mesma tabela, uma falha aqui
--     derrubaria a criação de contas para os dois sistemas.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  primeiro boolean;
  convite  public.convites%rowtype;
begin
  select count(*) = 0 into primeiro from public.profiles;
  select * into convite from public.convites where email = lower(new.email);

  if convite.email is not null then
    insert into public.profiles (id, nome, role, status, produtos)
    values (new.id, convite.nome, convite.role, 'ativo', convite.produtos)
    on conflict (id) do nothing;                      -- <<< não derruba o cadastro
    delete from public.convites where email = convite.email;
  else
    insert into public.profiles (id, nome, role, status)
    values (
      new.id,
      coalesce(nullif(new.raw_user_meta_data->>'nome',''), split_part(new.email, '@', 1)),
      case when primeiro then 'admin' else 'vendedor' end,
      case when primeiro then 'ativo' else 'pendente' end
    )
    on conflict (id) do nothing;                      -- <<< idem
  end if;
  return new;
exception when others then
  -- Nunca impedir a criação do usuário por causa do CRM.
  -- Sem perfil, ele aparece na tela de Equipe para ser liberado.
  return new;
end;
$$;

-- ------------------------------------------------------------
--  2. Cria perfil para todo mundo que já existe
--     Entram como 'vendedor' e 'pendente': veem o CRM, mas não
--     assumem lead até você liberar.
-- ------------------------------------------------------------
insert into public.profiles (id, nome, role, status)
select u.id,
       coalesce(nullif(u.raw_user_meta_data->>'nome',''), split_part(u.email,'@',1)),
       'vendedor',
       'pendente'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);

-- ------------------------------------------------------------
--  3. Quem manda no CRM — casa pelo nome antes do @,
--     então não importa se o domínio é adamicaptal ou outro.
-- ------------------------------------------------------------
update public.profiles p
set role = 'admin', status = 'ativo'
from auth.users u
where u.id = p.id
  and lower(split_part(u.email,'@',1)) = 'emil.stade';

update public.profiles p
set status = 'ativo'
from auth.users u
where u.id = p.id
  and lower(split_part(u.email,'@',1)) = 'thiago.miranda';

-- ------------------------------------------------------------
--  4. CONFERÊNCIA — é esta tabela que importa
--     emil.stade precisa sair com role = admin e status = ativo.
--     Quem estiver 'pendente' vê o CRM mas não recebe lead.
-- ------------------------------------------------------------
select u.email,
       p.nome,
       p.role,
       p.status,
       p.produtos
from public.profiles p
join auth.users u on u.id = p.id
order by (p.role = 'admin') desc, p.status, u.email;
