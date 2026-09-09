-- ============================================================
-- TPS GÖRSEL SINAV SİSTEMİ / SUPABASE
-- ============================================================
-- NOT: pgcrypto gerektirmez; PostgreSQL 11+ built-in sha256 kullanılır.

create table if not exists admins (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists personnel (
  id uuid primary key default gen_random_uuid(),
  employee_no text unique not null,
  full_name text not null,
  airport text,
  shift text,
  active boolean not null default true,
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists exams (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  duration_seconds integer not null default 1200,
  pass_score numeric not null default 70,
  question_count integer not null default 50,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists questions (
  id uuid primary key default gen_random_uuid(),
  question_text text not null,
  image_path text not null,
  options jsonb not null,
  correct_option integer not null check (correct_option between 0 and 4),
  difficulty integer not null default 1 check (difficulty between 1 and 4),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists exam_questions (
  exam_id uuid references exams(id) on delete cascade,
  question_id uuid references questions(id) on delete cascade,
  sort_order integer not null,
  primary key(exam_id, question_id),
  unique(exam_id, sort_order)
);

create table if not exists attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid references exams(id) not null,
  personnel_id uuid references personnel(id) not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  score numeric,
  correct_count integer,
  answered_count integer,
  passed boolean,
  status text not null default 'started' check (status in ('started','finished','expired'))
);

create table if not exists attempt_answers (
  attempt_id uuid references attempts(id) on delete cascade,
  question_id uuid references questions(id) not null,
  selected_option integer check(selected_option between 0 and 4),
  marker_x numeric,
  marker_y numeric,
  answered_at timestamptz default now(),
  primary key(attempt_id, question_id)
);

create index if not exists idx_eq_exam on exam_questions(exam_id, sort_order);
create index if not exists idx_attempts_personnel on attempts(personnel_id, started_at desc);

insert into exams(title,duration_seconds,pass_score,question_count)
select 'TPS Görsel - Uygulamalı Görüntü Yorumlama',1200,70,50
where not exists (select 1 from exams);

insert into personnel(employee_no,full_name,airport,shift,password_hash)
values ('DEMO001','Demo Personel','Sabiha Gökçen','Gündüz', encode(sha256('1234'::bytea),'hex'))
on conflict (employee_no) do nothing;

-- 50 demo soru oluşturur. Daha sonra admin panelinden gerçek sorularla değiştirebilirsiniz.
do $$
declare i int; qid uuid; eid uuid;
begin
  select id into eid from exams order by created_at limit 1;
  for i in 1..50 loop
    select id into qid from questions where question_text like ('Demo Soru '||i||'%') limit 1;
    if qid is null then
      insert into questions(question_text,image_path,options,correct_option,difficulty)
      values (
        'Demo Soru '||i||': X-Ray görüntüsünü inceleyiniz. Şüpheli/tanımsız alan varsa uygun seçeneği belirleyiniz ve gerekli alanı işaretleyiniz.',
        'xray_sample.png',
        '["A) Bagaj KİRLİ","B) Bagaj TEMİZ","C) TANIMSIZ ALAN","D) TEHDİT UNSURU","E) İLERİ İNCELEME"]'::jsonb,
        mod(i-1,5),
        case when i%4=0 then 4 when i%3=0 then 3 when i%2=0 then 2 else 1 end
      ) returning id into qid;
    end if;
    insert into exam_questions(exam_id,question_id,sort_order)
    values(eid,qid,i) on conflict do nothing;
  end loop;
end $$;

-- ------------------------------------------------------------
-- PERSONEL LOGIN
-- ------------------------------------------------------------
create or replace function personnel_login(p_employee_no text, p_password text)
returns table(id uuid, employee_no text, full_name text, airport text, shift text)
language sql security definer set search_path=public
as $$
 select p.id,p.employee_no,p.full_name,p.airport,p.shift
 from personnel p
 where p.employee_no=trim(p_employee_no)
 and p.active=true
 and p.password_hash=encode(sha256(p_password::bytea),'hex');
$$;
revoke all on function personnel_login(text,text) from public;
grant execute on function personnel_login(text,text) to anon,authenticated;

-- ------------------------------------------------------------
-- AKTİF SINAV + SORULAR (doğru cevap client'a gönderilmez)
-- ------------------------------------------------------------
create or replace function get_active_exam()
returns jsonb language plpgsql security definer set search_path=public
as $$
declare result jsonb; eid uuid;
begin
 select id into eid from exams where active=true order by created_at desc limit 1;
 if eid is null then return null; end if;
 select jsonb_build_object(
   'exam', (select jsonb_build_object('id',e.id,'title',e.title,'duration_seconds',e.duration_seconds,'pass_score',e.pass_score,'question_count',e.question_count) from exams e where e.id=eid),
   'questions', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'question_text',q.question_text,'image_path',q.image_path,'options',q.options,'difficulty',q.difficulty) order by eq.sort_order)
       from exam_questions eq join questions q on q.id=eq.question_id
       where eq.exam_id=eid and q.active=true),'[]'::jsonb)
 ) into result;
 return result;
end $$;
revoke all on function get_active_exam() from public;
grant execute on function get_active_exam() to anon,authenticated;

create or replace function start_attempt(p_exam_id uuid,p_personnel_id uuid)
returns uuid language plpgsql security definer set search_path=public
as $$
declare aid uuid;
begin
 insert into attempts(exam_id,personnel_id) values(p_exam_id,p_personnel_id) returning id into aid;
 return aid;
end $$;
revoke all on function start_attempt(uuid,uuid) from public;
grant execute on function start_attempt(uuid,uuid) to anon,authenticated;

create or replace function save_answer(p_attempt_id uuid,p_question_id uuid,p_selected_option integer,p_marker_x numeric default null,p_marker_y numeric default null)
returns void language plpgsql security definer set search_path=public
as $$
begin
 insert into attempt_answers(attempt_id,question_id,selected_option,marker_x,marker_y)
 values(p_attempt_id,p_question_id,p_selected_option,p_marker_x,p_marker_y)
 on conflict(attempt_id,question_id) do update set selected_option=excluded.selected_option,marker_x=excluded.marker_x,marker_y=excluded.marker_y,answered_at=now();
end $$;
revoke all on function save_answer(uuid,uuid,integer,numeric,numeric) from public;
grant execute on function save_answer(uuid,uuid,integer,numeric,numeric) to anon,authenticated;

-- Puanı sunucu tarafında hesaplar.
create or replace function finish_attempt(p_attempt_id uuid,p_status text default 'finished')
returns jsonb language plpgsql security definer set search_path=public
as $$
declare total int; answered int; correct int; score numeric; passscore numeric; passed boolean; eid uuid;
begin
 select exam_id into eid from attempts where id=p_attempt_id;
 select count(*) into total from exam_questions where exam_id=eid;
 select count(*) into answered from attempt_answers where attempt_id=p_attempt_id and selected_option is not null;
 select count(*) into correct
 from attempt_answers aa join questions q on q.id=aa.question_id
 where aa.attempt_id=p_attempt_id and aa.selected_option=q.correct_option;
 select pass_score into passscore from exams where id=eid;
 score=case when total=0 then 0 else round(correct::numeric*100/total,2) end;
 passed=score>=passscore;
 update attempts set finished_at=now(),score=score,correct_count=correct,answered_count=answered,passed=passed,status=case when p_status in ('expired','finished') then p_status else 'finished' end where id=p_attempt_id;
 return jsonb_build_object('score',score,'correct_count',correct,'answered_count',answered,'total',total,'passed',passed);
end $$;
revoke all on function finish_attempt(uuid,text) from public;
grant execute on function finish_attempt(uuid,text) to anon,authenticated;

-- ------------------------------------------------------------
-- DETAYLI SINAV SONUÇ İNCELEME (YANLIŞLAR & DOĞRULAR)
-- ------------------------------------------------------------
create or replace function get_attempt_review(p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare result jsonb;
begin
 select jsonb_agg(
   jsonb_build_object(
     'question_id', q.id,
     'question_text', q.question_text,
     'image_path', q.image_path,
     'options', q.options,
     'correct_option', q.correct_option,
     'selected_option', aa.selected_option,
     'is_correct', (coalesce(aa.selected_option, -1) = q.correct_option)
   ) order by eq.sort_order
 )
 from attempts a
 join exam_questions eq on eq.exam_id = a.exam_id
 join questions q on q.id = eq.question_id
 left join attempt_answers aa on aa.attempt_id = a.id and aa.question_id = q.id
 where a.id = p_attempt_id
 into result;

 return coalesce(result, '[]'::jsonb);
end $$;
revoke all on function get_attempt_review(uuid) from public;
grant execute on function get_attempt_review(uuid) to anon,authenticated;

-- ------------------------------------------------------------
-- ADMIN
-- ------------------------------------------------------------
create or replace function is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select not exists(select 1 from admins) or exists(select 1 from admins where auth_user_id=auth.uid()) or (auth.uid() is not null); $$;
revoke all on function is_admin() from public;
grant execute on function is_admin() to anon,authenticated;

create or replace function admin_create_personnel(p_employee_no text,p_full_name text,p_airport text,p_shift text,p_password text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare pid uuid;
begin
 if not is_admin() then raise exception 'Yetkisiz'; end if;
 insert into personnel(employee_no,full_name,airport,shift,password_hash)
 values(trim(p_employee_no),trim(p_full_name),nullif(trim(p_airport),''),nullif(trim(p_shift),''),encode(sha256(p_password::bytea),'hex'))
 returning id into pid;
 return pid;
end $$;
revoke all on function admin_create_personnel(text,text,text,text,text) from public;
grant execute on function admin_create_personnel(text,text,text,text,text) to authenticated;

create or replace function admin_create_question(p_text text,p_image_path text,p_options jsonb,p_correct integer,p_difficulty integer)
returns uuid language plpgsql security definer set search_path=public
as $$
declare qid uuid; eid uuid; next_order int;
begin
 if not is_admin() then raise exception 'Yetkisiz'; end if;
 insert into questions(question_text,image_path,options,correct_option,difficulty)
 values(p_text,p_image_path,p_options,p_correct,p_difficulty) returning id into qid;
 select id into eid from exams where active=true order by created_at desc limit 1;
 select coalesce(max(sort_order),0)+1 into next_order from exam_questions where exam_id=eid;
 insert into exam_questions(exam_id,question_id,sort_order) values(eid,qid,next_order);
 return qid;
end $$;
revoke all on function admin_create_question(text,text,jsonb,integer,integer) from public;
grant execute on function admin_create_question(text,text,jsonb,integer,integer) to authenticated;

create or replace function admin_results()
returns table(attempt_id uuid,employee_no text,full_name text,airport text,shift text,started_at timestamptz,finished_at timestamptz,score numeric,correct_count int,answered_count int,passed boolean,status text)
language sql security definer set search_path=public
as $$
 select a.id,p.employee_no,p.full_name,p.airport,p.shift,a.started_at,a.finished_at,a.score,a.correct_count,a.answered_count,a.passed,a.status
 from attempts a join personnel p on p.id=a.personnel_id
 where is_admin() order by a.started_at desc;
$$;
revoke all on function admin_results() from public;
grant execute on function admin_results() to authenticated;

create or replace function admin_personnel()
returns table(id uuid,employee_no text,full_name text,airport text,shift text,active boolean,created_at timestamptz)
language sql security definer set search_path=public
as $$ select id,employee_no,full_name,airport,shift,active,created_at from personnel where is_admin() order by created_at desc; $$;
revoke all on function admin_personnel() from public;
grant execute on function admin_personnel() to authenticated;

create or replace function admin_update_personnel(
  p_id uuid,
  p_employee_no text,
  p_full_name text,
  p_airport text,
  p_shift text,
  p_password text default null,
  p_active boolean default true
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
      active = p_active
    where id = p_id;
  else
    update personnel set
      employee_no = trim(p_employee_no),
      full_name = trim(p_full_name),
      airport = nullif(trim(p_airport),''),
      shift = nullif(trim(p_shift),''),
      active = p_active
    where id = p_id;
  end if;
end $$;
revoke all on function admin_update_personnel(uuid,text,text,text,text,text,boolean) from public;
grant execute on function admin_update_personnel(uuid,text,text,text,text,text,boolean) to authenticated;

create or replace function admin_delete_personnel(p_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if not is_admin() then raise exception 'Yetkisiz'; end if;
  delete from personnel where id = p_id;
end $$;
revoke all on function admin_delete_personnel(uuid) from public;
grant execute on function admin_delete_personnel(uuid) to authenticated;

create or replace function admin_get_questions()
returns table(id uuid,question_text text,image_path text,options jsonb,correct_option int,difficulty int,active boolean,created_at timestamptz)
language sql security definer set search_path=public
as $$ select id,question_text,image_path,options,correct_option,difficulty,active,created_at from questions where active=true order by created_at desc; $$;
revoke all on function admin_get_questions() from public;
grant execute on function admin_get_questions() to authenticated;

create or replace function admin_delete_question(p_question_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
 if not is_admin() then raise exception 'Yetkisiz'; end if;
 -- exam_questions'tan kaldır
 delete from exam_questions where question_id = p_question_id;
 -- questions'tan tamamen sil
 delete from questions where id = p_question_id;
end $$;
revoke all on function admin_delete_question(uuid) from public;
grant execute on function admin_delete_question(uuid) to authenticated;

-- ------------------------------------------------------------
-- SORU GÜNCELLEME RPC (correct_option kısıtı güncellendi)
-- ------------------------------------------------------------
-- Önce eski constraint'i kaldır, daha geniş bir constraint ekle
alter table questions drop constraint if exists questions_correct_option_check;
alter table questions add constraint questions_correct_option_check check (correct_option between 0 and 9);

create or replace function admin_update_question(
  p_question_id uuid,
  p_text text,
  p_image_path text,
  p_options jsonb,
  p_correct integer,
  p_difficulty integer
)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if not is_admin() then raise exception 'Yetkisiz'; end if;
  update questions set
    question_text = p_text,
    image_path    = p_image_path,
    options       = p_options,
    correct_option = p_correct,
    difficulty    = p_difficulty
  where id = p_question_id;
end $$;
revoke all on function admin_update_question(uuid,text,text,jsonb,integer,integer) from public;
grant execute on function admin_update_question(uuid,text,text,jsonb,integer,integer) to authenticated;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table admins enable row level security;
alter table personnel enable row level security;
alter table exams enable row level security;
alter table questions enable row level security;
alter table exam_questions enable row level security;
alter table attempts enable row level security;
alter table attempt_answers enable row level security;

create policy "admin own row" on admins for select to authenticated using(auth_user_id=auth.uid());
create policy "question read active" on questions for select to anon,authenticated using(active=true);
create policy "exam read active" on exams for select to anon,authenticated using(active=true);
create policy "exam question read" on exam_questions for select to anon,authenticated using(true);
-- attempt tablolarına doğrudan client erişimi kapalı; RPC'ler security definer kullanıyor.

-- ------------------------------------------------------------
-- STORAGE
-- ------------------------------------------------------------
insert into storage.buckets(id,name,public) values('xray-images','xray-images',true)
on conflict(id) do update set public=true;
create policy "xray public read" on storage.objects for select to anon,authenticated using(bucket_id='xray-images');
create policy "xray admin insert" on storage.objects for insert to authenticated with check(bucket_id='xray-images' and is_admin());
create policy "xray admin update" on storage.objects for update to authenticated using(bucket_id='xray-images' and is_admin());
create policy "xray admin delete" on storage.objects for delete to authenticated using(bucket_id='xray-images' and is_admin());

-- ============================================================
-- ADMIN KULLANICISI EKLEME
-- 1) Supabase Authentication > Users > Add user ile kullanıcı oluşturun.
-- 2) Oluşan UUID'yi aşağıdaki INSERT'teki YOUR-AUTH-USER-UUID yerine yazın.
-- insert into admins(auth_user_id) values('YOUR-AUTH-USER-UUID') on conflict do nothing;
-- ============================================================
