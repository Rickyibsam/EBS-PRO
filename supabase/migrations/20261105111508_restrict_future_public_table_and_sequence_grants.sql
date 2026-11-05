-- Require explicit Data API grants for future public tables and sequences.
-- Existing table/sequence privileges and data are not changed.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
