-- MedLog Supabase Schema
-- Run this in: https://supabase.com/dashboard/project/hfvfxiqfmcphctjbenul/sql/new
-- Supabase Auth handles users (auth.users table is auto-created)

-- ============================================================
-- PROFILES (family members per authenticated user)
-- ============================================================
CREATE TABLE IF NOT EXISTS ml_profiles (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  relationship TEXT,
  dob          DATE,
  email        TEXT,
  phone        TEXT,
  notes        TEXT,
  is_default   BOOLEAN DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- MEDICAL EVENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS ml_events (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES ml_profiles(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type       TEXT NOT NULL CHECK (type IN ('visit','checkup','surgery','medication','other')),
  date       DATE NOT NULL,
  title      TEXT NOT NULL,
  doctor     TEXT,
  dosage     TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- SYMPTOMS
-- ============================================================
CREATE TABLE IF NOT EXISTS ml_symptoms (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES ml_profiles(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  date       DATE NOT NULL,
  severity   TEXT CHECK (severity IN ('Mild','Moderate','Severe')),
  duration   TEXT,
  trigger    TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- FILE ATTACHMENTS (linked to events or symptoms)
-- ============================================================
CREATE TABLE IF NOT EXISTS ml_attachments (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id     UUID REFERENCES ml_events(id) ON DELETE CASCADE,
  symptom_id   UUID REFERENCES ml_symptoms(id) ON DELETE CASCADE,
  profile_id   UUID NOT NULL REFERENCES ml_profiles(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  file_name    TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  mime_type    TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  CHECK (event_id IS NOT NULL OR symptom_id IS NOT NULL)
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE ml_profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml_events     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml_symptoms   ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml_attachments ENABLE ROW LEVEL SECURITY;

-- Profiles: full access to own rows only
CREATE POLICY "ml_profiles_own" ON ml_profiles
  FOR ALL USING (auth.uid() = user_id);

-- Events: full access to own rows only
CREATE POLICY "ml_events_own" ON ml_events
  FOR ALL USING (auth.uid() = user_id);

-- Symptoms: full access to own rows only
CREATE POLICY "ml_symptoms_own" ON ml_symptoms
  FOR ALL USING (auth.uid() = user_id);

-- Attachments: full access to own rows only
CREATE POLICY "ml_attachments_own" ON ml_attachments
  FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- INDEXES for common query patterns
-- ============================================================
CREATE INDEX IF NOT EXISTS ml_events_profile_date   ON ml_events(profile_id, date DESC);
CREATE INDEX IF NOT EXISTS ml_symptoms_profile_date ON ml_symptoms(profile_id, date DESC);
CREATE INDEX IF NOT EXISTS ml_profiles_user         ON ml_profiles(user_id);

-- ============================================================
-- STORAGE BUCKET (run separately in Storage dashboard or via API)
-- Bucket name: medlog-attachments
-- Policies: authenticated users can upload/read/delete their own files
-- ============================================================
-- NOTE: Create bucket manually in Supabase Dashboard > Storage > New bucket
--       Name: medlog-attachments, Public: OFF
