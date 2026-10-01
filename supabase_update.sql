-- ============================================================
-- GÜNCELLEME — Supabase SQL Editor'da çalıştır
-- ============================================================

-- admin_personnel — tüm personeli limit olmadan döndürür
create or replace function admin_personnel()
returns table(
  id uuid, employee_no text, full_name text,
  airport text, shift text, active boolean, created_at timestamptz
)
language sql security definer set search_path=public
as $$
  select id, employee_no, full_name, airport, shift, active, created_at
  from personnel
  where is_admin()
  order by full_name asc;
$$;
revoke all on function admin_personnel() from public;
grant execute on function admin_personnel() to authenticated;
