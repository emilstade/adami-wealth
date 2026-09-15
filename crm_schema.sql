-- =============================================================
-- Pipeline CRM — Adami Wealth
-- schema.sql v2 — estado final consolidado
--
-- Substitui o schema base e as migrações 1 a 21 — inclusive a 15
-- (temperatura), a 16 (offshore + configuracoes), a 17 (conta offshore), a
-- 18 (saldo sob gestão da base), a 19 (captação em negociação da base), a
-- 20 (saldo offshore sob gestão) e a 21 (custódia da captação), que já estão
-- aqui. NÃO
-- rode nenhuma migração numerada depois deste arquivo; a única exceção é a
-- 14, que é DADO (os convites dos assessores), não estrutura.
--
-- Rode este arquivo inteiro, uma vez, no SQL Editor de um projeto Supabase
-- VAZIO. É idempotente no sentido de poder rodar de novo num banco que ele
-- mesmo criou.
--
-- ATENÇÃO — ele NÃO migra um banco que já existe com a forma antiga. Todas
-- as tabelas são `create table if not exists` e não há um `alter table add
-- column` sequer: contra um banco já povoado com o schema v1, ele passa
-- direto por `leads` e `profiles`, cria só o que falta, não acusa erro
-- nenhum e deixa o app quebrado na primeira leitura. Projeto vazio, sempre.
--
-- Consolidado em vez de replicado porque migração incremental carrega
-- o remendo da anterior: a v1 nasceu com um papel só ('vendedor'),
-- valores em texto e políticas que conheciam um dono por negócio. Num
-- banco vazio não há motivo para reconstituir esse caminho.
-- =============================================================

-- -------------------------------------------------------------
-- 1. PERFIS
-- auth.users guarda e-mail e senha (gerenciado pelo Supabase).
-- profiles guarda o que é do nosso domínio: nome, papel e situação.
--
-- 'vendedor' é o assessor. O nome ficou do CRM comercial anterior e é
-- mantido de propósito: renomear agora exigiria tocar o app inteiro
-- (ROTULO_PAPEL já traduz para 'assessor' na tela) sem ganho real.
-- -------------------------------------------------------------
create table if not exists public.profiles (
  id                   uuid primary key references auth.users(id) on delete cascade,
  nome                 text not null,
  role                 text not null default 'vendedor'
                         check (role in ('admin','vendedor','especialista')),
  status               text not null default 'pendente'
                         check (status in ('pendente','ativo','removido')),
  -- Produtos só fazem sentido para especialista; é o que decide quem
  -- aparece como destino no encaminhamento da R4.
  produtos             text[] not null default '{}',
  -- Dupla habitual do assessor por produto: {"Consórcio":"<uuid>"}.
  -- jsonb porque é um mapa lido junto com o perfil, nunca consultado.
  especialistas_padrao jsonb  not null default '{}'::jsonb,
  criado_em            timestamptz not null default now()
);

-- -------------------------------------------------------------
-- 2. NEGÓCIOS
-- Uma tabela para os dois funis. A coluna `funil` separa a jornada do
-- assessor (R1→R4) do processo do especialista (Cliente Novo→Contato
-- Futuro); `origem_lead_id` liga a indicação ao cliente que a gerou.
--
-- Campos consultáveis viram colunas; histórico, atividades, alertas,
-- pautas, briefing e movimentações ficam em jsonb porque são listas que
-- só lemos junto com o lead.
--
-- O id é texto porque o app gera o identificador antes de gravar (uid()),
-- o que permite montar a tela sem esperar o banco responder.
-- -------------------------------------------------------------
create table if not exists public.leads (
  id               text primary key,
  cliente          text not null default '',
  oportunidade     text default '',
  telefone         text default '',
  email            text default '',
  observacoes      text default '',
  responsavel_id   uuid references public.profiles(id) on delete set null,

  -- Etapa não tem check: os estágios válidos dependem do funil e mudam
  -- com o processo comercial. A regra de trajeto vive em allowedMoves,
  -- no app, onde ela pode evoluir sem migração.
  etapa            text not null default 'Cliente Novo',
  etapa_desde      timestamptz not null default now(),
  funil            text not null default 'assessor'
                     check (funil in ('assessor','especialista')),
  esteira          text not null default 'novo'
                     check (esteira in ('novo','base')),
  segmento         text not null default 'Advisory'
                     check (segmento in ('Advisory','Exclusive','Private')),
  produto          text check (produto in ('Consórcio','Seguro')),
  origem_lead_id   text references public.leads(id) on delete set null,

  -- Dinheiro em numeric, não em texto. Em texto o parseValor devolvia 0
  -- para entrada inválida, então patrimônio digitado errado entrava como
  -- zero e sumia dos indicadores sem avisar; e a ordenação por valor era
  -- alfabética ('900000' > '1500000'). Aqui o banco recusa lixo e permite
  -- somar do lado do servidor quando a carteira crescer.
  valor_potencial  numeric(15,2),
  valor_fechado    numeric(15,2),
  -- Patrimônio sob gestão no exterior, em DÓLAR. O mesmo cliente pode ter as
  -- duas custódias; são dois saldos de um relacionamento só, não dois
  -- clientes. Não é convertido na gravação de propósito: converter na entrada
  -- apagaria o valor original e o número envelheceria sem que ninguém soubesse
  -- por qual cotação passou. A conversão acontece na leitura, pela cotação em
  -- configuracoes.usd_brl.
  valor_offshore   numeric(14,2),

  ultimo_contato   date,
  proximo_contato  date,
  produto_servico  text default '',

  perdido          boolean not null default false,
  motivo_perda     text default '',
  perdido_em       timestamptz,
  ganho            boolean not null default false,
  ganho_em         timestamptz,
  excluido         boolean not null default false,
  excluido_em      timestamptz,

  -- Ficha do cliente
  tipo_pessoa      text not null default 'PF' check (tipo_pessoa in ('PF','PJ')),
  contato_nome     text,
  contato_cargo    text,
  nascimento       date,
  grupo_familiar   text,
  -- Temperatura é leitura de engajamento, não de etapa: um cliente pode estar
  -- na R2 e frio. Fica nula enquanto ninguém classificou — um default daria a
  -- toda a base carregada uma leitura que ninguém fez.
  temperatura      text check (temperatura is null or temperatura in ('quente','morno','frio')),
  estado_civil     text,
  profissao        text,
  banco_atual      text,
  origem           text,
  -- Número da conta no BTG. Só existe em cliente que veio da carga da base;
  -- quem é cadastrado pelo app não tem conta, e por isso o índice único é
  -- parcial (ver importacao-base-btg.sql). É a chave de reconciliação: sem
  -- ela, uma reimportação não sabe distinguir atualização de duplicata.
  conta            text,
  -- A conta offshore do mesmo cliente (migração 17). Não é chave: o export
  -- offshore do BTG liga pela conta onshore, que está ao lado dela no arquivo.
  conta_offshore   text,
  -- Cliente da base: saldo sob gestão antes das movimentações (migração 18).
  -- Separado de valor_potencial, que é o patrimônio do formulário — eram o
  -- mesmo campo, e corrigir o patrimônio mexia na carteira.
  saldo_inicial    numeric(14,2),
  -- Cliente da base: captação nova em negociação (migração 19). Entra em
  -- "Em captação" com o potencial dos prospects; o aporte abate daqui.
  valor_em_captacao numeric(14,2),
  -- Custódia e moeda do valor acima (migração 21): onshore = BRL, offshore = USD.
  captacao_custodia text check (captacao_custodia is null or captacao_custodia in ('onshore','offshore')),
  -- Saldo offshore sob gestão, em USD (migração 20). valor_offshore é só o
  -- patrimônio offshore declarado; o que vale para a carteira é o captado.
  saldo_inicial_offshore numeric(14,2),
  -- Patrimônio e renda declarados no briefing de seguro são texto livre
  -- ("2 imóveis + previdência"), nunca somados. Ficam como texto de
  -- propósito, ao contrário das colunas de valor acima.
  patrimonio       text,
  renda            text,

  historico        jsonb not null default '[]'::jsonb,
  atividades       jsonb not null default '[]'::jsonb,
  alertas          jsonb not null default '[]'::jsonb,
  movimentacoes    jsonb not null default '[]'::jsonb,
  briefing         jsonb not null default '{}'::jsonb,
  pautas           jsonb not null default '{}'::jsonb,

  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),

  -- Ganho e perdido são desfechos opostos; o app já os trata como
  -- exclusivos e o banco passa a garantir isso.
  constraint leads_desfecho_exclusivo check (not (ganho and perdido))
);

create index if not exists leads_responsavel_idx on public.leads (responsavel_id);
create index if not exists leads_etapa_idx       on public.leads (etapa);
create index if not exists leads_funil_idx       on public.leads (funil);
-- As políticas de encaminhamento buscam por origem_lead_id a cada linha
-- lida; sem índice isso vira varredura da tabela inteira.
create index if not exists leads_origem_idx      on public.leads (origem_lead_id)
  where origem_lead_id is not null;
create index if not exists leads_ativos_idx      on public.leads (excluido) where excluido = false;
create index if not exists leads_grupo_idx       on public.leads (grupo_familiar)
  where grupo_familiar is not null;
-- Parcial: a pergunta é "quem tem carteira lá fora", nunca "quem não tem".
create index if not exists leads_offshore_idx    on public.leads (valor_offshore)
  where valor_offshore is not null;
-- Parcial: a pergunta é sempre "quem está quente", nunca "quem está sem
-- classificação" na base inteira.
create index if not exists leads_temperatura_idx on public.leads (temperatura)
  where temperatura is not null;
-- Único e parcial: duas linhas não podem representar a mesma conta do BTG, mas
-- os clientes cadastrados na mão ficam todos com conta nula e não colidem.
create unique index if not exists leads_conta_uk  on public.leads (conta)
  where conta is not null;
create unique index if not exists leads_conta_offshore_uk on public.leads (conta_offshore)
  where conta_offshore is not null;

-- -------------------------------------------------------------
-- 3. CONVITES
-- Criar a conta de outra pessoa pelo navegador exigiria a chave de
-- serviço, que não pode ficar no código. O convite resolve: o admin
-- pré-define nome, papel e produtos; a pessoa se cadastra com aquele
-- e-mail e escolhe a própria senha.
--
-- O e-mail é guardado normalizado em minúsculas porque o casamento no
-- gatilho é case-insensitive: sem isso, 'Ana@x.com' e 'ana@x.com'
-- coexistiriam como convites distintos e o gatilho escolheria um deles
-- por acaso.
-- -------------------------------------------------------------
create table if not exists public.convites (
  email       text primary key check (email = lower(email)),
  nome        text not null,
  role        text not null default 'vendedor'
                check (role in ('admin','vendedor','especialista')),
  produtos    text[] not null default '{}',
  criado_por  uuid references public.profiles(id) on delete set null,
  criado_em   timestamptz not null default now()
);

-- -------------------------------------------------------------
-- 4. FUNÇÕES DE APOIO
-- SECURITY DEFINER é essencial: sem isso, uma política sobre uma tabela
-- que consulta a mesma tabela entra em recursão infinita.
-- -------------------------------------------------------------
create or replace function public.is_ativo()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'ativo'
  );
$$;

create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status = 'ativo'
  );
$$;

-- Este negócio é meu?
create or replace function public.lead_meu(p_id text)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.leads
    where id = p_id and responsavel_id = auth.uid()
  );
$$;

-- Alguma indicação minha nasceu deste negócio?
create or replace function public.lead_origem_minha(p_id text)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.leads
    where origem_lead_id = p_id and responsavel_id = auth.uid()
  );
$$;

-- -------------------------------------------------------------
-- 5. CRIAÇÃO AUTOMÁTICA DE PERFIL
-- Com convite, a pessoa entra já liberada, no papel definido pelo admin.
-- Sem convite, a primeira conta do sistema vira admin ativa — senão
-- ninguém conseguiria aprovar ninguém — e as demais nascem pendentes.
-- -------------------------------------------------------------
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
    values (new.id, convite.nome, convite.role, 'ativo', convite.produtos);
    delete from public.convites where email = convite.email;
  else
    insert into public.profiles (id, nome, role, status)
    values (
      new.id,
      coalesce(nullif(new.raw_user_meta_data->>'nome',''), split_part(new.email, '@', 1)),
      case when primeiro then 'admin' else 'vendedor' end,
      case when primeiro then 'ativo' else 'pendente' end
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -------------------------------------------------------------
-- 6. TROCA DE DONO
-- A RLS trabalha por linha, não por coluna: quem pode gravar na linha
-- pode gravar em qualquer campo dela. O especialista alcança o cliente
-- de origem para concluir a jornada (seção 7) e poderia, na mesma
-- escrita, apontar responsavel_id para si e tomar a carteira do
-- assessor. Redesignar cliente é ato de administração.
-- -------------------------------------------------------------
create or replace function public.protege_responsavel()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.responsavel_id is distinct from old.responsavel_id
     and not public.is_admin() then
    raise exception 'Somente um administrador pode transferir a responsabilidade de um negócio.';
  end if;
  return new;
end;
$$;

drop trigger if exists leads_protege_responsavel on public.leads;
create trigger leads_protege_responsavel
  before update on public.leads
  for each row execute function public.protege_responsavel();

-- -------------------------------------------------------------
-- 7. SEGURANÇA EM NÍVEL DE LINHA
-- A chave anônima fica no HTML, à vista de qualquer um. As regras aqui
-- são a única barreira real — não confie no front. O app faz
-- `select('*')` sem filtro: quem recorta a carteira é esta seção.
-- -------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.leads    enable row level security;
alter table public.convites enable row level security;

-- Perfis ---------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  -- Quem está ativo vê a equipe (precisa disso para exibir responsáveis).
  -- Quem está pendente enxerga só o próprio registro, para saber que aguarda.
  using ( id = auth.uid() or public.is_ativo() );

-- O USING só garante que a linha é a própria. Sem prender as colunas
-- sensíveis no WITH CHECK, uma conta pendente rodaria
--   update profiles set status='ativo' where id = auth.uid()
-- e entraria sem passar por nenhum admin — a aprovação viraria
-- decorativa. Mesmo raciocínio para produtos: um especialista se
-- atribuiria produtos e passaria a receber indicação que não é dele.
-- Nome e preferências seguem editáveis pelo próprio dono.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using ( id = auth.uid() )
  with check (
    id = auth.uid()
    and role     = (select role     from public.profiles where id = auth.uid())
    and status   = (select status   from public.profiles where id = auth.uid())
    and produtos = (select produtos from public.profiles where id = auth.uid())
  );

drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles
  for update to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );

-- Negócios -------------------------------------------------------
-- A indicação da R4 tem dois lados: o assessor cria o card e o
-- especialista o executa. O vínculo é sempre origem_lead_id, nunca uma
-- permissão ampla — cada lado alcança só o negócio ligado ao seu.
drop policy if exists leads_select on public.leads;
create policy leads_select on public.leads
  for select to authenticated
  using (
    public.is_admin()
    or (public.is_ativo() and responsavel_id = auth.uid())
    -- assessor lê a indicação gerada a partir de um cliente da carteira dele:
    -- sem isto semIndicacao ficaria pendente para sempre e jornadaConcluida
    -- nunca dispararia
    or (public.is_ativo() and origem_lead_id is not null and public.lead_meu(origem_lead_id))
    -- especialista lê o cliente de origem da indicação que recebeu
    or (public.is_ativo() and public.lead_origem_minha(id))
  );

drop policy if exists leads_insert on public.leads;
create policy leads_insert on public.leads
  for insert to authenticated
  with check (
    public.is_admin()
    or (public.is_ativo() and responsavel_id = auth.uid())
    -- o assessor cria a indicação em nome do especialista, mas só a partir
    -- de um cliente que já é dele: origem_lead_id é a credencial do ato
    or (
      public.is_ativo()
      and funil = 'especialista'
      and origem_lead_id is not null
      and public.lead_meu(origem_lead_id)
    )
  );

-- Escrita é mais estreita que leitura: o assessor lê a indicação para
-- saber em que pé ela está, mas quem a trabalha é o especialista. Na
-- volta, o especialista escreve no cliente de origem apenas porque a
-- conclusão automática da jornada precisa gravar a etapa lá.
drop policy if exists leads_update on public.leads;
create policy leads_update on public.leads
  for update to authenticated
  using (
    public.is_admin()
    or (public.is_ativo() and responsavel_id = auth.uid())
    or (public.is_ativo() and public.lead_origem_minha(id))
  )
  with check (
    public.is_admin()
    or (public.is_ativo() and responsavel_id = auth.uid())
    or (public.is_ativo() and public.lead_origem_minha(id))
  );

-- Exclusão é lógica (coluna excluido). Nenhuma política de DELETE,
-- então nada some do banco de verdade pelo aplicativo.

-- Convites -------------------------------------------------------
drop policy if exists convites_admin on public.convites;
create policy convites_admin on public.convites
  for all to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );

-- -------------------------------------------------------------
-- 8. TEMPO REAL
-- Permite que a tela de um assessor reaja à alteração feita por outro.
-- A entrega respeita a RLS acima: cada assinante recebe apenas o que
-- teria direito de ler por select.
-- -------------------------------------------------------------
-- ============================================================
-- Configurações do escritório
-- ============================================================
-- Hoje guarda uma linha só: a cotação do dólar usada para consolidar o
-- offshore. É decisão do escritório e não cotação de mercado buscada na hora —
-- dois relatórios do mesmo dia têm de dar o mesmo número. Chave/valor em vez
-- de coluna porque a próxima configuração não deve exigir outra migração.
create table if not exists public.configuracoes (
  chave          text primary key,
  valor          text not null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.profiles(id) on delete set null
);

alter table public.configuracoes enable row level security;

-- Todo mundo lê: sem a cotação nenhuma tela consolida a carteira.
drop policy if exists configuracoes_leitura on public.configuracoes;
create policy configuracoes_leitura on public.configuracoes
  for select to authenticated
  using ( true );

-- Só o admin escreve: a cotação move o total da carteira do escritório
-- inteiro, não é decisão de quem cuida de uma carteira só.
drop policy if exists configuracoes_admin on public.configuracoes;
create policy configuracoes_admin on public.configuracoes
  for all to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );

-- Quem gravou é carimbado pelo banco, não pelo app: o cliente poderia mandar
-- qualquer uuid nesse campo.
create or replace function public.configuracoes_carimba()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.atualizado_por := auth.uid();
  new.atualizado_em  := now();
  return new;
end $$;

drop trigger if exists configuracoes_carimba_trg on public.configuracoes;
create trigger configuracoes_carimba_trg
  before insert or update on public.configuracoes
  for each row execute function public.configuracoes_carimba();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'leads'
  ) then
    alter publication supabase_realtime add table public.leads;
  end if;
end $$;
