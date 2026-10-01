-- ============================================================
-- GÜNCELLEME — Supabase SQL Editor'da çalıştır
-- ============================================================

-- 1. Personnel tablosuna admin SELECT politikası ekle
drop policy if exists "admin personnel select" on personnel;
create policy "admin personnel select" on personnel
  for select to authenticated
  using (is_admin());

-- 2. admin_personnel RPC — limit yok, tüm veri
create or replace function admin_personnel()
returns table(
  id uuid, employee_no text, full_name text,
  airport text, shift text, active boolean, created_at timestamptz
)
language sql security definer set search_path=public
as $$
  select id, employee_no, full_name, airport, shift, active, created_at
  from personnel
  order by full_name asc;
$$;
revoke all on function admin_personnel() from public;
grant execute on function admin_personnel() to authenticated;
