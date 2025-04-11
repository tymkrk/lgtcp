	insert into _tb_payroll_type_mapping
		(year
		,payroll_type_code
		,paid_field_code
		,target_field_code
		,target_min_field_code
		,target_max_field_code)
	select 2024, 1000,'AnnualBaseSalary_CRP-LGT-Base_JLY_2024',null,null,null union
	select 2024, 2100,'PaidBonus_CRP-LGT-PEP_2024',null,'PaidBonus_CRP-LGT-PEmin_2024','PaidBonus_CRP-LGT-PEmax_2024' union
	select 2024, 2020,'PaidBonus_CRP-LGT-TBProfStaff_2024','TargetBonus_CRP-LGT-Target_TBProfStaff_2024',null,null union
	select 2024, 2070,'PaidBonus_CRP-LGT-DiscrBonus_2024',null,null,null union
	select 2024, 2071,'PaidBonus_CRP-LGT-ExitBonus_2024',null,null,null union
	select 2024, 2080,'PaidBonus_CRP-LGT-SalesComm_2024',null,null,null
