-- Mi carrito: ESQUEMA COMPLETO de la base de datos (foto del proyecto real de Supabase)
-- Sacado del proyecto "mi-carrito" el 28-11-2026, tras la migración move_device_purchases.
--
-- Para qué sirve:
--   * Es la referencia de cómo es HOY la base de datos. Los supabase.sql, -2, -3 y -4
--     son pasos antiguos y ya no la describen entera.
--   * Se puede pegar entero en Supabase → SQL Editor para montar un proyecto nuevo desde cero.
--     Es repetible: si ya existe algo, lo deja como está o lo pone al día.
--   * Los cambios nuevos van en un archivo nuevo numerado (supabase-6-..., etc.).
--
-- Regla general: nadie lee ni toca las tablas directamente (salvo user_data, que es de cada usuario);
-- todo pasa por las funciones de abajo, que comprueban y recortan lo que llega.

-- =====================================================================
-- 1) TABLAS
-- =====================================================================

-- Precios compartidos entre todos los usuarios.
-- code: código de barras (8-14 cifras), PLU de peso variable (plu:2xxxxxx) o artículo sin código (n:nombre)
create table if not exists public.prices (
  id bigint generated always as identity primary key,
  code text not null,
  name text,
  store text not null,
  price numeric(8,2) not null,
  unit text not null default 'unit',
  device text,
  created_at timestamptz not null default now(),
  constraint prices_code_check check ((code ~ '^[0-9]{8,14}$') or (code ~ '^plu:2[0-9]{6}$') or (code ~ '^n:[a-z0-9ñ ]{3,58}$')),
  constraint prices_name_check check (char_length(name) <= 80),
  constraint prices_store_check check (char_length(store) >= 1 and char_length(store) <= 40),
  constraint prices_price_check check (price > 0 and price < 1000),
  constraint prices_unit_check check (unit in ('unit','kg')),
  constraint prices_device_check check (char_length(device) <= 40)
);
create index if not exists prices_code_idx on public.prices (code, store, created_at desc);
create index if not exists prices_name_idx on public.prices (lower(name));

-- Lista de la compra compartida por familia (se accede sabiendo el código de 10 caracteres)
create table if not exists public.list_items (
  list_code text not null,
  id text not null,
  name text not null,
  price numeric(8,2),
  qty integer not null default 1,
  done boolean not null default false,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  store text,
  primary key (list_code, id),
  constraint list_items_list_code_check check (list_code ~ '^[A-Z0-9]{10}$'),
  constraint list_items_id_check check (char_length(id) <= 40),
  constraint list_items_name_check check (char_length(name) <= 80),
  constraint list_items_qty_check check (qty >= 1 and qty <= 99),
  constraint list_items_store_check check (char_length(store) <= 40)
);

-- Miembros de cada lista familiar (el primero en unirse es el dueño)
create table if not exists public.list_members (
  list_code text not null,
  device text not null,
  name text not null,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (list_code, device),
  constraint list_members_list_code_check check (list_code ~ '^[A-Z0-9]{10}$'),
  constraint list_members_device_check check (char_length(device) <= 40),
  constraint list_members_name_check check (char_length(name) >= 1 and char_length(name) <= 30)
);

-- Compras terminadas de la familia (historial de gasto). Solo las ven los miembros de la lista.
create table if not exists public.purchases (
  list_code text not null,
  id text not null,
  device text not null,
  who text,
  t timestamptz not null,
  store text,
  total numeric,
  paid numeric,
  saved numeric,
  items jsonb not null default '[]'::jsonb,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (list_code, device, id),
  constraint purchases_device_check check (char_length(device) >= 8 and char_length(device) <= 40),
  constraint purchases_who_check check (char_length(who) <= 30),
  constraint purchases_store_check check (char_length(store) <= 40),
  constraint purchases_total_check check (total >= 0 and total < 100000),
  constraint purchases_paid_check check (paid is null or (paid >= 0 and paid < 100000)),
  constraint purchases_items_check check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 400)
);
create index if not exists purchases_code_upd on public.purchases (list_code, updated_at);

-- Copia en la nube de los datos de cada usuario con cuenta (cart.*). Cada uno solo ve lo suyo.
create table if not exists public.user_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  constraint user_data_data_check check (pg_column_size(data) < 5000000)
);

-- Traspaso de sesión de inicio de sesión (web → APK). Caduca a los 10 minutos y se borra al leerlo.
create table if not exists public.auth_handoff (
  n text primary key,
  data jsonb not null,
  created_at timestamptz not null default now(),
  constraint auth_handoff_n_check check (n ~ '^[a-f0-9]{32,64}$'),
  constraint auth_handoff_data_check check (pg_column_size(data) < 20000)
);

-- Errores que manda la app (se guardan 60 días, máximo 100 por dispositivo y día)
create table if not exists public.app_errors (
  id bigint generated always as identity primary key,
  t timestamptz not null default now(),
  device text,
  who text,
  ver text,
  kind text,
  msg text,
  ctx jsonb
);
create index if not exists app_errors_t on public.app_errors (t desc);

-- Foto compartida de cada producto (la imagen está en el bucket "fotos")
create table if not exists public.product_photos (
  key text primary key,
  path text not null,
  device text,
  updated_at timestamptz not null default now(),
  constraint product_photos_key_check check (key ~ '^[a-z0-9-]{3,70}$'),
  constraint product_photos_path_check check (path ~ '^[a-z0-9-]{3,90}\.jpg$')
);

-- =====================================================================
-- 2) SEGURIDAD DE LAS TABLAS
-- =====================================================================

alter table public.prices         enable row level security;
alter table public.list_items     enable row level security;
alter table public.list_members   enable row level security;
alter table public.purchases      enable row level security;
alter table public.user_data      enable row level security;
alter table public.auth_handoff   enable row level security;
alter table public.app_errors     enable row level security;
alter table public.product_photos enable row level security;

-- Sin acceso directo: solo a través de las funciones
revoke all on public.prices, public.list_items, public.list_members, public.purchases,
              public.auth_handoff, public.app_errors, public.product_photos
  from anon, authenticated;

-- user_data: solo usuarios con sesión, y cada uno sus propias filas
revoke all on public.user_data from anon;
grant select, insert, update, delete on public.user_data to authenticated;

drop policy if exists "cada uno ve lo suyo" on public.user_data;
create policy "cada uno ve lo suyo" on public.user_data
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "cada uno guarda lo suyo" on public.user_data;
create policy "cada uno guarda lo suyo" on public.user_data
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "cada uno cambia lo suyo" on public.user_data;
create policy "cada uno cambia lo suyo" on public.user_data
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "cada uno borra lo suyo" on public.user_data;
create policy "cada uno borra lo suyo" on public.user_data
  for delete to authenticated using ((select auth.uid()) = user_id);

-- =====================================================================
-- 3) FOTOS (Storage)
-- =====================================================================

-- Bucket público de fotos de producto: solo JPG de hasta 400 KB
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 400000, array['image/jpeg'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Cualquiera puede subir una foto nueva con nombre válido; nadie puede borrarlas ni cambiarlas
drop policy if exists "subir fotos de productos" on storage.objects;
create policy "subir fotos de productos" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'fotos' and name ~ '^[a-z0-9-]{3,90}\.jpg$');

-- =====================================================================
-- 4) FUNCIONES (la app solo habla con la base de datos a través de estas)
-- =====================================================================

-- ---- Precios ----

-- Añadir un precio (no se puede borrar ni cambiar lo que suban otros)
create or replace function public.add_price(p_code text, p_name text, p_store text, p_price numeric, p_unit text, p_device text)
returns void language sql security definer set search_path = public as $$
  insert into prices(code, name, store, price, unit, device)
  values (p_code, left(p_name, 80), left(p_store, 40), round(p_price, 2), coalesce(p_unit, 'unit'), left(p_device, 40));
$$;

-- Añadir muchos precios de golpe (p. ej. al escanear un ticket). Ignora los repetidos. Máx. 500.
create or replace function public.add_prices(p jsonb)
returns integer language sql security definer set search_path = public as $$
  with r as (
    select left(p_code,60) c, left(coalesce(p_name,''),80) n, left(p_store,40) s, round(p_price,2) pr, case when p_unit='kg' then 'kg' else 'unit' end u, left(p_device,40) d
    from jsonb_to_recordset(case when jsonb_typeof(p)='array' then p else '[]'::jsonb end)
      as x(p_code text, p_name text, p_store text, p_price numeric, p_unit text, p_device text)
    where p_price > 0 and p_price < 1000 and char_length(coalesce(p_store,'')) >= 1
      and (p_code ~ '^[0-9]{8,14}$' or p_code ~ '^plu:2[0-9]{6}$' or p_code ~ '^n:[a-z0-9ñ ]{3,58}$')
    limit 500
  ), ins as (
    insert into prices(code, name, store, price, unit, device)
    select distinct c, n, s, pr, u, d from r
    where not exists (select 1 from prices q where q.code=r.c and q.store=r.s and q.price=r.pr and q.device is not distinct from r.d)
    returning 1
  ) select count(*)::int from ins;
$$;

-- Precios de un producto por tienda (últimos 60 días; el más repetido en cada tienda) y su nombre más usado
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

-- Último precio por tienda de varios productos a la vez (comparar la lista entre súpers). Máx. 80 códigos.
create or replace function public.get_prices_many(p_codes text[])
returns table(code text, store text, price numeric, unit text, last_at timestamptz)
language sql stable security definer set search_path = public as $$
  select distinct on (p.code, lower(p.store)) p.code, p.store, p.price, p.unit, p.created_at
  from prices p
  where p.code = any(p_codes[1:80]) and p.created_at > now() - interval '90 days'
  order by p.code, lower(p.store), p.created_at desc;
$$;

-- Buscar productos por nombre (mín. 3 letras, últimos 120 días, máx. 40 resultados)
create or replace function public.search_products(p_q text)
returns table(code text, name text, store text, price numeric, unit text, last_at timestamptz)
language sql stable security definer set search_path = public as $$
  select distinct on (p.code, p.store) p.code, p.name, p.store, p.price, p.unit, p.created_at
  from prices p
  where char_length(p_q) >= 3
    and p.created_at > now() - interval '120 days'
    and lower(p.name) like '%' || lower(replace(replace(p_q, '%', ''), '_', '')) || '%'
  order by p.code, p.store, p.created_at desc
  limit 40;
$$;

-- Renombrar una tienda, solo en los precios que subió ese mismo dispositivo
create or replace function public.rename_store(p_device text, p_from text, p_to text)
returns integer language sql security definer set search_path = public as $$
  with u as (
    update prices set store = left(p_to, 40)
    where device = p_device and store = p_from and char_length(coalesce(p_to,'')) between 2 and 40 and p_device is not null and char_length(p_device) >= 8
    returning 1
  ) select count(*)::int from u;
$$;

-- ---- Lista de la compra compartida ----

-- Leer los cambios de la lista desde una fecha
create or replace function public.get_list(p_list text, p_since timestamptz)
returns setof public.list_items language sql stable security definer set search_path = public as $$
  select * from list_items where list_code = p_list and updated_at > coalesce(p_since, 'epoch'::timestamptz) order by updated_at;
$$;

-- Guardar cambios de la lista (máx. 200 artículos por llamada). Devuelve la hora del servidor.
create or replace function public.put_list(p_list text, p_items jsonb)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare it jsonb;
begin
  if jsonb_array_length(p_items) > 200 then raise exception 'demasiados'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    insert into list_items(list_code, id, name, price, qty, done, deleted, store, updated_at)
    values (p_list, it->>'id', left(it->>'name', 80), nullif(it->>'price','')::numeric, greatest(1, least(99, coalesce((it->>'qty')::int, 1))),
            coalesce((it->>'done')::boolean, false), coalesce((it->>'deleted')::boolean, false), left(it->>'store', 40), now())
    on conflict (list_code, id) do update set name = excluded.name, price = excluded.price, qty = excluded.qty,
            done = excluded.done, deleted = excluded.deleted, store = coalesce(excluded.store, list_items.store), updated_at = now();
  end loop;
  return now();
end $$;

-- ---- Miembros de la familia ----

create or replace function public.join_list(p_list text, p_device text, p_name text)
returns void language sql security definer set search_path = public as $$
  insert into list_members(list_code, device, name) values (p_list, left(p_device, 40), left(p_name, 30))
  on conflict (list_code, device) do update set name = excluded.name, last_seen = now();
$$;

create or replace function public.leave_list(p_list text, p_device text)
returns void language sql security definer set search_path = public as $$
  delete from list_members where list_code = p_list and device = p_device;
$$;

-- Quién está en la lista, si soy yo y quién es el dueño (el primero que se unió)
create or replace function public.get_members(p_list text, p_device text)
returns table(name text, last_seen timestamptz, me boolean, owner boolean)
language sql stable security definer set search_path = public as $$
  select m.name, m.last_seen, m.device = p_device,
         m.joined_at = (select min(joined_at) from list_members where list_code = p_list)
  from list_members m where m.list_code = p_list order by m.joined_at;
$$;

-- ---- Compras de la familia ----

-- Guardar o actualizar una compra terminada (solo si el dispositivo es miembro de la lista)
create or replace function public.put_purchase(p_list text, p_device text, p jsonb)
returns void language sql security definer set search_path = public as $$
  insert into purchases(list_code, id, device, who, t, store, total, paid, saved, items, deleted, updated_at)
  select p_list, left(p->>'id',40), p_device, left(coalesce((select name from list_members m where m.list_code=p_list and m.device=p_device),''),30),
         to_timestamp((p->>'t')::double precision/1000), left(p->>'store',40), round((p->>'total')::numeric,2),
         case when p ? 'paid' and p->>'paid' is not null then round((p->>'paid')::numeric,2) end,
         round(coalesce((p->>'saved')::numeric,0),2), coalesce(p->'items','[]'::jsonb), coalesce((p->>'deleted')::boolean,false), now()
  where exists (select 1 from list_members m where m.list_code=p_list and m.device=p_device)
  on conflict (list_code, device, id) do update set who=excluded.who, t=excluded.t, store=excluded.store, total=excluded.total, paid=excluded.paid,
    saved=excluded.saved, items=excluded.items, deleted=excluded.deleted, updated_at=now();
$$;

-- Compras de la familia (últimos 400 días, recientes primero). El dispositivo de otros se devuelve ofuscado.
create or replace function public.get_purchases(p_list text, p_device text, p_since timestamptz)
returns table(id text, device text, who text, t timestamptz, store text, total numeric, paid numeric, saved numeric, items jsonb, deleted boolean, updated_at timestamptz, mine boolean)
language sql stable security definer set search_path = public as $$
  select p.id, left(md5(p.device),10), coalesce(m2.name, p.who), p.t, p.store, p.total, p.paid, p.saved, p.items,
         p.deleted or m2.device is null, p.updated_at, p.device = p_device
  from purchases p
  left join list_members m2 on m2.list_code = p.list_code and m2.device = p.device
  where p.list_code = p_list and p.t > now() - interval '400 days' and p.updated_at > coalesce(p_since,'epoch'::timestamptz)
    and exists (select 1 from list_members m where m.list_code=p_list and m.device=p_device)
  order by p.t desc limit 1000;
$$;

-- Pasar las compras de un identificador de dispositivo antiguo al nuevo (p. ej. al iniciar sesión)
create or replace function public.move_device(p_list text, p_old text, p_new text)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if p_old is null or p_new is null or p_old = p_new then return 0; end if;
  if not exists (select 1 from list_members where list_code = p_list and device = p_new) then return 0; end if;
  update purchases p set device = p_new, updated_at = now()
   where p.list_code = p_list and p.device = p_old
     and not exists (select 1 from purchases q where q.list_code = p_list and q.device = p_new and q.id = p.id);
  get diagnostics n = row_count;
  delete from purchases p where p.list_code = p_list and p.device = p_old
     and exists (select 1 from purchases q where q.list_code = p_list and q.device = p_new and q.id = p.id);
  return n;
end $$;

-- ---- Fotos de producto ----

-- Registrar la foto de un producto (solo si el archivo ya está subido al bucket)
create or replace function public.add_photo(p_key text, p_path text, p_device text)
returns void language sql security definer set search_path = public as $$
  insert into product_photos(key, path, device) select p_key, p_path, left(p_device,40)
  where exists (select 1 from storage.objects o where o.bucket_id='fotos' and o.name = p_path)
  on conflict (key) do update set path = excluded.path, device = excluded.device, updated_at = now();
$$;

-- Fotos de varios productos (máx. 60)
create or replace function public.get_photos(p_keys text[])
returns table(key text, path text) language sql stable security definer set search_path = public as $$
  select key, path from product_photos where key = any(p_keys[1:60]);
$$;

-- ---- Cuenta e inicio de sesión ----

-- Dejar la sesión para que la recoja el APK (caduca en 10 minutos)
create or replace function public.put_handoff(p_n text, p_data jsonb)
returns void language sql security definer set search_path = public as $$
  delete from auth_handoff where created_at < now() - interval '10 minutes';
  insert into auth_handoff(n, data) values (p_n, p_data)
  on conflict (n) do nothing;
$$;

-- Recoger la sesión (se borra al leerla)
create or replace function public.take_handoff(p_n text)
returns jsonb language sql security definer set search_path = public as $$
  delete from auth_handoff where n = p_n and created_at > now() - interval '10 minutes' returning data;
$$;

-- Borrar mi cuenta y mis datos (solo con sesión iniciada)
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;
  delete from list_members where device = auth.uid()::text;
  delete from purchases where device = auth.uid()::text;
  delete from auth.users where id = auth.uid();
end $$;

-- ---- Errores de la app ----

-- Guardar errores que manda la app (máx. 30 por llamada y 100 por dispositivo y día; se borran a los 60 días)
create or replace function public.log_errors(p_device text, p jsonb)
returns void language sql security definer set search_path = public as $$
  delete from app_errors where t < now() - interval '60 days';
  insert into app_errors(device, who, ver, kind, msg, ctx)
  select left(p_device,40), left(x->>'who',30), left(x->>'ver',40), left(x->>'kind',20), left(x->>'msg',500),
         case when pg_column_size(x->'ctx') < 4000 then x->'ctx' end
  from jsonb_array_elements(case when jsonb_typeof(p)='array' then p else '[]'::jsonb end) x
  where (select count(*) from app_errors e where e.device = left(p_device,40) and e.t > now() - interval '1 day') < 100
  limit 30;
$$;

-- =====================================================================
-- 5) PERMISOS DE LAS FUNCIONES
-- =====================================================================

revoke all on function
  public.add_price, public.add_prices, public.get_prices, public.get_prices_many, public.search_products, public.rename_store,
  public.get_list, public.put_list, public.join_list, public.leave_list, public.get_members,
  public.put_purchase, public.get_purchases, public.move_device,
  public.add_photo, public.get_photos, public.put_handoff, public.take_handoff,
  public.delete_my_account, public.log_errors
from public;

-- Las usa la app sin cuenta (anon) y con cuenta (authenticated)
grant execute on function
  public.add_price, public.add_prices, public.get_prices, public.get_prices_many, public.search_products, public.rename_store,
  public.get_list, public.put_list, public.join_list, public.leave_list, public.get_members,
  public.put_purchase, public.get_purchases, public.move_device,
  public.add_photo, public.get_photos, public.put_handoff, public.take_handoff,
  public.log_errors
to anon, authenticated;

-- Borrar la cuenta solo con sesión iniciada
grant execute on function public.delete_my_account to authenticated;

-- Nota: el proyecto también tiene la función public.rls_auto_enable() con el event trigger "ensure_rls",
-- que activa RLS automáticamente en cada tabla nueva de public. No se toca desde aquí.
