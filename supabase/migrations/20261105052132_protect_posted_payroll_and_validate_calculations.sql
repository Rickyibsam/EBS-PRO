-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.guard_payroll_line_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_status text;begin
 select status into v_status from public.payroll_runs where id=coalesce(new.payroll_run_id,old.payroll_run_id) and tenant_id=coalesce(new.tenant_id,old.tenant_id);
 if v_status is null then raise exception 'Payroll run not found';end if;
 if tg_op='INSERT' then if v_status<>'draft' then raise exception 'Cannot add lines to a posted payroll run';end if;return new;end if;
 if tg_op='DELETE' then if v_status<>'draft' then raise exception 'Cannot delete lines from a posted payroll run';end if;return old;end if;
 if v_status='draft' then return new;end if;
 if old.payment_status='unpaid' and new.payment_status='paid'
    and new.basic_salary=old.basic_salary and new.allowances=old.allowances and new.overtime=old.overtime
    and new.deductions=old.deductions and new.net_salary=old.net_salary
    and new.employee_id=old.employee_id and new.payroll_run_id=old.payroll_run_id and new.tenant_id=old.tenant_id
    and new.payment_method in ('cash','bank','cheque','online') and new.paid_at is not null then return new;end if;
 raise exception 'Posted payroll compensation is immutable; only salary payment status can change';
end $$;
drop trigger if exists payroll_line_mutation_guard on public.payroll_lines;
create trigger payroll_line_mutation_guard before insert or update or delete on public.payroll_lines for each row execute function public.guard_payroll_line_mutation();

create or replace function public.guard_posted_payroll_run()
returns trigger language plpgsql as $$
begin
 if old.status<>'draft' then raise exception 'Posted or void payroll runs cannot be modified';end if;
 return new;
end $$;
drop trigger if exists payroll_run_mutation_guard on public.payroll_runs;
create trigger payroll_run_mutation_guard before update on public.payroll_runs for each row execute function public.guard_posted_payroll_run();

create or replace function public.post_payroll_run(p_payroll_run_id uuid)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_run public.payroll_runs%rowtype;v_user uuid:=auth.uid();v_gross numeric;v_ded numeric;v_net numeric;v_count integer;v_salary uuid;v_payable uuid;v_deductions uuid;v_journal uuid;v_no text;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_run from public.payroll_runs where id=p_payroll_run_id for update;
 if not found then raise exception 'Payroll run not found';end if;
 if not public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Payroll posting permission required';end if;
 if v_run.status<>'draft' then raise exception 'Only draft payroll runs can be posted';end if;
 if exists(select 1 from public.payroll_lines where tenant_id=v_run.tenant_id and payroll_run_id=v_run.id and (deductions>basic_salary+allowances+overtime or abs(net_salary-(basic_salary+allowances+overtime-deductions))>0.01)) then raise exception 'One or more payroll lines have invalid net salary calculations';end if;
 select coalesce(sum(basic_salary+allowances+overtime),0),coalesce(sum(deductions),0),count(*) into v_gross,v_ded,v_count from public.payroll_lines where tenant_id=v_run.tenant_id and payroll_run_id=v_run.id;
 if v_count=0 then raise exception 'Add at least one employee to the payroll run';end if;
 v_net:=v_gross-v_ded;if v_net<0 then raise exception 'Payroll deductions cannot exceed gross salary';end if;
 select id into v_salary from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='5200' and is_active;
 select id into v_payable from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='2150' and is_active;
 select id into v_deductions from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='2160' and is_active;
 if v_salary is null or v_payable is null or v_deductions is null then raise exception 'Payroll accounts are not configured';end if;
 v_no:='EBS-PAYROLL-JV-'||right(replace(v_run.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_run.tenant_id,v_no,v_run.pay_date,'payroll',v_run.id,'Payroll accrual for '||v_run.period_start||' to '||v_run.period_end,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_run.tenant_id,v_journal,v_salary,v_gross,0,'Gross payroll expense'),
 (v_run.tenant_id,v_journal,v_payable,0,v_net,'Net salaries payable');
 if v_ded>0 then insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo) values(v_run.tenant_id,v_journal,v_deductions,0,v_ded,'Employee deductions payable');end if;
 update public.payroll_runs set status='posted',gross_total=v_gross,deductions_total=v_ded,net_total=v_net,posted_by=v_user,posted_at=now() where id=v_run.id and tenant_id=v_run.tenant_id;
 return jsonb_build_object('success',true,'status','posted','gross_total',v_gross,'deductions_total',v_ded,'net_total',v_net,'journal_entry_id',v_journal);
end $$;

create or replace function public.pay_payroll_line(p_payroll_line_id uuid,p_method text,p_reference text default null)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_line public.payroll_lines%rowtype;v_run public.payroll_runs%rowtype;v_user uuid:=auth.uid();v_payable uuid;v_cash uuid;v_journal uuid;v_no text;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_line from public.payroll_lines where id=p_payroll_line_id for update;
 if not found then raise exception 'Payroll line not found';end if;
 select * into v_run from public.payroll_runs where id=v_line.payroll_run_id and tenant_id=v_line.tenant_id;
 if v_run.status<>'posted' then raise exception 'Post payroll run before paying salaries';end if;
 if not public.has_tenant_role(v_line.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Payroll payment permission required';end if;
 if v_line.payment_status='paid' then raise exception 'This salary has already been paid';end if;
 if v_line.net_salary<=0 then raise exception 'No net salary is payable for this employee';end if;
 if p_method not in ('cash','bank','cheque','online') then raise exception 'Invalid payment method';end if;
 select id into v_payable from public.chart_of_accounts where tenant_id=v_line.tenant_id and account_code='2150' and is_active;
 select id into v_cash from public.chart_of_accounts where tenant_id=v_line.tenant_id and account_code=case when p_method in ('bank','cheque','online') then '1010' else '1000' end and is_active;
 if v_payable is null or v_cash is null then raise exception 'Payroll payable and cash/bank accounts are required';end if;
 v_no:='EBS-SALARY-PAY-'||right(replace(v_line.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_line.tenant_id,v_no,current_date,'payroll_payment',v_line.id,'Salary payment for employee '||v_line.employee_id,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_line.tenant_id,v_journal,v_payable,v_line.net_salary,0,'Payroll payable settlement'),
 (v_line.tenant_id,v_journal,v_cash,0,v_line.net_salary,'Salary disbursement');
 update public.payroll_lines set payment_status='paid',payment_method=p_method,payment_reference=nullif(trim(p_reference),''),paid_at=now() where id=v_line.id and tenant_id=v_line.tenant_id;
 return jsonb_build_object('success',true,'status','paid','journal_entry_id',v_journal);
end $$;
