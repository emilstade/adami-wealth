-- ============================================================
--  Adami Wealth - acesso por assessor
--  Rode este arquivo INTEIRO no SQL Editor do Supabase, de uma vez.
--
--  Administrador: emil.gualter.stade@gmail.com
--  Ele enxerga todos os clientes e recebe a posse de todos os
--  clientes que ja existem. Nao precisa editar nada neste arquivo.
-- ============================================================

create temporary table _cfg as
select 'emil.gualter.stade@gmail.com'::text as email_admin;   -- e-mail do administrador


-- ------------------------------------------------------------
-- 1. Tabela de perfis (quem e assessor, quem e admin)
-- ------------------------------------------------------------
create table if not exists public.perfis (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  nome      text,
  admin     boolean not null default false,
  criado_em timestamptz not null default now()
);

-- todo usuario que ja existe vira um perfil
insert into public.perfis (user_id, nome)
select u.id, coalesce(u.raw_user_meta_data->>'name', split_part(u.email,'@',1))
from auth.users u
on conflict (user_id) do nothing;

-- define o administrador
update public.perfis p set admin = true
from auth.users u, _cfg
where p.user_id = u.id and u.email = _cfg.email_admin;


-- ------------------------------------------------------------
-- 2. Dono de cada cliente
-- ------------------------------------------------------------
alter table public.clientes
  add column if not exists assessor_id uuid references auth.users(id);

-- clientes que ja existem passam para o administrador
update public.clientes c set assessor_id = u.id
from auth.users u, _cfg
where u.email = _cfg.email_admin and c.assessor_id is null;

create index if not exists clientes_assessor_idx on public.clientes(assessor_id);


-- ------------------------------------------------------------
-- 3. Funcao auxiliar: o usuario atual e administrador?
--    security definer para nao entrar em recursao com a RLS
-- ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.admin from public.perfis p where p.user_id = auth.uid()), false);
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;


-- ------------------------------------------------------------
-- 4. RLS: clientes
-- ------------------------------------------------------------
alter table public.clientes enable row level security;

drop policy if exists clientes_sel on public.clientes;
drop policy if exists clientes_ins on public.clientes;
drop policy if exists clientes_upd on public.clientes;
drop policy if exists clientes_del on public.clientes;

create policy clientes_sel on public.clientes for select to authenticated
  using (assessor_id = auth.uid() or public.is_admin());

create policy clientes_ins on public.clientes for insert to authenticated
  with check (assessor_id = auth.uid() or public.is_admin());

create policy clientes_upd on public.clientes for update to authenticated
  using (assessor_id = auth.uid() or public.is_admin())
  with check (assessor_id = auth.uid() or public.is_admin());

create policy clientes_del on public.clientes for delete to authenticated
  using (assessor_id = auth.uid() or public.is_admin());


-- ------------------------------------------------------------
-- 5. RLS: lancamentos (segue o dono do cliente)
-- ------------------------------------------------------------
alter table public.lancamentos enable row level security;

drop policy if exists lanc_all on public.lancamentos;

create policy lanc_all on public.lancamentos for all to authenticated
  using (exists (
    select 1 from public.clientes c
    where c.id = lancamentos.cliente_id
      and (c.assessor_id = auth.uid() or public.is_admin())))
  with check (exists (
    select 1 from public.clientes c
    where c.id = lancamentos.cliente_id
      and (c.assessor_id = auth.uid() or public.is_admin())));


-- ------------------------------------------------------------
-- 6. RLS: perfis (todos leem a lista; so o admin altera)
-- ------------------------------------------------------------
alter table public.perfis enable row level security;

drop policy if exists perfis_sel on public.perfis;
drop policy if exists perfis_upd on public.perfis;

create policy perfis_sel on public.perfis for select to authenticated using (true);

create policy perfis_upd on public.perfis for update to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ------------------------------------------------------------
-- 7. RLS: cartas (comentario do mes e da casa, vale para todos)
-- ------------------------------------------------------------
alter table public.cartas enable row level security;

drop policy if exists cartas_all on public.cartas;

create policy cartas_all on public.cartas for all to authenticated
  using (true) with check (true);


-- ------------------------------------------------------------
-- 8. RLS: auditoria (cada um ve o proprio rastro; admin ve tudo)
-- ------------------------------------------------------------
alter table public.auditoria enable row level security;

drop policy if exists aud_sel on public.auditoria;
drop policy if exists aud_ins on public.auditoria;

create policy aud_sel on public.auditoria for select to authenticated
  using (usuario = (auth.jwt() ->> 'email') or public.is_admin());

create policy aud_ins on public.auditoria for insert to authenticated
  with check (true);


-- ------------------------------------------------------------
-- 9. RLS: backups  << critico
--    O backup e um dump de TODOS os clientes. So o admin acessa.
-- ------------------------------------------------------------
alter table public.backups enable row level security;

drop policy if exists bkp_all on public.backups;

create policy bkp_all on public.backups for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ------------------------------------------------------------
-- 10. Conferencia
-- ------------------------------------------------------------
select p.nome, u.email, p.admin,
       (select count(*) from public.clientes c where c.assessor_id = p.user_id) as clientes
from public.perfis p
join auth.users u on u.id = p.user_id
order by p.admin desc, p.nome;
