-- Fix route updates: the shared updated_at trigger writes NEW.updated_at.
alter table public.sales_routes
  add column if not exists updated_at timestamptz not null default now();
