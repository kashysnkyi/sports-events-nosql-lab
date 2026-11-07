SET search_path = sports, public;

INSERT INTO app_user(id, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Олена Мельник', 'organizer')
ON CONFLICT (id) DO UPDATE SET display_name = excluded.display_name, deleted_at = NULL;

INSERT INTO sport(id, name) VALUES
  ('10000000-0000-0000-0000-000000000001', 'Біг'),
  ('10000000-0000-0000-0000-000000000002', 'Велоспорт'),
  ('10000000-0000-0000-0000-000000000003', 'Плавання'),
  ('10000000-0000-0000-0000-000000000004', 'Тріатлон'),
  ('10000000-0000-0000-0000-000000000005', 'Футбол')
ON CONFLICT (id) DO UPDATE SET name = excluded.name, deleted_at = NULL;

INSERT INTO venue(id, name, address, city)
SELECT
  ('20000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  'Спортивна локація ' || i,
  'вул. Спортивна, ' || i,
  (ARRAY['Київ','Львів','Одеса','Харків','Дніпро'])[1 + ((i - 1) % 5)]
FROM generate_series(1, 14) i
ON CONFLICT (id) DO UPDATE SET
  name = excluded.name, address = excluded.address, city = excluded.city, deleted_at = NULL;

INSERT INTO app_user(id, display_name, role)
SELECT md5('athlete-user-' || i)::uuid, 'Спортсмен ' || i, 'athlete'
FROM generate_series(1, 300) i
ON CONFLICT (id) DO UPDATE SET display_name = excluded.display_name, deleted_at = NULL;

INSERT INTO athlete_profile(id, user_id, birth_date)
SELECT md5('athlete-profile-' || i)::uuid, md5('athlete-user-' || i)::uuid,
       date '1980-01-01' + ((i * 37) % 9000)
FROM generate_series(1, 300) i
ON CONFLICT (id) DO UPDATE SET birth_date = excluded.birth_date, deleted_at = NULL;

INSERT INTO sport_event(
  id, sport_id, venue_id, organizer_id, name, description, starts_at, ends_at,
  registration_deadline, capacity, status, last_modified_by)
SELECT
  ('30000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  ('10000000-0000-0000-0000-' || lpad((1 + ((i - 1) % 5))::text, 12, '0'))::uuid,
  ('20000000-0000-0000-0000-' || lpad((1 + ((i - 1) % 14))::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000001',
  'Спортивна подія ' || i,
  'Демонстраційна подія',
  timestamptz '2027-03-01 09:00+02' + (i - 1) * interval '7 days',
  timestamptz '2027-03-01 12:00+02' + (i - 1) * interval '7 days',
  timestamptz '2027-02-25 23:59+02' + (i - 1) * interval '7 days',
  300, 'published', '00000000-0000-0000-0000-000000000001'
FROM generate_series(1, 12) i
ON CONFLICT (id) DO UPDATE SET name = excluded.name, deleted_at = NULL;

INSERT INTO event_category(id, event_id, code, name, min_age, capacity, last_modified_by)
SELECT
  ('40000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  ('30000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  'OPEN', 'Відкрита категорія', 18, 300,
  '00000000-0000-0000-0000-000000000001'
FROM generate_series(1, 12) i
ON CONFLICT (id) DO UPDATE SET name = excluded.name, deleted_at = NULL;

INSERT INTO event_registration(id, category_id, athlete_id, status, last_modified_by)
SELECT
  md5('demo-registration-' || event_no || '-' || athlete_no)::uuid,
  ('40000000-0000-0000-0000-' || lpad(event_no::text, 12, '0'))::uuid,
  md5('athlete-profile-' || athlete_no)::uuid,
  'confirmed', '00000000-0000-0000-0000-000000000001'
FROM generate_series(1, 12) event_no
CROSS JOIN generate_series(1, 25) athlete_no
ON CONFLICT (id) DO UPDATE SET status = excluded.status, deleted_at = NULL;
