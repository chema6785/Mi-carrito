-- Mi carrito: una lista por tienda
alter table public.list_items add column if not exists store text check (char_length(store) <= 40);

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
    insert into list_items(list_code, id, name, price, qty, done, deleted, store, updated_at)
    values (p_list, it->>'id', left(it->>'name', 80), nullif(it->>'price','')::numeric, greatest(1, least(99, coalesce((it->>'qty')::int, 1))),
            coalesce((it->>'done')::boolean, false), coalesce((it->>'deleted')::boolean, false), left(it->>'store', 40), now())
    on conflict (list_code, id) do update set name = excluded.name, price = excluded.price, qty = excluded.qty,
            done = excluded.done, deleted = excluded.deleted, store = coalesce(excluded.store, list_items.store), updated_at = now();
  end loop;
  return now();
end $$;

revoke all on function public.get_list, public.put_list from public;
grant execute on function public.get_list, public.put_list to anon, authenticated;
