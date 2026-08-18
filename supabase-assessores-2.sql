-- ============================================================
--  Adami Wealth - complemento do acesso por assessor
--
--  Faz com que TODO usuario novo criado no Supabase Auth ganhe
--  automaticamente um perfil de assessor. Sem isto, um assessor
--  criado depois nao aparece na lista de transferencia de cliente.
--
--  Rode uma vez, numa aba nova do SQL Editor.
--  Se aparecer o aviso "Potential issues detected", clique em
--  "Run without RLS" - o motivo e o drop trigger, nao ha risco.
-- ============================================================

create or replace function public.novo_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfis (user_id, nome)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.novo_perfil();

-- garante que ninguem ficou sem perfil
insert into public.perfis (user_id, nome)
select u.id, coalesce(u.raw_user_meta_data->>'name', split_part(u.email,'@',1))
from auth.users u
on conflict (user_id) do nothing;

-- conferencia
select p.nome, u.email, p.admin,
       (select count(*) from public.clientes c where c.assessor_id = p.user_id) as clientes
from public.perfis p
join auth.users u on u.id = p.user_id
order by p.admin desc, p.nome;
