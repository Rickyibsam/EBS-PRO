-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.guard_purchase_debit_note_posting()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if old.status='draft' and new.status='draft'
   and (to_jsonb(new)-array['subtotal'])=(to_jsonb(old)-array['subtotal'])
 then return new;end if;
 if old.status='draft' and new.status='posted'
   and (to_jsonb(new)-array['status','posted_by','posted_at'])=(to_jsonb(old)-array['status','posted_by','posted_at'])
 then return new;end if;
 raise exception 'Posted supplier debit notes are immutable';
end $$;
