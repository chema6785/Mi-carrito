-- Mi carrito: base de datos compartida (precios y lista de la compra)
-- Pégalo entero en Supabase → SQL Editor → New query → Run

-- 1) Precios compartidos: cada vez que alguien guarda un precio con código de barras
create table if not exists public.prices (
  id bigint generated always as identity primary key,
  code text not null check (code ~ '^[0-9]{8,14}$'),
  name text check (char_length(name) <= 80),
  store text not null check (char_length(store) between 1 and 40),
  price numeric(8,2) not null check (price > 0 and price < 1000),
  unit text not null default 'unit' check (unit in ('unit','kg')),
  device text check (char_length(device) <= 40),
  created_at timestamptz not null default now()
);
create index if not exists prices_code_idx on public.prices (code, store, created_at desc);

-- 2) Listas compartidas: se accede solo sabiendo el código de familia
create table if not exists public.list_items (
  list_code text not null check (list_code ~ '^[A-Z0-9]{10}$'),
  id text not null check (char_length(id) <= 40),
  name text not null check (char_length(name) <= 80),
  price numeric(8,2),
  qty int not null default 1 check (qty between 1 and 99),
  done boolean not null default false,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (list_code, id)
);

-- Nadie puede leer ni tocar las tablas directamente; solo a través de las funciones de abajo
alter table public.prices enable row level security;
alter table public.list_items enable row level security;
revoke all on public.prices, public.list_items from anon, authenticated;

-- Añadir un precio (no se puede borrar ni cambiar lo que suban otros)
create or replace function public.add_price(p_code text, p_name text, p_store text, p_price numeric, p_unit text, p_device text)
returns void language sql security definer set search_path = public as $$
  insert into prices(code, name, store, price, unit, device)
  values (p_code, left(p_name, 80), left(p_store, 40), round(p_price, 2), coalesce(p_unit, 'unit'), left(p_device, 40));
$$;

-- Consultar un código: nombre más repetido y, por tienda, el precio más repetido de los últimos 60 días
create or replace function public.get_prices(p_code text)
returns table(store text, price numeric, unit text, n bigint, last_at timestamptz, name text)
language sql stable security definer set search_path = public as $$
  with r as (
    select * from prices where code = p_code and created_at > now() - interval '60 days'
  ), nm as (
    select name from prices where code = p_code and name is not null and name <> ''
    group by name order by count(*) desc limit 1
  ), per as (
    select store, price, unit, count(*) c, max(created_at) m from r group by store, price, unit
  )
  select distinct on (per.store) per.store, per.price, per.unit,
         (select count(*) from r where r.store = per.store), (select max(created_at) from r where r.store = per.store),
         (select name from nm)
  from per order by per.store, per.c desc, per.m desc;
$$;

-- Lista compartida: leer los cambios desde una fecha y guardar cambios
create or replace function public.get_list(p_list text, p_since timestamptz)
returns setof list_items language sql stable security definer set search_path = public as $$
  select * from list_items where list_code = p_list and updated_at > coalesce(p_since, 'epoch'::timestamptz) order by updated_at;
$$;

create or replace function public.put_list(p_list text, p_items jsonb)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare it jsonb;
begin
  if jsonb_array_length(p_items) > 200 then raise exception 'demasiados'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    insert into list_items(list_code, id, name, price, qty, done, deleted, updated_at)
    values (p_list, it->>'id', left(it->>'name', 80), nullif(it->>'price','')::numeric, greatest(1, least(99, coalesce((it->>'qty')::int, 1))),
            coalesce((it->>'done')::boolean, false), coalesce((it->>'deleted')::boolean, false), now())
    on conflict (list_code, id) do update set name = excluded.name, price = excluded.price, qty = excluded.qty,
            done = excluded.done, deleted = excluded.deleted, updated_at = now();
  end loop;
  return now();
end $$;

revoke all on function public.add_price, public.get_prices, public.get_list, public.put_list from public;
grant execute on function public.add_price, public.get_prices, public.get_list, public.put_list to anon, authenticated;
