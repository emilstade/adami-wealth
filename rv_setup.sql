-- ============================================================
--  Mesa RV — tabelas, permissões e políticas
--  Rodar inteiro no SQL Editor do Supabase.
--  Se aparecer "Potential issues detected", use Run without RLS.
--  Pode rodar mais de uma vez sem quebrar nada.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Quem pode EDITAR a Mesa RV
--    Coluna nova em perfis. Todo mundo já existente entra como
--    false, ou seja, somente leitura, até ser marcado.
-- ------------------------------------------------------------
alter table public.perfis
  add column if not exists mesa_rv boolean not null default false;

-- Função de apoio: responde se o usuário logado pode escrever.
-- security definer para não depender da RLS da própria perfis.
create or replace function public.pode_editar_rv()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.mesa_rv or p.admin from public.perfis p where p.user_id = auth.uid()),
    false);
$$;

revoke all on function public.pode_editar_rv() from public;
grant execute on function public.pode_editar_rv() to authenticated;

-- ------------------------------------------------------------
-- 2. Operações
-- ------------------------------------------------------------
create table if not exists public.rv_operacoes (
  id            uuid primary key default gen_random_uuid(),
  tipo          text        not null,
  ativo         text        not null,
  empresa       text,
  params        jsonb       not null default '{}'::jsonb,
  resumo        text,
  status        text        not null default 'aberta'
                check (status in ('aberta','encerrada')),
  desfecho      text        check (desfecho in ('alvo','stop','manual')),
  resultado_pct numeric,
  criado_por    uuid        references auth.users(id) on delete set null,
  criado_em     timestamptz not null default now(),
  encerrado_em  timestamptz,
  atualizado_em timestamptz not null default now()
);

create index if not exists rv_operacoes_status_idx on public.rv_operacoes(status);
create index if not exists rv_operacoes_ativo_idx  on public.rv_operacoes(upper(ativo));
create index if not exists rv_operacoes_criado_idx on public.rv_operacoes(criado_em desc);

-- ------------------------------------------------------------
-- 3. Alocações por cliente
--    cliente_id aponta para a tabela clientes que já existe.
--    cliente_nome guarda o nome no momento do lançamento, para o
--    histórico não mudar se o cadastro for renomeado depois.
-- ------------------------------------------------------------
create table if not exists public.rv_alocacoes (
  id           uuid primary key default gen_random_uuid(),
  operacao_id  uuid        not null references public.rv_operacoes(id) on delete cascade,
  cliente_id   uuid        references public.clientes(id) on delete set null,
  cliente_nome text        not null,
  valor        numeric     not null check (valor > 0),
  lancado_por  uuid        references auth.users(id) on delete set null,
  em           timestamptz not null default now()
);

create index if not exists rv_alocacoes_op_idx      on public.rv_alocacoes(operacao_id);
create index if not exists rv_alocacoes_cliente_idx on public.rv_alocacoes(cliente_id);

-- ------------------------------------------------------------
-- 4. RLS
--    Leitura: qualquer usuário autenticado.
--    Escrita: somente quem tem mesa_rv ou admin.
-- ------------------------------------------------------------
alter table public.rv_operacoes enable row level security;
alter table public.rv_alocacoes enable row level security;

drop policy if exists rv_op_ler      on public.rv_operacoes;
drop policy if exists rv_op_inserir  on public.rv_operacoes;
drop policy if exists rv_op_alterar  on public.rv_operacoes;
drop policy if exists rv_op_apagar   on public.rv_operacoes;

create policy rv_op_ler     on public.rv_operacoes for select
  to authenticated using (true);
create policy rv_op_inserir on public.rv_operacoes for insert
  to authenticated with check (public.pode_editar_rv());
create policy rv_op_alterar on public.rv_operacoes for update
  to authenticated using (public.pode_editar_rv()) with check (public.pode_editar_rv());
create policy rv_op_apagar  on public.rv_operacoes for delete
  to authenticated using (public.pode_editar_rv());

drop policy if exists rv_al_ler      on public.rv_alocacoes;
drop policy if exists rv_al_inserir  on public.rv_alocacoes;
drop policy if exists rv_al_alterar  on public.rv_alocacoes;
drop policy if exists rv_al_apagar   on public.rv_alocacoes;

create policy rv_al_ler     on public.rv_alocacoes for select
  to authenticated using (true);
create policy rv_al_inserir on public.rv_alocacoes for insert
  to authenticated with check (public.pode_editar_rv());
create policy rv_al_alterar on public.rv_alocacoes for update
  to authenticated using (public.pode_editar_rv()) with check (public.pode_editar_rv());
create policy rv_al_apagar  on public.rv_alocacoes for delete
  to authenticated using (public.pode_editar_rv());

-- ------------------------------------------------------------
-- 5. A mesa precisa enxergar os clientes de todos os assessores
--    Hoje a RLS de clientes mostra só os do próprio assessor.
--    Esta política ADICIONA leitura para quem edita a Mesa RV.
--    Ela não mexe nas políticas que já existem e não dá escrita.
-- ------------------------------------------------------------
drop policy if exists clientes_ler_mesa_rv on public.clientes;
create policy clientes_ler_mesa_rv on public.clientes for select
  to authenticated using (public.pode_editar_rv());

-- ------------------------------------------------------------
-- 6. Carimbo de atualização
-- ------------------------------------------------------------
create or replace function public.rv_touch()
returns trigger language plpgsql as $$
begin
  new.atualizado_em = now();
  return new;
end $$;

drop trigger if exists rv_operacoes_touch on public.rv_operacoes;
create trigger rv_operacoes_touch before update on public.rv_operacoes
  for each row execute function public.rv_touch();

-- ============================================================
--  7. LIBERAR QUEM EDITA  — trocar os e-mails abaixo
-- ============================================================
update public.perfis set mesa_rv = true
where user_id in (
  select id from auth.users
  where lower(email) in (
    'emil@adamiwealth.com.br',      -- <<< confirmar
    'thiago@adamiwealth.com.br'     -- <<< confirmar
  )
);

-- Conferência: quem ficou com poder de escrita
select u.email, p.nome, p.admin, p.mesa_rv
from public.perfis p
join auth.users u on u.id = p.user_id
order by p.mesa_rv desc, p.admin desc, u.email;
