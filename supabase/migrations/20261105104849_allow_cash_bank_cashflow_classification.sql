-- Mark cash and bank ledger accounts explicitly for cash-flow statement classification.
alter table public.cash_flow_account_mappings drop constraint if exists cash_flow_account_mappings_classification_check;
alter table public.cash_flow_account_mappings add constraint cash_flow_account_mappings_classification_check
 check(classification in ('operating','investing','financing','cash_bank'));
