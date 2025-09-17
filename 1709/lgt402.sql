
select * into _tb_employee_compensation_2025_09_17 from _tb_employee_compensation  

declare @id_payroll_code_ltis nvarchar(20) = (select top 1 PayrollTypeCode from _ref_PayrollType where PayrollTypeDescription = 'LTIS'),
	@id_plan int = (select top 1 id_plan from k_m_plans where name_plan = 'Compensation Review Process 2024')

update _ref_PayrollType set IsActive = 1 where PayrollTypeCode = @id_payroll_code_ltis

insert into _tb_payroll_type_mapping  (year,payroll_type_code, paid_field_code, plan_id)
select 2025, @id_payroll_code_ltis, 'LTIS_CRP-LGT-LTISY+1_2024', @id_plan

exec sp_load_process_data_to_tables @id_plan
