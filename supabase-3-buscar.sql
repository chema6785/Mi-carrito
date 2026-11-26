-- Mi carrito: buscar productos compartidos por nombre
create index if not exists prices_name_idx on public.prices (lower(name));

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

revoke all on function public.search_products from public;
grant execute on function public.search_products to anon, authenticated;
