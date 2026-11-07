SET search_path = sports, public;

CREATE INDEX IF NOT EXISTS ix_venue_city_active
  ON venue(city)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_registration_category_status_active
  ON event_registration(category_id, status)
  WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW v_event_catalog_sql AS
SELECT
  e.id,
  e.name,
  e.description,
  e.status,
  e.starts_at,
  e.ends_at,
  e.registration_deadline,
  e.capacity,
  e.last_modified_at,
  s.id AS sport_id,
  s.name AS sport_name,
  v.id AS venue_id,
  v.name AS venue_name,
  v.address AS venue_address,
  v.city AS venue_city,
  u.id AS organizer_id,
  u.display_name AS organizer_name,
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'code', c.code,
        'name', c.name,
        'minAge', c.min_age,
        'maxAge', c.max_age,
        'capacity', c.capacity,
        'confirmedRegistrations', COALESCE((
          SELECT count(*)
          FROM event_registration r
          WHERE r.category_id = c.id
            AND r.status = 'confirmed'
            AND r.deleted_at IS NULL
        ), 0)
      )
      ORDER BY c.code
    )
    FROM event_category c
    WHERE c.event_id = e.id
      AND c.deleted_at IS NULL
  ), '[]'::jsonb) AS categories,
  COALESCE((
    SELECT count(*)
    FROM event_registration r
    JOIN event_category c ON c.id = r.category_id
    WHERE c.event_id = e.id
      AND c.deleted_at IS NULL
      AND r.status = 'confirmed'
      AND r.deleted_at IS NULL
  ), 0) AS confirmed_registrations
FROM sport_event e
JOIN sport s ON s.id = e.sport_id AND s.deleted_at IS NULL
JOIN venue v ON v.id = e.venue_id AND v.deleted_at IS NULL
JOIN app_user u ON u.id = e.organizer_id AND u.deleted_at IS NULL
WHERE e.deleted_at IS NULL;

CREATE OR REPLACE FUNCTION fn_search_event_catalog(
  p_city text,
  p_from timestamptz,
  p_to timestamptz,
  p_limit integer DEFAULT 50
)
RETURNS SETOF v_event_catalog_sql
LANGUAGE sql
STABLE
AS $$
  SELECT *
  FROM sports.v_event_catalog_sql
  WHERE status = 'published'
    AND venue_city = p_city
    AND starts_at >= p_from
    AND starts_at < p_to
  ORDER BY starts_at, id
  LIMIT LEAST(GREATEST(p_limit, 1), 500)
$$;

COMMENT ON VIEW v_event_catalog_sql IS
  'SQL equivalent of the MongoDB event_catalog read model. Data comes from sport_event, sport, venue, app_user, event_category and event_registration.';

COMMENT ON FUNCTION fn_search_event_catalog(text, timestamptz, timestamptz, integer) IS
  'Benchmark search equivalent to the MongoDB city/status/date query.';
