-- ============================================================
-- 008_fitness_schema.sql — Fitness Buddy schema
-- ============================================================
-- Tables backing the fitness-buddy MCP skill. All scoped per user
-- via user_id text (matches the qualifiedUserId pattern used by
-- tasks/reminders).
--
-- Idempotent: safe to apply on existing installs. Empty tables for
-- users who do not install the fitness-buddy skill are negligible.
-- ============================================================

-- 1. Profile (one row per user) -----------------------------------
CREATE TABLE IF NOT EXISTS public.fitness_profile (
  user_id              text PRIMARY KEY,
  sex                  text CHECK (sex IN ('m','f','x')),
  birthdate            date,
  height_cm            numeric,
  weight_kg_baseline   numeric,
  activity_level       text CHECK (activity_level IN ('sedentary','light','moderate','active','very_active')),
  goal                 text CHECK (goal IN ('lose_weight','maintain','gain_muscle','recomp','endurance')),
  target_weight_kg     numeric,
  target_date          date,
  daily_kcal_target    integer,
  protein_g_target     integer,
  carbs_g_target       integer,
  fat_g_target         integer,
  hydration_ml_target  integer,
  dietary_restrictions text[],
  allergies            text[],
  excluded_foods       text[],
  training_days_per_week integer,
  preferred_workout_time text,
  notes                text,
  updated_at           timestamptz DEFAULT now()
);

-- 2. Meal memory (frequently eaten meals) -------------------------
CREATE TABLE IF NOT EXISTS public.fitness_meal_memory (
  id               bigserial PRIMARY KEY,
  user_id          text NOT NULL,
  name             text NOT NULL,
  items            jsonb NOT NULL,
  total_kcal       numeric,
  total_protein_g  numeric,
  total_carbs_g    numeric,
  total_fat_g      numeric,
  total_fiber_g    numeric,
  times_logged     integer DEFAULT 1,
  last_logged_at   timestamptz,
  created_at       timestamptz DEFAULT now(),
  CONSTRAINT fitness_meal_memory_user_name_unique UNIQUE (user_id, name)
);
CREATE INDEX IF NOT EXISTS fitness_meal_memory_user_freq_idx
  ON public.fitness_meal_memory (user_id, times_logged DESC);

-- 3. Meals --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fitness_meals (
  id               bigserial PRIMARY KEY,
  user_id          text NOT NULL,
  logged_at        timestamptz NOT NULL,
  meal_type        text CHECK (meal_type IN ('breakfast','lunch','dinner','snack')),
  items            jsonb NOT NULL,
  total_kcal       numeric,
  total_protein_g  numeric,
  total_carbs_g    numeric,
  total_fat_g      numeric,
  total_fiber_g    numeric,
  input_source     text,
  photo_ref        text,
  raw_input        text,
  vision_confidence numeric,
  meal_memory_id   bigint REFERENCES public.fitness_meal_memory(id) ON DELETE SET NULL,
  notes            text,
  created_at       timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS fitness_meals_user_logged_idx
  ON public.fitness_meals (user_id, logged_at DESC);

-- 4. Workouts -----------------------------------------------------
-- Plans/sessions are created in a later block; the workouts.plan_session_id
-- FK is added once the sessions table exists.
CREATE TABLE IF NOT EXISTS public.fitness_workouts (
  id               bigserial PRIMARY KEY,
  user_id          text NOT NULL,
  performed_at     timestamptz NOT NULL,
  exercise_type    text,
  duration_min     integer,
  intensity        text CHECK (intensity IN ('low','medium','high')),
  distance_km      numeric,
  sets             jsonb,
  calories_burned  integer,
  perceived_exertion integer CHECK (perceived_exertion BETWEEN 1 AND 10),
  plan_session_id  bigint,
  input_source     text,
  raw_input        text,
  notes            text,
  created_at       timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS fitness_workouts_user_perf_idx
  ON public.fitness_workouts (user_id, performed_at DESC);

-- 5. Body measurements --------------------------------------------
CREATE TABLE IF NOT EXISTS public.fitness_body (
  id              bigserial PRIMARY KEY,
  user_id         text NOT NULL,
  measured_at     timestamptz NOT NULL,
  weight_kg       numeric,
  body_fat_pct    numeric,
  muscle_mass_kg  numeric,
  waist_cm        numeric,
  chest_cm        numeric,
  hip_cm          numeric,
  thigh_cm        numeric,
  arm_cm          numeric,
  photo_ref       text,
  notes           text,
  created_at      timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS fitness_body_user_measured_idx
  ON public.fitness_body (user_id, measured_at DESC);

-- 6. Hydration ----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fitness_hydration (
  id            bigserial PRIMARY KEY,
  user_id       text NOT NULL,
  logged_at     timestamptz NOT NULL,
  volume_ml     integer NOT NULL CHECK (volume_ml > 0),
  beverage_type text DEFAULT 'water',
  created_at    timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS fitness_hydration_user_logged_idx
  ON public.fitness_hydration (user_id, logged_at DESC);

-- 7. Goals --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fitness_goals (
  id            bigserial PRIMARY KEY,
  user_id       text NOT NULL,
  goal_type     text CHECK (goal_type IN ('weight','body_fat','workout_frequency','distance','strength','habit','streak')),
  target_value  numeric,
  target_unit   text,
  current_value numeric DEFAULT 0,
  deadline      date,
  status        text DEFAULT 'active' CHECK (status IN ('active','achieved','abandoned')),
  parent_id     bigint,
  created_at    timestamptz DEFAULT now(),
  achieved_at   timestamptz
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fitness_goals_parent_id_fkey' AND conrelid = 'public.fitness_goals'::regclass
  ) THEN
    ALTER TABLE public.fitness_goals
      ADD CONSTRAINT fitness_goals_parent_id_fkey
      FOREIGN KEY (parent_id) REFERENCES public.fitness_goals(id) ON DELETE SET NULL;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS fitness_goals_user_status_idx
  ON public.fitness_goals (user_id, status);

-- 8. Training plans ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.fitness_plans (
  id            bigserial PRIMARY KEY,
  user_id       text NOT NULL,
  name          text,
  goal_type     text,
  methodology   text CHECK (methodology IN ('linear','undulating','periodized')),
  start_date    date,
  end_date      date,
  weeks_total   integer,
  current_week  integer DEFAULT 1,
  status        text DEFAULT 'active' CHECK (status IN ('active','completed','paused')),
  structure     jsonb,
  notes         text,
  created_at    timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS fitness_plans_user_status_idx
  ON public.fitness_plans (user_id, status);
-- Only one active plan per user
CREATE UNIQUE INDEX IF NOT EXISTS fitness_plans_one_active_per_user
  ON public.fitness_plans (user_id) WHERE status = 'active';

-- 9. Plan sessions ------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fitness_plan_sessions (
  id              bigserial PRIMARY KEY,
  plan_id         bigint NOT NULL REFERENCES public.fitness_plans(id) ON DELETE CASCADE,
  user_id         text NOT NULL,
  week_num        integer,
  day_num         integer,
  name            text,
  exercises       jsonb,
  planned_for     date,
  completed_at    timestamptz,
  completion_notes text,
  workout_log_id  bigint
);
CREATE INDEX IF NOT EXISTS fitness_plan_sessions_plan_idx
  ON public.fitness_plan_sessions (plan_id, week_num, day_num);
CREATE INDEX IF NOT EXISTS fitness_plan_sessions_user_planned_idx
  ON public.fitness_plan_sessions (user_id, planned_for);

-- Now wire the cross-FKs that needed both tables to exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fitness_workouts_plan_session_id_fkey' AND conrelid = 'public.fitness_workouts'::regclass
  ) THEN
    ALTER TABLE public.fitness_workouts
      ADD CONSTRAINT fitness_workouts_plan_session_id_fkey
      FOREIGN KEY (plan_session_id) REFERENCES public.fitness_plan_sessions(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fitness_plan_sessions_workout_log_id_fkey' AND conrelid = 'public.fitness_plan_sessions'::regclass
  ) THEN
    ALTER TABLE public.fitness_plan_sessions
      ADD CONSTRAINT fitness_plan_sessions_workout_log_id_fkey
      FOREIGN KEY (workout_log_id) REFERENCES public.fitness_workouts(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================
-- PostgREST grants — same pattern as 001_schema.sql
-- ============================================================
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN
    SELECT unnest(ARRAY[
      'fitness_profile',
      'fitness_meal_memory',
      'fitness_meals',
      'fitness_workouts',
      'fitness_body',
      'fitness_hydration',
      'fitness_goals',
      'fitness_plans',
      'fitness_plan_sessions'
    ])
  LOOP
    EXECUTE format('GRANT ALL ON TABLE public.%I TO anon', t);
    EXECUTE format('GRANT ALL ON TABLE public.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role', t);
  END LOOP;
END $$;

-- Sequences for bigserial PKs
DO $$
DECLARE
  s text;
BEGIN
  FOR s IN
    SELECT unnest(ARRAY[
      'fitness_meal_memory_id_seq',
      'fitness_meals_id_seq',
      'fitness_workouts_id_seq',
      'fitness_body_id_seq',
      'fitness_hydration_id_seq',
      'fitness_goals_id_seq',
      'fitness_plans_id_seq',
      'fitness_plan_sessions_id_seq'
    ])
  LOOP
    EXECUTE format('GRANT ALL ON SEQUENCE public.%I TO anon', s);
    EXECUTE format('GRANT ALL ON SEQUENCE public.%I TO authenticated', s);
    EXECUTE format('GRANT ALL ON SEQUENCE public.%I TO service_role', s);
  END LOOP;
END $$;

-- Tell PostgREST to reload its schema cache
NOTIFY pgrst, 'reload schema';
