CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS sports;
SET search_path = sports, public;

CREATE TABLE IF NOT EXISTS app_user (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('organizer', 'athlete')),
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS sport (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS venue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  address text NOT NULL,
  city text NOT NULL,
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS athlete_profile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES app_user(id),
  birth_date date,
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS sport_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sport_id uuid NOT NULL REFERENCES sport(id),
  venue_id uuid NOT NULL REFERENCES venue(id),
  organizer_id uuid NOT NULL REFERENCES app_user(id),
  name text NOT NULL,
  description text,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  registration_deadline timestamptz,
  capacity integer CHECK (capacity > 0),
  status text NOT NULL CHECK (status IN ('draft', 'published', 'cancelled', 'completed')),
  last_modified_at timestamptz NOT NULL DEFAULT now(),
  last_modified_by uuid REFERENCES app_user(id),
  deleted_at timestamptz,
  CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS event_category (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES sport_event(id),
  code text NOT NULL,
  name text NOT NULL,
  min_age integer,
  max_age integer,
  capacity integer CHECK (capacity > 0),
  last_modified_at timestamptz NOT NULL DEFAULT now(),
  last_modified_by uuid REFERENCES app_user(id),
  deleted_at timestamptz,
  UNIQUE (event_id, code)
);

CREATE TABLE IF NOT EXISTS event_registration (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES event_category(id),
  athlete_id uuid NOT NULL REFERENCES athlete_profile(id),
  status text NOT NULL CHECK (status IN ('pending', 'confirmed', 'cancelled')),
  registered_at timestamptz NOT NULL DEFAULT now(),
  last_modified_at timestamptz NOT NULL DEFAULT now(),
  last_modified_by uuid REFERENCES app_user(id),
  deleted_at timestamptz,
  UNIQUE (category_id, athlete_id)
);

CREATE INDEX IF NOT EXISTS ix_event_status_start_active
  ON sport_event(status, starts_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_category_event_active
  ON event_category(event_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_registration_category_active
  ON event_registration(category_id) WHERE deleted_at IS NULL;
