-- ============================================================
-- GÜNCELLEME — KISMI ADMİN (SORU EDİTÖRÜ) YETKİSİ
-- Supabase SQL Editor'da çalıştırın
-- ============================================================

-- 1) Personel tablosuna soru editörü (kısmi admin) alanı ekle
alter table personnel add column if not exists is_question_editor boolean not null default false;

-- 2) personnel_login RPC — is_question_editor alanını da dönecek şekilde güncelle
drop function if exists personnel_login(text,text);
create or replace function personnel_login(p_employee_no text, p_password text)
returns table(id uuid, employee_no text, full_name text, airport text, shift text, is_question_editor boolean)
language sql security definer set search_path=public
as $$
 select p.id,p.employee_no,p.full_name,p.airport,p.shift,p.is_question_editor
 from personnel p
 where p.employee_no=trim(p_employee_no)
 and p.active=true
 and p.password_hash=encode(sha256(p_password::bytea),'hex');
$$;
revoke all on function personnel_login(text,text) from public;
grant execute on function personnel_login(text,text) to anon,authenticated;

-- 3) admin_create_personnel — soru editörü parametresi destek
drop function if exists admin_create_personnel(text,text,text,text,text);
drop function if exists admin_create_personnel(text,text,text,text,text,boolean);
create or replace function admin_create_personnel(
  p_employee_no text,
  p_full_name text,
  p_airport text,
  p_shift text,
  p_password text,
  p_is_question_editor boolean default false
)
returns uuid language plpgsql security definer set search_path=public
as $$
declare pid uuid;
begin
 if not is_admin() then raise exception 'Yetkisiz'; end if;
 insert into personnel(employee_no,full_name,airport,shift,password_hash,is_question_editor)
 values(trim(p_employee_no),trim(p_full_name),nullif(trim(p_airport),''),nullif(trim(p_shift),''),encode(sha256(p_password::bytea),'hex'),coalesce(p_is_question_editor,false))
 returning id into pid;
 return pid;
end $$;
revoke all on function admin_create_personnel(text,text,text,text,text,boolean) from public;
grant execute on function admin_create_personnel(text,text,text,text,text,boolean) to authenticated;

-- 4) admin_personnel RPC — is_question_editor alanını da döner
drop function if exists admin_personnel();
create or replace function admin_personnel()
returns table(id uuid,employee_no text,full_name text,airport text,shift text,active boolean,is_question_editor boolean,created_at timestamptz)
language sql security definer set search_path=public
as $$ select id,employee_no,full_name,airport,shift,active,is_question_editor,created_at from personnel where is_admin() order by created_at desc; $$;
revoke all on function admin_personnel() from public;
grant execute on function admin_personnel() to authenticated;

-- 5) admin_update_personnel — p_is_question_editor parametresi destek
drop function if exists admin_update_personnel(uuid,text,text,text,text,text,boolean);
drop function if exists admin_update_personnel(uuid,text,text,text,text,text,boolean,boolean);
create or replace function admin_update_personnel(
  p_id uuid,
  p_employee_no text,
  p_full_name text,
  p_airport text,
  p_shift text,
  p_password text default null,
  p_active boolean default true,
  p_is_question_editor boolean default null
)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if not is_admin() then raise exception 'Yetkisiz'; end if;
  if p_password is not null and trim(p_password) <> '' then
    update personnel set
      employee_no = trim(p_employee_no),
      full_name = trim(p_full_name),
      airport = nullif(trim(p_airport),''),
      shift = nullif(trim(p_shift),''),
      password_hash = encode(sha256(p_password::bytea),'hex'),
      active = p_active,
      is_question_editor = coalesce(p_is_question_editor, is_question_editor)
    where id = p_id;
  else
    update personnel set
      employee_no = trim(p_employee_no),
      full_name = trim(p_full_name),
      airport = nullif(trim(p_airport),''),
      shift = nullif(trim(p_shift),''),
      active = p_active,
      is_question_editor = coalesce(p_is_question_editor, is_question_editor)
    where id = p_id;
  end if;
end $$;
revoke all on function admin_update_personnel(uuid,text,text,text,text,text,boolean,boolean) from public;
grant execute on function admin_update_personnel(uuid,text,text,text,text,text,boolean,boolean) to authenticated;

-- 6) Soru editörü için ÖZEL RPC: sadece correct_option güncelleme yetkisi
--    Kullanımı: personel girişi yapmış (auth gerekmez; personnel id verilir
create or replace function qeditor_update_correct(
  p_personnel_id uuid,
  p_question_id uuid,
  p_correct integer
)
returns void language plpgsql security definer set search_path=public
as $$
declare
  v_is_editor boolean;
begin
  -- Yetki kontrolü: personel.is_question_editor = true olmalı
  select coalesce(is_question_editor, false) into v_is_editor
  from personnel where id = p_personnel_id;

  if v_is_editor is not true then
    raise exception 'Yetkisiz: Soru editörü yetkiniz yok.';
  end if;

  -- Doğru cevap aralığı kontrolü (0-9)
  if p_correct is null or p_correct < 0 or p_correct > 9 then
    raise exception 'Geçersiz doğru cevap indeksi.';
  end if;

  update questions
  set correct_option = p_correct
  where id = p_question_id and active = true;
end $$;
revoke all on function qeditor_update_correct(uuid,uuid,integer) from public;
grant execute on function qeditor_update_correct(uuid,uuid,integer) to anon,authenticated;
