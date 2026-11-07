# Legacy SQL bootstrap files

These two SQL files are retained only as historical reference:

- `001_initial_erp_core.sql`
- `002_hr_returns_transfers.sql`

They are not part of the current hosted database migration ledger and must not be run against the existing EBS PRO project. The authoritative migration stream is the timestamped set in `supabase/migrations/`, which now matches all 182 versions recorded in the hosted Supabase migration history.

For a fresh environment, use the timestamped migrations in order and perform a clean-room replay in a separate disposable database before treating the rebuild as certified. Never reset or recreate the production database to test this.
