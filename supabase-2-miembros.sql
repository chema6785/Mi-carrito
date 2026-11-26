-- Mi carrito: quién está en cada lista compartida
create table if not exists public.list_members (
  list_code text not null check (list_code ~ '^[A-Z0-9]{10}$'),
  device text not null check (char_length(device) <= 40),
  name text not null check (char_length(name) between 1 and 30),
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (list_code, device)
);
alter table public.list_members enable row level security;
revoke all on public.list_members from anon, authenticated;

create or replace function public.join_list(p_list text, p_device text, p_name text)
returns void language sql security definer set search_path = public as $$
  insert into list_members(list_code, device, name) values (p_list, left(p_device, 40), left(p_name, 30))
  on conflict (list_code, device) do update set name = excluded.name, last_seen = now();
$$;

create or replace function public.leave_list(p_list text, p_device text)
returns void language sql security definer set search_path = public as $$
  delete from list_members where list_code = p_list and device = p_device;
$$;

create or replace function public.get_members(p_list text, p_device text)
returns table(name text, last_seen timestamptz, me boolean, owner boolean)
language sql stable security definer set search_path = public as $$
  select m.name, m.last_seen, m.device = p_device,
         m.joined_at = (select min(joined_at) from list_members where list_code = p_list)
  from list_members m where m.list_code = p_list order by m.joined_at;
$$;

revoke all on function public.join_list, public.leave_list, public.get_members from public;
grant execute on function public.join_list, public.leave_list, public.get_members to anon, authenticated;
