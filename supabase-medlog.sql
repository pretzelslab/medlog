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


-- ============================================================
-- MIGRATION: Switch from Supabase Auth to PIN / invite-code auth
-- Run date: 2026-04-08
-- ============================================================

-- 1. Access codes table (stores shareable invite codes)
CREATE TABLE IF NOT EXISTS medlog_codes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code       TEXT NOT NULL UNIQUE,
  label      TEXT,                        -- who the code is for, e.g. "Mum", "Ravi"
  created_at TIMESTAMPTZ DEFAULT NOW(),
  is_active  BOOLEAN DEFAULT TRUE
);

-- 2. Allow anon key to read / create / update codes (no Supabase login needed)
ALTER TABLE medlog_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_read"   ON medlog_codes FOR SELECT USING (true);
CREATE POLICY "anon_insert" ON medlog_codes FOR INSERT WITH CHECK (true);
CREATE POLICY "anon_update" ON medlog_codes FOR UPDATE USING (true);

-- 3. Make ml_profiles accessible without Supabase auth
--    (access is now controlled by the invite code, not auth.uid())
DROP POLICY IF EXISTS "ml_profiles_own" ON ml_profiles;
CREATE POLICY "anon_all" ON ml_profiles FOR ALL USING (true) WITH CHECK (true);

-- 4. Same for events and symptoms (cascades from profile access)
DROP POLICY IF EXISTS "ml_events_own"   ON ml_events;
DROP POLICY IF EXISTS "ml_symptoms_own" ON ml_symptoms;
CREATE POLICY "anon_all" ON ml_events   FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON ml_symptoms FOR ALL USING (true) WITH CHECK (true);

-- NOTE: user_id columns in ml_events and ml_symptoms are no longer
--       populated with auth.uid(). They are left empty (nullable) or
--       set to a fixed constant by the app. No FK constraint is enforced
--       once auth.users is no longer used.
