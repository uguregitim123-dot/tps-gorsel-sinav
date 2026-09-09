-- ============================================================
-- GÜNCELLEME — Supabase SQL Editor'da çalıştır
-- ============================================================

-- get_active_exam — correct_option eklendi + rastgele 50 soru seçimi
create or replace function get_active_exam()
returns jsonb language plpgsql security definer set search_path=public
as $$
declare result jsonb; eid uuid; qcount integer;
begin
  select id, question_count
  into eid, qcount
  from exams
  where active = true
  order by created_at desc
  limit 1;

  if eid is null then return null; end if;

  -- question_count kadar (varsayılan 50) rastgele soru seç
  select jsonb_build_object(
    'exam', (
      select jsonb_build_object(
        'id',               e.id,
        'title',            e.title,
        'duration_seconds', e.duration_seconds,
        'pass_score',       e.pass_score,
        'question_count',   e.question_count
      )
      from exams e where e.id = eid
    ),
    'questions', coalesce((
      select jsonb_agg(q_row)
      from (
        select jsonb_build_object(
          'id',             q.id,
          'question_text',  q.question_text,
          'image_path',     q.image_path,
          'options',        q.options,
          'correct_option', q.correct_option,
          'difficulty',     q.difficulty
        ) as q_row
        from exam_questions eq
        join questions q on q.id = eq.question_id
        where eq.exam_id = eid
          and q.active = true
        order by random()
        limit qcount
      ) sub
    ), '[]'::jsonb)
  ) into result;

  return result;
end $$;
revoke all on function get_active_exam() from public;
grant execute on function get_active_exam() to anon, authenticated;

-- admin_create_question — soruyu exam_questions'a da ekliyor (havuz için gerekli)
-- Bu fonksiyon değişmiyor, mevcut haliyle doğru çalışıyor.
-- Ancak get_active_exam artık sort_order'a değil random()'a bakıyor,
-- exam_questions sadece hangi soruların havuzda olduğunu tanımlamak için kullanılıyor.

-- Sınav havuzundaki soru sayısını kontrol etmek için:
-- select count(*) from exam_questions eq
-- join questions q on q.id = eq.question_id
-- where q.active = true
-- and eq.exam_id = (select id from exams where active=true order by created_at desc limit 1);
