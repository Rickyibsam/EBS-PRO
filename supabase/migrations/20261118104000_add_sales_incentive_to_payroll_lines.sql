-- Sales incentive is part of payroll net compensation and must exist on a clean replay.
alter table public.payroll_lines
  add column if not exists sales_incentive numeric not null default 0;
