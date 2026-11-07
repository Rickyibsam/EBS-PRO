-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.employees
 add column if not exists basic_salary numeric(18,2) not null default 0 check (basic_salary>=0),
 add column if not exists joining_date date,
 add column if not exists employment_type text not null default 'permanent',
 add column if not exists bank_name text,
 add column if not exists bank_account_no text;

insert into public.chart_of_accounts(tenant_id,account_code,account_name,account_type,is_control_account,is_active)
select o.id,a.code,a.name,a.type,a.control,true
from public.organizations o
cross join (values ('5200','Salaries & Wages','expense',false),('2150','Payroll Payable','liability',true),('2160','Payroll Deductions Payable','liability',true)) a(code,name,type,control)
on conflict do nothing;

create table if not exists public.payroll_runs(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 run_number text not null,
 period_start date not null,
 period_end date not null,
 pay_date date not null default current_date,
 status text not null default 'draft' check(status in ('draft','posted','void')),
 gross_total numeric(18,2) not null default 0,
 deductions_total numeric(18,2) not null default 0,
 net_total numeric(18,2) not null default 0,
 created_by uuid references auth.users(id),
 posted_by uuid references auth.users(id),
 posted_at timestamptz,
 created_at timestamptz not null default now(),
 constraint payroll_runs_period_check check(period_end>=period_start),
 constraint payroll_runs_tenant_number_uq unique(tenant_id,run_number),
 constraint payroll_runs_id_tenant_uq unique(id,tenant_id)
);
create table if not exists public.payroll_lines(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 payroll_run_id uuid not null,
 employee_id uuid not null,
 basic_salary numeric(18,2) not null default 0 check(basic_salary>=0),
 allowances numeric(18,2) not null default 0 check(allowances>=0),
 overtime numeric(18,2) not null default 0 check(overtime>=0),
 deductions numeric(18,2) not null default 0 check(deductions>=0),
 net_salary numeric(18,2) not null default 0 check(net_salary>=0),
 payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid')),
 payment_method text,
 payment_reference text,
 paid_at timestamptz,
 created_at timestamptz not null default now(),
 constraint payroll_lines_run_fk foreign key(payroll_run_id,tenant_id) references public.payroll_runs(id,tenant_id) on delete cascade,
 constraint payroll_lines_employee_fk foreign key(employee_id,tenant_id) references public.employees(id,tenant_id),
 constraint payroll_lines_run_employee_uq unique(payroll_run_id,employee_id)
);
create index if not exists payroll_runs_tenant_period_idx on public.payroll_runs(tenant_id,period_start desc);
create index if not exists payroll_lines_tenant_run_idx on public.payroll_lines(tenant_id,payroll_run_id);
alter table public.payroll_runs enable row level security;
alter table public.payroll_lines enable row level security;
grant select,insert,update on public.payroll_runs,public.payroll_lines to authenticated;
drop policy if exists payroll_runs_select on public.payroll_runs;
drop policy if exists payroll_runs_insert on public.payroll_runs;
drop policy if exists payroll_runs_update on public.payroll_runs;
drop policy if exists payroll_lines_select on public.payroll_lines;
drop policy if exists payroll_lines_insert on public.payroll_lines;
drop policy if exists payroll_lines_update on public.payroll_lines;
create policy payroll_runs_select on public.payroll_runs for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy payroll_runs_insert on public.payroll_runs for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy payroll_runs_update on public.payroll_runs for update to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy payroll_lines_select on public.payroll_lines for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy payroll_lines_insert on public.payroll_lines for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy payroll_lines_update on public.payroll_lines for update to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));

create or replace function public.post_payroll_run(p_payroll_run_id uuid)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_run public.payroll_runs%rowtype; v_user uuid:=auth.uid(); v_gross numeric; v_ded numeric; v_net numeric; v_count integer;
 v_salary uuid; v_payable uuid; v_deductions uuid; v_journal uuid; v_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_run from public.payroll_runs where id=p_payroll_run_id for update;
 if not found then raise exception 'Payroll run not found'; end if;
 if not public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Payroll posting permission required'; end if;
 if v_run.status<>'draft' then raise exception 'Only draft payroll runs can be posted'; end if;
 select coalesce(sum(basic_salary+allowances+overtime),0),coalesce(sum(deductions),0),count(*) into v_gross,v_ded,v_count from public.payroll_lines where tenant_id=v_run.tenant_id and payroll_run_id=v_run.id;
 if v_count=0 then raise exception 'Add at least one employee to the payroll run'; end if;
 v_net:=v_gross-v_ded;if v_net<0 then raise exception 'Payroll deductions cannot exceed gross salary'; end if;
 select id into v_salary from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='5200' and is_active;
 select id into v_payable from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='2150' and is_active;
 select id into v_deductions from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='2160' and is_active;
 if v_salary is null or v_payable is null or v_deductions is null then raise exception 'Payroll accounts are not configured'; end if;
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
declare v_line public.payroll_lines%rowtype; v_run public.payroll_runs%rowtype; v_user uuid:=auth.uid(); v_payable uuid; v_cash uuid; v_journal uuid; v_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_line from public.payroll_lines where id=p_payroll_line_id for update;
 if not found then raise exception 'Payroll line not found'; end if;
 select * into v_run from public.payroll_runs where id=v_line.payroll_run_id and tenant_id=v_line.tenant_id;
 if v_run.status<>'posted' then raise exception 'Post payroll run before paying salaries'; end if;
 if not public.has_tenant_role(v_line.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Payroll payment permission required'; end if;
 if v_line.payment_status='paid' then raise exception 'This salary has already been paid'; end if;
 if p_method not in ('cash','bank','cheque','online') then raise exception 'Invalid payment method'; end if;
 select id into v_payable from public.chart_of_accounts where tenant_id=v_line.tenant_id and account_code='2150' and is_active;
 select id into v_cash from public.chart_of_accounts where tenant_id=v_line.tenant_id and account_code=case when p_method in ('bank','cheque','online') then '1010' else '1000' end and is_active;
 if v_payable is null or v_cash is null then raise exception 'Payroll payable and cash/bank accounts are required'; end if;
 v_no:='EBS-SALARY-PAY-'||right(replace(v_line.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_line.tenant_id,v_no,current_date,'payroll_payment',v_line.id,'Salary payment for employee '||v_line.employee_id,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_line.tenant_id,v_journal,v_payable,v_line.net_salary,0,'Payroll payable settlement'),
 (v_line.tenant_id,v_journal,v_cash,0,v_line.net_salary,'Salary disbursement');
 update public.payroll_lines set payment_status='paid',payment_method=p_method,payment_reference=nullif(trim(p_reference),''),paid_at=now() where id=v_line.id and tenant_id=v_line.tenant_id;
 return jsonb_build_object('success',true,'status','paid','journal_entry_id',v_journal);
end $$;
revoke all on function public.post_payroll_run(uuid) from public;
revoke all on function public.pay_payroll_line(uuid,text,text) from public;
grant execute on function public.post_payroll_run(uuid) to authenticated;
grant execute on function public.pay_payroll_line(uuid,text,text) to authenticated;
