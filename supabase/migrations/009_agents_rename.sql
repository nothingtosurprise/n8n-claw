-- ============================================================
-- 009_agents_rename.sql — rename app table agents -> claw_agents
-- ============================================================
-- Fixes Issue #35: n8n >= 2.21.4 ships a core "Agents" feature whose
-- migration CreateAgentTables1783000000000 creates a table named
-- `agents` and indexes its `projectId` column. n8n-claw already owns
-- `public.agents` (persona/config table) in the SAME database, so
-- n8n's createTable no-ops, the createIndex on projectId fails, and
-- n8n never boots.
--
-- Fix: rename the n8n-claw table to `claw_agents`, freeing the
-- `agents` name for n8n's own table.
--
-- Idempotent + safe by design:
--   * Only renames a table that has a `key` column — that uniquely
--     identifies n8n-claw's table and NEVER matches n8n's core
--     `agents` table (which has no `key` column). So if n8n already
--     created its own `agents`, this is a no-op against it.
--   * Only fires if `claw_agents` does not already exist (fresh
--     installs created it directly via 001; re-runs are no-ops).
-- ============================================================

DO $$
BEGIN
  IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'agents'
          AND column_name  = 'key'
     )
     AND NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name   = 'claw_agents'
     )
  THEN
    ALTER TABLE public.agents RENAME TO claw_agents;
    ALTER SEQUENCE IF EXISTS public.agents_id_seq RENAME TO claw_agents_id_seq;
  END IF;
END $$;
