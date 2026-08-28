-- ============================================================
--  ADAMI — passo 3: acesso supremo e correção de segurança
--
--  Este script conserta uma falha do passo 1: a política de update
--  em perfis deixava QUALQUER assessor gravar admin = true na
--  própria linha pela API e virar administrador sozinho.
--
--  Rodar inteiro no SQL Editor. Pode rodar de novo sem quebrar.
--  Se aparecer "Potential issues detected", use Run without RLS.
-- ============================================================

-- ------------------------------------------------------------
--  1. Nível supremo
--     super = quem pode conceder e revogar privilégios.
--     Ninguém nasce com ele; é dado aqui embaixo, no item 6.
-- ------------------------------------------------------------
alter table public.perfis
  add column if not exists super boolean not null default false;

create or replace function public.eh_super()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.super from public.perfis p where p.user_id = auth.uid()), false);
$$;

-- super manda em tudo que o admin manda
create or replace function public.eh_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin or p.super from public.perfis p where p.user_id = auth.uid()), false);
$$;

-- e também na Mesa RV
create or replace function public.pode_editar_rv()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.mesa_rv or p.admin or p.super
                   from public.perfis p where p.user_id = auth.uid()), false);
$$;

revoke all on function public.eh_super(), public.eh_admin(), public.pode_editar_rv() from public;
grant execute on function public.eh_super(), public.eh_admin(), public.pode_editar_rv() to authenticated;

-- ------------------------------------------------------------
--  2. Trava nas colunas de privilégio
--     Impede alteração de admin, mesa_rv e super por quem não é
--     supremo. auth.uid() nulo = SQL Editor ou service_role, que
--     continuam podendo — é a sua saída de emergência.
-- ------------------------------------------------------------
create or replace function public.proteger_privilegios()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;                      -- SQL Editor / service_role
  end if;

  if (new.admin   is distinct from old.admin)
  or (new.mesa_rv is distinct from old.mesa_rv)
  or (new.super   is distinct from old.super) then
    if not public.eh_super() then
      raise exception
        'Apenas o administrador supremo pode alterar privilegios (admin, mesa_rv, super).';
    end if;
  end if;

  if new.user_id is distinct from old.user_id then
    raise exception 'O vinculo do perfil com o usuario nao pode ser alterado.';
  end if;

  return new;
end $$;

drop trigger if exists perfis_proteger on public.perfis;
create trigger perfis_proteger before update on public.perfis
  for each row execute function public.proteger_privilegios();

-- Perfil novo nunca nasce com privilégio, aconteça o que acontecer
create or replace function public.perfil_novo_sem_privilegio()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.eh_super() then
    new.admin   := false;
    new.mesa_rv := false;
    new.super   := false;
  end if;
  return new;
end $$;

drop trigger if exists perfis_nascimento on public.perfis;
create trigger perfis_nascimento before insert on public.perfis
  for each row execute function public.perfil_novo_sem_privilegio();

-- ------------------------------------------------------------
--  3. Segunda barreira: permissão no nível da coluna
--     Pela API, o autenticado só consegue escrever em "nome".
--     Um PATCH em admin/mesa_rv/super é recusado pelo Postgres
--     antes mesmo de chegar na política.
--     O portal apenas LÊ perfis, então isso não quebra nada.
-- ------------------------------------------------------------
revoke update on public.perfis from authenticated;
grant  update (nome) on public.perfis to authenticated;

-- ------------------------------------------------------------
--  4. Políticas de perfis, reescritas
-- ------------------------------------------------------------
drop policy if exists perfis_ler     on public.perfis;
drop policy if exists perfis_alterar on public.perfis;
drop policy if exists perfis_apagar  on public.perfis;

create policy perfis_ler on public.perfis for select to authenticated
  using (user_id = auth.uid() or public.eh_admin());

create policy perfis_alterar on public.perfis for update to authenticated
  using (user_id = auth.uid() or public.eh_admin())
  with check (user_id = auth.uid() or public.eh_admin());

-- apagar perfil: só o supremo
create policy perfis_apagar on public.perfis for delete to authenticated
  using (public.eh_super());

-- ------------------------------------------------------------
--  5. Backups continuam exclusivos de quem manda
-- ------------------------------------------------------------
drop policy if exists backups_admin on public.backups;
create policy backups_admin on public.backups for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

-- ============================================================
--  6. CONCEDER O NÍVEL SUPREMO — só você
--     Roda aqui no SQL Editor, onde auth.uid() é nulo e o
--     trigger deixa passar. Casa pelo nome antes do @.
-- ============================================================
update public.perfis set super = true, admin = true
where user_id in (
  select id from auth.users
  where lower(split_part(email,'@',1)) = 'emil.stade'
);

-- Garante que mais ninguém tem supremo nem admin
update public.perfis set super = false, admin = false
where user_id not in (
  select id from auth.users
  where lower(split_part(email,'@',1)) = 'emil.stade'
);

-- Thiago segue editando a Mesa RV (não é supremo, não é admin)
update public.perfis set mesa_rv = true
where user_id in (
  select id from auth.users
  where lower(split_part(email,'@',1)) = 'thiago.miranda'
);

-- ============================================================
--  7. CONFERÊNCIA — é esta tabela que importa
--     emil.stade ....... supremo true,  admin true,  edita_rv true
--     thiago.miranda ... supremo false, admin false, edita_rv true
--     demais ........... tudo false
-- ============================================================
select u.email,
       p.nome,
       p.super   as supremo,
       p.admin   as administrador,
       p.mesa_rv as edita_rv
from public.perfis p
join auth.users u on u.id = p.user_id
order by p.super desc, p.admin desc, p.mesa_rv desc, u.email;

-- ============================================================
--  8. GESTÃO DE EQUIPE PELA TELA
--     A escrita direta em admin/mesa_rv está bloqueada de propósito
--     (item 3). Para o portal conseguir gerir permissões sem abrir
--     esse buraco de novo, a mudança passa por estas duas funções,
--     que checam quem está chamando antes de fazer qualquer coisa.
-- ============================================================

-- Lista a equipe com e-mail. auth.users não é exposta pela API,
-- por isso a leitura precisa vir por função.
create or replace function public.listar_equipe()
returns table (
  user_id uuid, email text, nome text,
  admin boolean, mesa_rv boolean, super boolean, criado_em timestamptz
)
language sql stable security definer set search_path = public as $$
  select p.user_id, u.email::text, p.nome, p.admin, p.mesa_rv, p.super, u.created_at
  from public.perfis p
  join auth.users u on u.id = p.user_id
  where public.eh_admin()          -- quem não é admin recebe lista vazia
  order by p.super desc, p.admin desc, p.mesa_rv desc, u.email;
$$;

-- Concede ou revoga. Só o supremo executa, e ninguém mexe no supremo.
create or replace function public.definir_privilegio(
  p_user_id uuid, p_campo text, p_valor boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v_super boolean;
begin
  if not public.eh_super() then
    raise exception 'Apenas o administrador supremo pode alterar privilegios.';
  end if;
  if p_campo not in ('admin','mesa_rv') then
    raise exception 'Campo invalido: %. Use admin ou mesa_rv.', p_campo;
  end if;

  select super into v_super from public.perfis where user_id = p_user_id;
  if v_super is null then
    raise exception 'Perfil nao encontrado.';
  end if;
  if v_super then
    raise exception 'O perfil supremo nao pode ser alterado pela tela.';
  end if;

  if p_campo = 'admin' then
    update public.perfis set admin = p_valor where user_id = p_user_id;
  else
    update public.perfis set mesa_rv = p_valor where user_id = p_user_id;
  end if;

  insert into public.auditoria(usuario, acao, alvo, detalhe)
  values (coalesce(auth.jwt() ->> 'email','?'), 'privilegio',
          (select email from auth.users where id = p_user_id),
          p_campo || ' = ' || p_valor);
end $$;

revoke all on function public.listar_equipe(), public.definir_privilegio(uuid,text,boolean) from public;
grant execute on function public.listar_equipe() to authenticated;
grant execute on function public.definir_privilegio(uuid,text,boolean) to authenticated;
