-- ============================================================
--  ADAMI — passo 4: convites, primeiro acesso e papéis unificados
--
--  Criar usuário pela rota de administração do Supabase exige a
--  chave service_role, que não pode ir para o navegador. O caminho
--  que funciona com a chave publicável é outro: o master convida,
--  e a própria pessoa define a senha no primeiro acesso.
--
--  Rodar DEPOIS de adami_banco.sql, adami_supremo.sql, crm_schema.sql
--  e crm_acessos.sql. Pode rodar de novo.
-- ============================================================

-- ------------------------------------------------------------
--  1. O convite passa a carregar os papéis dos DOIS sistemas
--     Uma pessoa, um convite. Sem isso, o master cadastraria a
--     mesma pessoa duas vezes, em telas diferentes.
-- ------------------------------------------------------------
alter table public.convites
  add column if not exists master  boolean not null default false,
  add column if not exists admin   boolean not null default false,
  add column if not exists mesa_rv boolean not null default false,
  add column if not exists convidado_por uuid references auth.users(id) on delete set null,
  add column if not exists criado_em timestamptz not null default now();

-- ------------------------------------------------------------
--  2. Só quem foi convidado entra
--     Sem esta trava, /auth/v1/signup fica aberto: qualquer pessoa
--     com o endereço do portal criaria conta. A conta não teria
--     privilégio nenhum, mas existiria — e isso é porta aberta.
-- ------------------------------------------------------------
create or replace function public.exige_convite()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.convites c
                  where c.email = lower(new.email) and c.consumido_em is null) then
    raise exception 'Cadastro permitido apenas para e-mails convidados pela Adami.';
  end if;
  return new;
end $$;

drop trigger if exists exige_convite_trg on auth.users;
create trigger exige_convite_trg before insert on auth.users
  for each row execute function public.exige_convite();

-- ------------------------------------------------------------
--  3. O perfil do PORTAL nasce com o que o convite disse
--     Substitui criar_perfil, que criava todo mundo sem privilégio.
-- ------------------------------------------------------------
create or replace function public.criar_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
declare cv public.convites%rowtype;
begin
  select * into cv from public.convites where email = lower(new.email);
  insert into public.perfis(user_id, nome, admin, mesa_rv, super)
  values (new.id,
          coalesce(nullif(cv.nome,''),
                   nullif(new.raw_user_meta_data->>'nome',''),
                   split_part(new.email,'@',1)),
          coalesce(cv.admin,false),
          coalesce(cv.mesa_rv,false),
          coalesce(cv.master,false))
  on conflict (user_id) do nothing;
  return new;
exception when others then
  return new;   -- nunca impedir a criação da conta por causa do perfil
end $$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.criar_perfil();


-- ------------------------------------------------------------
--  3b. O convite deixa de ser apagado ao ser usado
--     O gatilho do CRM apagava o convite depois de consumi-lo, e o
--     gatilho do portal le o MESMO convite no mesmo INSERT. A ordem
--     entre eles e alfabetica pelo nome do gatilho: funciona hoje
--     por acaso. Marcar como consumido em vez de apagar remove a
--     dependencia de ordem e ainda deixa o rastro de quem convidou.
-- ------------------------------------------------------------
alter table public.convites
  add column if not exists consumido_em timestamptz;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  primeiro boolean;
  convite  public.convites%rowtype;
begin
  select count(*) = 0 into primeiro from public.profiles;
  select * into convite from public.convites
   where email = lower(new.email) and consumido_em is null;

  if convite.email is not null then
    insert into public.profiles (id, nome, role, status, produtos)
    values (new.id, convite.nome, convite.role, 'ativo', convite.produtos)
    on conflict (id) do nothing;
    update public.convites set consumido_em = now() where email = convite.email;
  else
    insert into public.profiles (id, nome, role, status)
    values (new.id,
            coalesce(nullif(new.raw_user_meta_data->>'nome',''), split_part(new.email,'@',1)),
            case when primeiro then 'admin' else 'vendedor' end,
            case when primeiro then 'ativo' else 'pendente' end)
    on conflict (id) do nothing;
  end if;
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
--  4. Quem pode convidar: só o master
-- ------------------------------------------------------------
alter table public.convites enable row level security;

drop policy if exists convites_admin on public.convites;
drop policy if exists convites_master_ler on public.convites;
drop policy if exists convites_master_escrever on public.convites;

create policy convites_master_ler on public.convites for select
  to authenticated using (public.eh_super());
create policy convites_master_escrever on public.convites for all
  to authenticated using (public.eh_super()) with check (public.eh_super());

-- ------------------------------------------------------------
--  5. Convidar e revogar, pela tela de Equipe
-- ------------------------------------------------------------
create or replace function public.convidar(
  p_email text, p_nome text, p_role text,
  p_master boolean default false, p_admin boolean default false,
  p_mesa_rv boolean default false, p_produtos text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_super() then
    raise exception 'Apenas o master pode convidar.';
  end if;
  if p_role not in ('admin','vendedor','especialista') then
    raise exception 'Papel invalido no CRM: %', p_role;
  end if;
  if position('@' in p_email) = 0 then
    raise exception 'E-mail invalido.';
  end if;
  if exists (select 1 from auth.users u where lower(u.email) = lower(p_email)) then
    raise exception 'Ja existe conta com este e-mail. Use a tela de Equipe para ajustar os acessos.';
  end if;

  insert into public.convites (email, nome, role, produtos, master, admin, mesa_rv, convidado_por)
  values (lower(p_email), p_nome, p_role, coalesce(p_produtos,'{}'),
          p_master, p_admin, p_mesa_rv, auth.uid())
  on conflict (email) do update
    set nome=excluded.nome, role=excluded.role, produtos=excluded.produtos,
        master=excluded.master, admin=excluded.admin, mesa_rv=excluded.mesa_rv,
        convidado_por=excluded.convidado_por, criado_em=now();

  insert into public.auditoria(usuario, acao, alvo, detalhe)
  values (coalesce(auth.jwt() ->> 'email','?'), 'convite', lower(p_email),
          'papel CRM '||p_role||coalesce(', master',''));
end $$;

create or replace function public.revogar_convite(p_email text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_super() then
    raise exception 'Apenas o master pode revogar convite.';
  end if;
  delete from public.convites where email = lower(p_email);
end $$;

create or replace function public.listar_convites()
returns table (email text, nome text, role text, produtos text[],
               master boolean, admin boolean, mesa_rv boolean, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select c.email, c.nome, c.role, c.produtos, c.master, c.admin, c.mesa_rv, c.criado_em
  from public.convites c
  where public.eh_super() and c.consumido_em is null
  order by c.criado_em desc;
$$;

-- ------------------------------------------------------------
--  6. A Equipe passa a mostrar e editar os papéis dos dois sistemas
-- ------------------------------------------------------------
create or replace function public.listar_equipe()
returns table (
  user_id uuid, email text, nome text,
  admin boolean, mesa_rv boolean, super boolean,
  crm_role text, crm_status text, crm_produtos text[], criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select p.user_id, u.email::text, p.nome, p.admin, p.mesa_rv, p.super,
         pr.role, pr.status, pr.produtos, u.created_at
  from public.perfis p
  join auth.users u on u.id = p.user_id
  left join public.profiles pr on pr.id = p.user_id
  where public.eh_admin()
  order by p.super desc, p.admin desc, p.mesa_rv desc, u.email;
$$;

/* Papel no CRM, alterado pela tela de Equipe. A escrita direta em
   profiles continua restrita: passa por aqui, que confere quem pede. */
create or replace function public.definir_papel_crm(
  p_user_id uuid, p_role text, p_status text default null, p_produtos text[] default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_super() then
    raise exception 'Apenas o master pode alterar papeis no CRM.';
  end if;
  if p_role not in ('admin','vendedor','especialista') then
    raise exception 'Papel invalido: %', p_role;
  end if;
  if p_status is not null and p_status not in ('pendente','ativo','removido') then
    raise exception 'Status invalido: %', p_status;
  end if;

  insert into public.profiles (id, nome, role, status, produtos)
  select p_user_id,
         coalesce((select nome from public.perfis where user_id = p_user_id), 'Sem nome'),
         p_role, coalesce(p_status,'ativo'), coalesce(p_produtos,'{}')
  on conflict (id) do update
    set role = excluded.role,
        status = coalesce(p_status, public.profiles.status),
        produtos = coalesce(p_produtos, public.profiles.produtos);

  insert into public.auditoria(usuario, acao, alvo, detalhe)
  values (coalesce(auth.jwt() ->> 'email','?'), 'papel-crm',
          (select email from auth.users where id = p_user_id),
          p_role||coalesce(' / '||p_status,''));
end $$;

revoke all on function public.convidar(text,text,text,boolean,boolean,boolean,text[]),
                      public.revogar_convite(text), public.listar_convites(),
                      public.definir_papel_crm(uuid,text,text,text[]) from public;
grant execute on function public.convidar(text,text,text,boolean,boolean,boolean,text[]),
                          public.revogar_convite(text), public.listar_convites(),
                          public.definir_papel_crm(uuid,text,text,text[]) to authenticated;

-- ============================================================
--  7. MASTER — Emil, Bibiana e Rafael
--     Troque os nomes antes do @ se estiverem diferentes.
-- ============================================================
update public.perfis p set super = true, admin = true
from auth.users u
where u.id = p.user_id
  and lower(split_part(u.email,'@',1)) in ('emil.stade','bibiana','rafael');

-- ============================================================
--  8. CONFERÊNCIA
-- ============================================================
select u.email, p.nome,
       p.super as master, p.admin as administrador, p.mesa_rv as edita_rv,
       pr.role as papel_crm, pr.status as status_crm
from public.perfis p
join auth.users u on u.id = p.user_id
left join public.profiles pr on pr.id = p.user_id
order by p.super desc, p.admin desc, u.email;
