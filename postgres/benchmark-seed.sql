SET search_path = sports, public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM sport WHERE deleted_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM venue WHERE deleted_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM app_user WHERE role = 'organizer' AND deleted_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM athlete_profile WHERE deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Run schema.sql and seed.sql before benchmark-seed.sql';
  END IF;
END $$;

WITH dimensions AS (
  SELECT
    array_agg(id ORDER BY id) FILTER (WHERE kind = 'sport') AS sport_ids,
    array_agg(id ORDER BY id) FILTER (WHERE kind = 'venue') AS venue_ids,
    (array_agg(id ORDER BY id) FILTER (WHERE kind = 'organizer'))[1] AS organizer_id
  FROM (
    SELECT id, 'sport'::text AS kind FROM sport WHERE deleted_at IS NULL
    UNION ALL
    SELECT id, 'venue' FROM venue WHERE deleted_at IS NULL
    UNION ALL
    SELECT id, 'organizer' FROM app_user WHERE role = 'organizer' AND deleted_at IS NULL
  ) d
), source AS (
  SELECT i, d.*
  FROM generate_series(1, 10000) AS i
  CROSS JOIN dimensions d
)
INSERT INTO sport_event(
  id, sport_id, venue_id, organizer_id, name, description,
  starts_at, ends_at, registration_deadline, capacity, status, last_modified_by
)
SELECT
  md5('nosql-benchmark-event-' || i)::uuid,
  sport_ids[1 + ((i - 1) % cardinality(sport_ids))],
  venue_ids[1 + ((i - 1) % cardinality(venue_ids))],
  organizer_id,
  'Benchmark event ' || lpad(i::text, 5, '0'),
  'Синтетичний запис для порівняння PostgreSQL і MongoDB.',
  timestamptz '2027-01-01 09:00+02' + ((i - 1) % 365) * interval '1 day',
  timestamptz '2027-01-01 12:00+02' + ((i - 1) % 365) * interval '1 day',
  timestamptz '2026-12-28 23:59+02' + ((i - 1) % 365) * interval '1 day',
  300,
  'published',
  organizer_id
FROM source
ON CONFLICT (id) DO UPDATE SET
  sport_id = excluded.sport_id,
  venue_id = excluded.venue_id,
  organizer_id = excluded.organizer_id,
  name = excluded.name,
  description = excluded.description,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  registration_deadline = excluded.registration_deadline,
  capacity = excluded.capacity,
  status = excluded.status,
  deleted_at = NULL,
  last_modified_by = excluded.last_modified_by;

INSERT INTO event_category(
  id, event_id, code, name, min_age, max_age, capacity, last_modified_by
)
SELECT
  md5('nosql-benchmark-category-' || i || '-' || category_no)::uuid,
  md5('nosql-benchmark-event-' || i)::uuid,
  'C' || category_no,
  'Benchmark category ' || category_no,
  CASE category_no WHEN 1 THEN 12 WHEN 2 THEN 18 ELSE NULL END,
  CASE category_no WHEN 1 THEN 17 ELSE NULL END,
  100,
  (SELECT id FROM app_user WHERE role = 'organizer' AND deleted_at IS NULL ORDER BY id LIMIT 1)
FROM generate_series(1, 10000) AS i
CROSS JOIN generate_series(1, 3) AS category_no
ON CONFLICT (id) DO UPDATE SET
  event_id = excluded.event_id,
  code = excluded.code,
  name = excluded.name,
  min_age = excluded.min_age,
  max_age = excluded.max_age,
  capacity = excluded.capacity,
  deleted_at = NULL,
  last_modified_by = excluded.last_modified_by;

WITH athletes AS (
  SELECT array_agg(id ORDER BY id) AS ids
  FROM athlete_profile
  WHERE deleted_at IS NULL
), source AS (
  SELECT i, category_no, registration_no, ids
  FROM generate_series(1, 10000) AS i
  CROSS JOIN generate_series(1, 3) AS category_no
  CROSS JOIN generate_series(1, 12) AS registration_no
  CROSS JOIN athletes
)
INSERT INTO event_registration(
  id, category_id, athlete_id, status, registered_at, last_modified_by
)
SELECT
  md5('nosql-benchmark-registration-' || i || '-' || category_no || '-' || registration_no)::uuid,
  md5('nosql-benchmark-category-' || i || '-' || category_no)::uuid,
  ids[1 + (((i * 17) + (category_no * 31) + registration_no - 1) % cardinality(ids))],
  'confirmed',
  now() - (registration_no % 7) * interval '1 day',
  (SELECT id FROM app_user WHERE role = 'organizer' AND deleted_at IS NULL ORDER BY id LIMIT 1)
FROM source
ON CONFLICT (id) DO UPDATE SET
  category_id = excluded.category_id,
  athlete_id = excluded.athlete_id,
  status = excluded.status,
  registered_at = excluded.registered_at,
  deleted_at = NULL,
  last_modified_by = excluded.last_modified_by;

ANALYZE sport_event;
ANALYZE event_category;
ANALYZE event_registration;

SELECT
  (SELECT count(*) FROM sport_event WHERE name LIKE 'Benchmark event %' AND deleted_at IS NULL) AS benchmark_events,
  (SELECT count(*) FROM event_category WHERE name LIKE 'Benchmark category %' AND deleted_at IS NULL) AS benchmark_categories,
  (SELECT count(*) FROM event_registration r
     JOIN event_category c ON c.id = r.category_id
    WHERE c.name LIKE 'Benchmark category %' AND r.deleted_at IS NULL) AS benchmark_registrations;
