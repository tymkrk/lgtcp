
declare @script_name_insert_tb_payroll_type_mapping_2024 nvarchar(100) = 'insert_tb_payroll_type_mapping_2024'

if not exists (select top 1 1 from [dbo].[_tb_one_time_scripts_release_log] where script_name = @script_name_insert_tb_payroll_type_mapping_2024)
begin

	insert into _tb_payroll_type_mapping
		(year
		,payroll_type_code
		,paid_field_code
		,target_field_code
		,target_min_field_code
		,target_max_field_code
		,plan_id)
			select	2024,	2020,	NULL											,'PaidBonus_CRP-LGT-TBProfStaff_2024'	,NULL										,NULL									,	13
	union	select	2024,	2070,	NULL											,'PaidBonus_CRP-LGT-DiscrBonus_2024'	,NULL										,NULL									,	13
	union	select	2024,	2071,	NULL											,'PaidBonus_CRP-LGT-ExitBonus_2024'		,NULL										,NULL									,	13
	union	select	2024,	2080,	NULL											,'PaidBonus_CRP-LGT-SalesComm_2024'		,NULL										,NULL									,	13
	union	select	2024,	2100,	NULL											,'PaidBonus_CRP-LGT-PEP_2024'			,NULL										,NULL									,	13
	union	select	2025,	2020,	'TargetBonus_CRP-LGT-Target_TBProfStaff_2024'	,NULL									,NULL										,NULL									,	13
	union	select	2025,	2100,	NULL											,NULL									,'TargetBonus_CRP-LGT-Target_PEmin_2024'	,'TargetBonus_CRP-LGT-Target_PEmax_2024',	13
	union	select	2024,	2070,	NULL											'PaidBonus_CRP-LGT-GIMPerformance_2024'	,NULL										,NULL									,	13

	insert into [dbo].[_tb_one_time_scripts_release_log]
		(script_name
		,applied_on)
	select @script_name_insert_tb_payroll_type_mapping_2024, GETDATE()
end
