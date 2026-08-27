-- ============================================================
--  ADAMI WEALTH — recriação completa do banco
--  Rodar UMA VEZ, inteiro, no SQL Editor do projeto NOVO.
--  Se aparecer "Potential issues detected", use Run without RLS.
--  Pode rodar de novo sem quebrar (tudo é if not exists / or replace).
-- ============================================================

-- ------------------------------------------------------------
--  0. Funções de apoio
--     security definer para que as políticas possam consultar
--     perfis sem cair em recursão de RLS.
-- ------------------------------------------------------------
create table if not exists public.perfis (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nome    text,
  admin   boolean not null default false,
  mesa_rv boolean not null default false
);

create or replace function public.eh_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin from public.perfis p where p.user_id = auth.uid()), false);
$$;

create or replace function public.pode_editar_rv()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.mesa_rv or p.admin from public.perfis p where p.user_id = auth.uid()), false);
$$;

revoke all on function public.eh_admin(), public.pode_editar_rv() from public;
grant execute on function public.eh_admin(), public.pode_editar_rv() to authenticated;

-- Perfil criado automaticamente para todo usuário novo
create or replace function public.criar_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis(user_id, nome)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email,'@',1)))
  on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.criar_perfil();

-- ------------------------------------------------------------
--  1. Clientes
-- ------------------------------------------------------------
create table if not exists public.clientes (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  assessor_id uuid default auth.uid() references auth.users(id) on delete set null,
  criado_em   timestamptz not null default now()
);
create index if not exists clientes_assessor_idx on public.clientes(assessor_id);

-- quem é dono do cliente (usado pelas políticas de lancamentos)
create or replace function public.meu_cliente(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.clientes c
    where c.id = cid and (c.assessor_id = auth.uid() or public.eh_admin()));
$$;
revoke all on function public.meu_cliente(uuid) from public;
grant execute on function public.meu_cliente(uuid) to authenticated;

-- ------------------------------------------------------------
--  2. Lançamentos mensais
--     A unicidade por (cliente, mês, ano) é OBRIGATÓRIA: o portal
--     grava com ?on_conflict=cliente_id,mes,ano. Sem ela a gravação
--     falha em silêncio.
-- ------------------------------------------------------------
create table if not exists public.lancamentos (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes(id) on delete cascade,
  mes           smallint not null check (mes between 1 and 12),
  ano           smallint not null check (ano between 2000 and 2100),
  contas        jsonb not null default '[]'::jsonb,
  indicadores   jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now(),
  constraint lancamentos_unico unique (cliente_id, mes, ano)
);
create index if not exists lancamentos_periodo_idx on public.lancamentos(ano, mes);

-- ------------------------------------------------------------
--  3. Comentários do mês (compartilhados por toda a casa)
--     Unicidade por (mês, ano): o portal usa ?on_conflict=mes,ano
-- ------------------------------------------------------------
create table if not exists public.cartas (
  id            bigint generated always as identity primary key,
  mes           smallint not null check (mes between 1 and 12),
  ano           smallint not null check (ano between 2000 and 2100),
  conteudo      text,
  atualizado_em timestamptz not null default now(),
  constraint cartas_unico unique (mes, ano)
);

-- ------------------------------------------------------------
--  4. Auditoria
-- ------------------------------------------------------------
create table if not exists public.auditoria (
  id      bigint generated always as identity primary key,
  quando  timestamptz not null default now(),
  usuario text,
  acao    text,
  alvo    text,
  detalhe text
);
create index if not exists auditoria_quando_idx on public.auditoria(quando desc);

-- ------------------------------------------------------------
--  5. Backups (dump completo — exclusivo do admin)
-- ------------------------------------------------------------
create table if not exists public.backups (
  id       bigint generated always as identity primary key,
  quando   timestamptz not null default now(),
  usuario  text,
  conteudo jsonb not null
);
create index if not exists backups_quando_idx on public.backups(quando desc);

-- ------------------------------------------------------------
--  6. Mesa RV
-- ------------------------------------------------------------
create table if not exists public.rv_operacoes (
  id            uuid primary key default gen_random_uuid(),
  tipo          text not null,
  ativo         text not null,
  empresa       text,
  params        jsonb not null default '{}'::jsonb,
  resumo        text,
  status        text not null default 'aberta' check (status in ('aberta','encerrada')),
  desfecho      text check (desfecho in ('alvo','stop','manual')),
  resultado_pct numeric,
  criado_por    uuid references auth.users(id) on delete set null,
  criado_em     timestamptz not null default now(),
  encerrado_em  timestamptz,
  atualizado_em timestamptz not null default now()
);
create index if not exists rv_operacoes_status_idx on public.rv_operacoes(status);
create index if not exists rv_operacoes_criado_idx on public.rv_operacoes(criado_em desc);

create table if not exists public.rv_alocacoes (
  id           uuid primary key default gen_random_uuid(),
  operacao_id  uuid not null references public.rv_operacoes(id) on delete cascade,
  cliente_id   uuid references public.clientes(id) on delete set null,
  cliente_nome text not null,
  valor        numeric not null check (valor > 0),
  lancado_por  uuid references auth.users(id) on delete set null,
  em           timestamptz not null default now()
);
create index if not exists rv_alocacoes_op_idx on public.rv_alocacoes(operacao_id);

create or replace function public.rv_touch()
returns trigger language plpgsql as $$
begin new.atualizado_em = now(); return new; end $$;
drop trigger if exists rv_operacoes_touch on public.rv_operacoes;
create trigger rv_operacoes_touch before update on public.rv_operacoes
  for each row execute function public.rv_touch();

-- ============================================================
--  7. ROW LEVEL SECURITY
-- ============================================================
alter table public.perfis       enable row level security;
alter table public.clientes     enable row level security;
alter table public.lancamentos  enable row level security;
alter table public.cartas       enable row level security;
alter table public.auditoria    enable row level security;
alter table public.backups      enable row level security;
alter table public.rv_operacoes enable row level security;
alter table public.rv_alocacoes enable row level security;

-- perfis: cada um vê o seu; admin vê todos
drop policy if exists perfis_ler on public.perfis;
drop policy if exists perfis_alterar on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (user_id = auth.uid() or public.eh_admin());
create policy perfis_alterar on public.perfis for update to authenticated
  using (user_id = auth.uid() or public.eh_admin())
  with check (user_id = auth.uid() or public.eh_admin());

-- clientes: cada assessor vê os seus; admin vê todos; a mesa RV lê todos
drop policy if exists clientes_ler on public.clientes;
drop policy if exists clientes_inserir on public.clientes;
drop policy if exists clientes_alterar on public.clientes;
drop policy if exists clientes_apagar on public.clientes;
create policy clientes_ler on public.clientes for select to authenticated
  using (assessor_id = auth.uid() or public.eh_admin() or public.pode_editar_rv());
create policy clientes_inserir on public.clientes for insert to authenticated
  with check (assessor_id = auth.uid() or public.eh_admin());
create policy clientes_alterar on public.clientes for update to authenticated
  using (assessor_id = auth.uid() or public.eh_admin())
  with check (assessor_id = auth.uid() or public.eh_admin());
create policy clientes_apagar on public.clientes for delete to authenticated
  using (assessor_id = auth.uid() or public.eh_admin());

-- lancamentos: seguem o dono do cliente
drop policy if exists lanc_ler on public.lancamentos;
drop policy if exists lanc_inserir on public.lancamentos;
drop policy if exists lanc_alterar on public.lancamentos;
drop policy if exists lanc_apagar on public.lancamentos;
create policy lanc_ler on public.lancamentos for select to authenticated
  using (public.meu_cliente(cliente_id));
create policy lanc_inserir on public.lancamentos for insert to authenticated
  with check (public.meu_cliente(cliente_id));
create policy lanc_alterar on public.lancamentos for update to authenticated
  using (public.meu_cliente(cliente_id)) with check (public.meu_cliente(cliente_id));
create policy lanc_apagar on public.lancamentos for delete to authenticated
  using (public.meu_cliente(cliente_id));

-- cartas: comentário é da casa, liberado a todos os autenticados
drop policy if exists cartas_tudo on public.cartas;
create policy cartas_tudo on public.cartas for all to authenticated
  using (true) with check (true);

-- auditoria: cada um vê o próprio rastro; admin vê tudo; só admin limpa
drop policy if exists aud_ler on public.auditoria;
drop policy if exists aud_inserir on public.auditoria;
drop policy if exists aud_apagar on public.auditoria;
create policy aud_ler on public.auditoria for select to authenticated
  using (public.eh_admin() or usuario = (auth.jwt() ->> 'email'));
create policy aud_inserir on public.auditoria for insert to authenticated
  with check (true);
create policy aud_apagar on public.auditoria for delete to authenticated
  using (public.eh_admin());

-- backups: exclusivo do admin, contém dump de todos os assessores
drop policy if exists backups_admin on public.backups;
create policy backups_admin on public.backups for all to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

-- Mesa RV: todos leem, só a mesa escreve
drop policy if exists rv_op_ler on public.rv_operacoes;
drop policy if exists rv_op_escrever on public.rv_operacoes;
create policy rv_op_ler on public.rv_operacoes for select to authenticated using (true);
create policy rv_op_escrever on public.rv_operacoes for all to authenticated
  using (public.pode_editar_rv()) with check (public.pode_editar_rv());

drop policy if exists rv_al_ler on public.rv_alocacoes;
drop policy if exists rv_al_escrever on public.rv_alocacoes;
create policy rv_al_ler on public.rv_alocacoes for select to authenticated using (true);
create policy rv_al_escrever on public.rv_alocacoes for all to authenticated
  using (public.pode_editar_rv()) with check (public.pode_editar_rv());

-- ------------------------------------------------------------
--  8. Permissões de tabela para a API
-- ------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on
  public.perfis, public.clientes, public.lancamentos, public.cartas,
  public.auditoria, public.backups, public.rv_operacoes, public.rv_alocacoes
  to authenticated;

-- ============================================================
--  9. CONFERÊNCIA
-- ============================================================
select table_name,
       (select count(*) from pg_policies p
        where p.schemaname='public' and p.tablename=t.table_name) as politicas
from information_schema.tables t
where table_schema='public' and table_type='BASE TABLE'
order by table_name;
