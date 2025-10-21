/****** Object:  StoredProcedure [dbo].[sp_load_process_data_to_tables]    Script Date: 10/21/2025 2:02:16 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_load_process_data_to_tables_tk]
(@plan_id INT)
AS 

BEGIN 


BEGIN TRY
	BEGIN TRANSACTION trans_insert_values;
	declare @sql nvarchar(max)



/*
	/* TITLE TABLE BACKUP */
	DECLARE @sql NVARCHAR(MAX) = 'SELECT * INTO _tb_employee_Title'+'_'+convert(varchar, getdate(), 112)	 + replace(convert(varchar, getdate(),108),':','')+' FROM _tb_employee_Title'

	EXEC sys.sp_executesql @sql

	
	INSERT INTO _tb_employee_Title (IdPayee, PersonnelNumber, EffectiveDate, EndDate, TitleCode, id_user, CreatedDate, ModificationDate, ParentId)
	SELECT  
		vcpt.IdPayee
	,	vcpt.PersonnelNumber
	,	@next_award_date
	,	'2999-01-01' AS EndDate
	,	kmv.input_value AS TitleCode
	,	@id_user, GETDATE() AS CreatedDate
	,	NULL AS ModificationDate
	,	1 AS ParentId
	FROM _vw_CRP_Process_Template vcpt
	JOIN k_m_plans_payees_steps kmpps 
		ON vcpt.id_plan = kmpps.id_plan 
		AND vcpt.idPayee = kmpps.id_payee
	JOIN k_m_values kmv 
		ON kmpps.id_step = kmv.id_step
	JOIN k_m_fields kmf 
		ON kmv.id_field = kmf.id_field
	LEFT JOIN _tb_employee_Title t 
		ON T.EffectiveDate = @next_award_date 
		AND t.IdPayee = vcpt.IdPayee
	WHERE kmf.id_field = @new_title_id_field
	AND NULLIF(kmv.input_value,'') IS NOT NULL
	AND kmpps.id_plan = @plan_id
	AND t.employeeTitleId IS NULL


    /* UPDATE TITLE END DATES */
   	;WITH cte AS (
	SELECT
			PersonnelNumber
		,	EffectiveDate
		,	Lead(DATEADD("day",-1,EffectiveDate),1,'01-01-2999') over (PARTITION BY PersonnelNumber order by EffectiveDate) AS EndDate
	FROM _tb_employee_Title
	)
	UPDATE f
	SET f.EndDate = c.EndDate
	FROM _tb_employee_Title f 
	JOIN  cte c 
		ON f.PersonnelNumber = c.PersonnelNumber 
		AND f.EffectiveDate = c.EffectiveDate
*/

	/* COMPENSATION TABLE BACKUP */
	SET @sql  = 'SELECT * INTO _tb_employee_compensation'+'_'+convert(varchar, getdate(), 112)	 + replace(convert(varchar, getdate(),108),':','')+' FROM _tb_employee_compensation'

	EXEC sys.sp_executesql @sql

declare @now date = getdate()

drop table if exists #fields
drop table if exists #payee_payroll
drop table if exists #results

select 
	f.code_field,
	v.input_value,
	psp.id_payee
into #fields
from k_m_plans p
join k_m_plans_payees_steps psp
	on psp.id_plan = p.id_plan
join k_m_values v
	on v.id_step = psp.id_step
join k_m_fields f
	on f.id_field = v.id_field
where p.id_plan = @plan_id
	--and id_control_type <> -5
	and type_value = 2
	and v.input_value is not null


select distinct
	f.id_payee,
	ptm.payroll_type_code,
	ptm.id as ptm_id
into #payee_payroll
from #fields f
join _tb_payroll_type_mapping ptm
	on f.code_field in (ptm.paid_field_code, ptm.target_field_code, ptm.target_max_field_code, ptm.target_min_field_code)
	and ptm.plan_id = @plan_id -- @plan_id
where f.id_payee is not null and ptm.payroll_type_code is not null
--	and f.id_payee = @idpayee or @idpayee  is null

select distinct
	pp.id_payee,
	pt.PersonnelNumber,
	pp.payroll_type_code,
	ptm.year,
	max(f_paid.input_value		)	as PaidValue,
	max(f_target.input_value	)	as TargetValue,
	max(f_min.input_value		)	as TargetValueMin,
	max(f_max.input_value		)	as TargetValueMax,
	max(pt.Target_Bonus_Currency)	as Currency
into #results
from #payee_payroll pp
join _tb_payroll_type_mapping ptm
	on ptm.id = pp.ptm_id
join _vw_CRP_Process_Template pt
	on pt.id_plan = @plan_id
	and pt.idPayee = pp.id_payee
left join #fields f_paid
	on  f_paid.code_field	= ptm.paid_field_code 
	and f_paid.id_payee		= pp.id_payee
left join #fields f_target
	on  f_target.code_field	= ptm.target_field_code
	and f_target.id_payee	= pp.id_payee
left join #fields f_min
	on  f_min.code_field	= ptm.target_min_field_code
	and f_min.id_payee		= pp.id_payee
left join #fields f_max
	on  f_max.code_field	= ptm.target_max_field_code
	and f_max.id_payee		= pp.id_payee
group by 
	pp.id_payee,
	pt.PersonnelNumber,
	pp.payroll_type_code,
	ptm.year



;with cte as 
(
select  *,
	ROW_NUMBER() over ( 
		partition by idPayee, PayrollType,fs.fiscalYear
	order by AwardDate desc) as rn
from _tb_employee_compensation
outer apply
	(select case when month(awardDate) >=4 then year(awarddate) else year(awarddate) - 1 end as fiscalYear) fs
where fs.fiscalYear > 2023
	)

merge cte as c
using #results as r
on r.id_payee = c.IdPayee
	and r.payroll_type_code = c.PayrollType
	and r.year	= c.fiscalYear
	and c.rn = 1
when matched then update set
	c.TargetValueMin	= COALESCE(r.TargetValueMin,c.TargetValueMin)
	,c.TargetValueMax	= COALESCE(r.TargetValueMax,c.TargetValueMax)
	,c.TargetValue		= COALESCE(r.TargetValue,c.TargetValue)		
	,c.PaidDate			= IIF(r.PaidValue is not null, DATEFROMPARTS(r.year+1,4,1) , c.PaidDate)
	,c.PaidValue		= COALESCE(r.PaidValue, c.PaidValue)
	,c.Currency			= COALESCE(r.Currency,c.Currency)
	,c.modificationDate = @now
when not matched by target then insert 
	(IdPayee
	,PersonnelNumber
	,PayrollType
	,AwardDate
	,EndDate
	,TargetValueMin
	,TargetValueMax
	,TargetValue
	,PaidDate
	,PaidValue
	,Currency
	,id_user
	,CreatedDate
	,ParentId)
values
(
	r.id_payee
	,r.PersonnelNumber
	,r.payroll_type_code
	,DATEFROMPARTS(r.year,4,1)
	,'2999-01-01'
	,r.TargetValueMin
	,r.TargetValueMax
	,r.TargetValue
	,IIF(r.PaidValue is not null, DATEFROMPARTS(r.year+1,4,1) , null)
	,r.PaidValue
	,r.Currency
	,-1
	,@now
	,1
);

	DELETE FROM tb_CRP_Process_Template_archive where id_plan = @plan_id
    INSERT INTO tb_CRP_Process_Template_archive (
			id_histo
        ,	start_date_histo
        ,	end_date_histo
        ,	id_plan
        ,	name_plan
        ,	FreezeDate
        ,	idPayee
        ,	codePayee
        ,	lastname
        ,	firstname
        ,	fullname
        ,	PersonnelNumber
        ,	BirthDate
        ,	Age
        ,	Gender
        ,	EntryDate
        ,	Anniversary
        ,	LeavingDate
        ,	EmployeeClass
        ,	Org_BeginDate
        ,	Org_EndDate
        ,	Org_ReportManager
        ,	Org_CostCenter_Code
        ,	Org_CostCenter_Desc
        ,	Org_BusinessUnit_Code
        ,	Org_BusinessUnit_Desc
        ,	Org_BusinessArea_Code
        ,	Org_BusinessArea_Desc
        ,	Org_Department_Code
        ,	Org_Department_Desc
        ,	Org_LegalEntity_Code
        ,	Org_LegalEntity_Desc
        ,	FTE_BeginDate
        ,	FTE_Enddate
        ,	FTE_Current
        ,	FTE_Future
        ,	Job_BeginDate
        ,	Job_EndDate
        ,	JobCode_Current
        ,	CurrentTitleCode
        ,	CurrentTitle
        ,	has_allowances
        ,	Base_Salary_Currency
        ,	Base_Salary_Current
        ,	Bonus_Year
        ,	Bonus_Currency
        ,	Target_Bonus_Prof_Staff
        ,	Target_Bonus_Admin_Staff
        ,	Bonus_Signon
        ,	Bonus_Exit
        ,	Target_HF_Point_Min
        ,	Target_HF_Point_Max
        ,	Target_PE_Point_Min
        ,	Target_PE_Point_Max
        ,	HF_Point_Value
        ,	PE_Point_Value
        ,	LTIS_Current
        ,	Target_Bonus_Year
        ,	Target_Bonus_Currency
        ,	CRP_Eligible
        ,	Allowances
        ,	Prepayments
        ,	AllowanceName
		,	Is_Identified_Staff
)
	SELECT 
			id_histo
        ,	start_date_histo
        ,	end_date_histo
        ,	id_plan
        ,	name_plan
        ,	FreezeDate
        ,	idPayee
        ,	codePayee
        ,	lastname
        ,	firstname
        ,	fullname
        ,	PersonnelNumber
        ,	BirthDate
        ,	Age
        ,	Gender
        ,	EntryDate
        ,	Anniversary
        ,	LeavingDate
        ,	EmployeeClass
        ,	Org_BeginDate
        ,	Org_EndDate
        ,	Org_ReportManager
        ,	Org_CostCenter_Code
        ,	Org_CostCenter_Desc
        ,	Org_BusinessUnit_Code
        ,	Org_BusinessUnit_Desc
        ,	Org_BusinessArea_Code
        ,	Org_BusinessArea_Desc
        ,	Org_Department_Code
        ,	Org_Department_Desc
        ,	Org_LegalEntity_Code
        ,	Org_LegalEntity_Desc
        ,	FTE_BeginDate
        ,	FTE_Enddate
        ,	FTE_Current
        ,	FTE_Future
        ,	Job_BeginDate
        ,	Job_EndDate
        ,	JobCode_Current
        ,	CurrentTitleCode
        ,	CurrentTitle
        ,	has_allowances
        ,	Base_Salary_Currency
        ,	Base_Salary_Current
        ,	Bonus_Year
        ,	Bonus_Currency
        ,	Target_Bonus_Prof_Staff
        ,	Target_Bonus_Admin_Staff
        ,	Bonus_Signon
        ,	Bonus_Exit
        ,	Target_HF_Point_Min
        ,	Target_HF_Point_Max
        ,	Target_PE_Point_Min
        ,	Target_PE_Point_Max
        ,	HF_Point_Value
        ,	PE_Point_Value
        ,	LTIS_Current
        ,	Target_Bonus_Year
        ,	Target_Bonus_Currency
        ,	CRP_Eligible
        ,	Allowances
        ,	Prepayments
        ,	AllowanceName 
		,	Is_Identified_Staff
    FROM  _vw_CRP_Process_Template vcpt 
    WHERE id_plan=@plan_id



COMMIT TRANSACTION trans_insert_values;
	END TRY

	BEGIN CATCH
		DECLARE @ErrorFlag BIT = 1;
		DECLARE @EventText NVARCHAR(MAX) = 'End';
		DECLARE @ErrorText NVARCHAR(MAX) = ERROR_MESSAGE();
		DECLARE @ErrorLine INT = ERROR_LINE();
		DECLARE @xstate INT = XACT_STATE()

		SELECT @ErrorText

		IF @xstate != 0
			ROLLBACK TRANSACTION trans_insert_values;

		
	END CATCH
END
