-- Cover branch foreign keys without changing or rewriting business data.
create index if not exists fixed_assets_branch_id_idx
  on public.fixed_assets (branch_id)
  where branch_id is not null;

create index if not exists journal_entries_branch_id_idx
  on public.journal_entries (branch_id)
  where branch_id is not null;
