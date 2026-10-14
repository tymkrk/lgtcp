/*
TEST ONLY. Run this entire batch in SSMS against the TEST database.
Set @ExpectedDatabase below to its exact name before running.

Creates 20 fictional employees, personnel numbers 99000001..99000020.
First names are visibly numbered TEST-01 Avery through TEST-20 Taylor.
Uses existing employees only as templates for valid organizational codes,
job/title codes and manager/approver assignments. Personal data and amounts
are generated, not copied. No login accounts or external notifications.

Includes active CRP payee history, population membership, process steps,
default/calculated values and compensation history for PlanYear-2..PlanYear.
Existing population definitions still control eligibility and access.
LTIS allocations, identified-staff status and completed workflow approvals
are separate business events and are not fabricated by this seed.

IMPORTANT: sp_publish_Hierarchy rebuilds ALL hierarchy/security in TEST
from _tb_hierarchy_data (including existing unpublished changes), adjusts
profiles/access grants, and refreshes the entire CRP reporting dataset.
Run when other TEST activity is paused. The enclosing transaction includes
these changes. Existing employee compensation/process inputs are not reset.

Requires exactly one active, configured CRP and an eligible existing employee
with organization, job, title and hierarchy. Optionally set @TemplateIdPayee
to choose that employee; otherwise up to 20 valid templates are cycled.
Duplicate personnel numbers cause an error BEFORE writes; to seed another
batch change @PersonnelNumberBase. This is intentionally not an overwrite.

Prepared from repository schemas; not executed against a live database.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedDatabase sysname = N'lgttest'; -- EDIT if TEST has another name.
DECLARE @PersonnelNumberBase int = 99000000;
DECLARE @TemplateIdPayee int = NULL; -- Optional existing TEST employee idPayee.
DECLARE @UserId int = -1;
DECLARE @BatchTag nvarchar(255) = N'TEST dummy employee seed 2026-10-14';
DECLARE @Now datetime = GETDATE();

IF DB_NAME() <> @ExpectedDatabase OR LOWER(DB_NAME()) NOT LIKE N'%test%'
    THROW 51000, 'Select the TEST database and set @ExpectedDatabase to its exact name.', 1;
IF @@TRANCOUNT <> 0
    THROW 51000, 'Run as a standalone batch, outside an existing transaction.', 1;
IF @PersonnelNumberBase < 1 OR @PersonnelNumberBase > 2147483627
    THROW 51000, 'Personnel number base is outside the supported integer range.', 1;
IF (SELECT COUNT(*) FROM dbo._tb_ProcessDefinition WHERE IsActive = 1) <> 1
    THROW 51000, 'Exactly one active CRP process is required.', 1;

DECLARE @PlanId int, @PlanYear int, @FreezeDate date, @PlanStart datetime, @PlanEnd datetime;
SELECT @PlanId = d.id_plan, @PlanYear = d.PlanYear, @FreezeDate = d.FreezeDate,
       @PlanStart = p.start_date_plan, @PlanEnd = p.end_date_plan
FROM dbo._tb_ProcessDefinition d
JOIN dbo.k_m_plans p ON p.id_plan = d.id_plan
WHERE d.IsActive = 1;
IF @PlanId IS NULL OR @PlanYear NOT BETWEEN 1905 AND 2095 OR @PlanYear IS NULL
   OR @FreezeDate IS NULL OR @PlanStart IS NULL OR @PlanEnd IS NULL
    THROW 51000, 'Active process dates/year/plan are missing or unsupported.', 1;

DECLARE @EntryDate date = DATEFROMPARTS(@PlanYear - 3, 1, 1);
DECLARE @Snapshot date = CASE WHEN CONVERT(date, GETDATE()) < @FreezeDate
                             THEN CONVERT(date, GETDATE()) ELSE @FreezeDate END;
IF @Snapshot < @EntryDate
    THROW 51000, 'Active process is too far in the future for this seed.', 1;

DECLARE @SalaryCode nvarchar(10), @BonusCode nvarchar(10);
SELECT TOP (1) @SalaryCode = PayrollTypeCode FROM dbo._ref_PayrollType
WHERE PayrollTypeTechnicalCode = N'BASIC_SALARY' AND IsActive = 1 AND ISNULL(IsDeleted, 0) = 0
  AND ISNULL(FrequencyID,N'') <> N'Hourly'
ORDER BY Priority, PayrollTypeCode;
SELECT TOP (1) @BonusCode = PayrollTypeCode FROM dbo._ref_PayrollType
WHERE PayrollTypeTechnicalCode = N'TARGET_BONUS_PROF_STAFF' AND IsActive = 1 AND ISNULL(IsDeleted, 0) = 0
ORDER BY Priority, PayrollTypeCode;
IF @SalaryCode IS NULL OR @BonusCode IS NULL
    THROW 51000, 'Active BASIC_SALARY and TARGET_BONUS_PROF_STAFF payroll codes are required.', 1;

DROP TABLE IF EXISTS #SeedEmployees;
CREATE TABLE #SeedEmployees
(
    N int PRIMARY KEY, PersonnelNumber int NOT NULL UNIQUE,
    FirstName nvarchar(50) NOT NULL, LastName nvarchar(50) NOT NULL,
    Email nvarchar(100) NOT NULL, TemplateIdPayee int NULL, IdPayee int NULL,
    Salary decimal(32,2) NOT NULL, Bonus decimal(32,2) NOT NULL, FTE decimal(5,4) NOT NULL
);
INSERT #SeedEmployees (N, PersonnelNumber, FirstName, LastName, Email, Salary, Bonus, FTE)
SELECT n, @PersonnelNumberBase+n, CONCAT(N'TEST-',RIGHT(CONCAT(N'0',n),2),N' ',FirstName), N'Dummy '+LastName,
       CONCAT(N'test.employee.', @PersonnelNumberBase+n, N'@example.invalid'),
       90000+n*3500, 12000+n*700, CASE WHEN n%4=0 THEN 0.8 ELSE 1 END
FROM (VALUES
 (1,N'Avery',N'Brook'),(2,N'Blake',N'Cedar'),(3,N'Casey',N'Dale'),(4,N'Drew',N'Elm'),
 (5,N'Emery',N'Field'),(6,N'Finley',N'Grove'),(7,N'Harper',N'Hill'),(8,N'Jamie',N'Ivy'),
 (9,N'Jordan',N'Lake'),(10,N'Kai',N'Meadow'),(11,N'Logan',N'Moss'),(12,N'Morgan',N'North'),
 (13,N'Parker',N'Oak'),(14,N'Quinn',N'Pine'),(15,N'Reese',N'Reed'),(16,N'Riley',N'River'),
 (17,N'Rowan',N'Stone'),(18,N'Sage',N'Vale'),(19,N'Skyler',N'West'),(20,N'Taylor',N'Wood')
) v(n,FirstName,LastName);

-- Only templates that already participate in this CRP and its hierarchy.
DROP TABLE IF EXISTS #Templates;
SELECT ROW_NUMBER() OVER (ORDER BY t.IdPayee) AS TemplateNumber, t.*
INTO #Templates
FROM (
 SELECT DISTINCT TOP (20) i.IdPayee
 FROM dbo._tb_employee_information i
 JOIN dbo.k_m_plans_payees_steps s ON s.id_payee = i.IdPayee AND s.id_plan = @PlanId
 JOIN dbo._tb_hierarchy_data h ON h.Emp_IdPayee = i.IdPayee
 WHERE (@TemplateIdPayee IS NULL OR i.IdPayee = @TemplateIdPayee)
   AND i.LeavingDate IS NULL
   AND i.Country = N'CHE' -- generated compensation is CHF; use a Swiss template.
   AND i.EmployeeClass IN (SELECT EmployeeClassCode FROM dbo._ref_EmployeeClass)
   AND h.FirstInput_Idpayee IS NOT NULL AND h.FinalInput_IdPayee IS NOT NULL
   AND i.IdPayee NOT IN (SELECT IdPayee FROM dbo.py_Payee
                        WHERE TRY_CONVERT(int, codePayee) BETWEEN @PersonnelNumberBase+1 AND @PersonnelNumberBase+20)
   AND EXISTS (SELECT 1 FROM dbo._tb_employee_organization o
               JOIN dbo._ref_CostCenter cc ON cc.CostCenterCode=o.CostCenter
               JOIN dbo._ref_BusinessUnit bu ON bu.BusinessUnitCode=o.BusinessUnit
               JOIN dbo._ref_BusinessArea ba ON ba.BusinessAreaCode=o.BusinessArea
               JOIN dbo._ref_Department dp ON dp.DepartmentCode=o.Department
               JOIN dbo._ref_LegalEntity le ON le.CompanyCode=o.LegalEntity
               WHERE o.IdPayee=i.IdPayee AND @Snapshot BETWEEN o.EffectiveDate AND o.EndDate)
   AND EXISTS (SELECT 1 FROM dbo._tb_employee_Job j JOIN dbo._ref_JobCode r ON r.JobCode=j.JobCode
               WHERE j.IdPayee=i.IdPayee AND @Snapshot BETWEEN j.EffectiveDate AND j.EndDate)
   AND EXISTS (SELECT 1 FROM dbo._tb_employee_Title j JOIN dbo._ref_JobTitle r ON r.JobTitleCode=j.TitleCode
               WHERE j.IdPayee=i.IdPayee AND @Snapshot BETWEEN j.EffectiveDate AND j.EndDate)
 ORDER BY i.IdPayee
) t;
DECLARE @TemplateCount int = (SELECT COUNT(*) FROM #Templates);
IF @TemplateCount = 0
    THROW 51000, 'No eligible Swiss CRP template with valid organization/job/title/hierarchy found. Set @TemplateIdPayee or review template filters.', 1;
UPDATE e SET TemplateIdPayee = t.IdPayee
FROM #SeedEmployees e JOIN #Templates t ON t.TemplateNumber = (e.N-1)%@TemplateCount+1;

BEGIN TRY
    BEGIN TRANSACTION;
    -- Lock the reserved range while checking and inserting this batch.
    IF EXISTS (SELECT 1 FROM dbo.py_Payee p WITH (UPDLOCK,HOLDLOCK)
               JOIN #SeedEmployees e ON TRY_CONVERT(int,p.codePayee)=e.PersonnelNumber)
       OR EXISTS (SELECT 1 FROM dbo._tb_employee_information i
                  JOIN #SeedEmployees e ON TRY_CONVERT(int,i.PersonnelNumber)=e.PersonnelNumber)
        THROW 51000, 'A reserved personnel number already exists. Change the base; existing employees will not be overwritten.', 1;

    -- Same payee fields as sp_global_payee_creation, scoped to this batch.
    INSERT dbo.py_Payee (codePayee,email,lastname,firstname,is_active)
    SELECT CONVERT(nvarchar(15),PersonnelNumber),Email,LastName,FirstName,1 FROM #SeedEmployees;
    UPDATE e SET IdPayee=p.idPayee FROM #SeedEmployees e
    JOIN dbo.py_Payee p ON p.codePayee=CONVERT(nvarchar(15),e.PersonnelNumber);

    INSERT dbo._tb_employee_information
    (IdPayee,PersonnelNumber,Name,FirstName,BirthDate,Gender,EntryDate,LeavingDate,
     Adress,PostalCode,City,Canton,Country,EmployeeClass,EMailAddress,Infotext,
     id_user,CreatedDate,ModificationDate,ParentId,pipeline_processing_id,file_processing_id)
    SELECT e.IdPayee,e.PersonnelNumber,e.LastName,e.FirstName,DATEFROMPARTS(1980+e.N%15,1+e.N%12,1+e.N%27),
           CASE WHEN e.N%2=0 THEN N'F' ELSE N'M' END,@EntryDate,NULL,
           CONCAT(N'Fictional Test Street ',e.N),N'8000',N'Zurich',N'ZH',N'CHE',i.EmployeeClass,
           e.Email,@BatchTag,@UserId,@Now,@Now,1,-9999,-9999
    FROM #SeedEmployees e JOIN dbo._tb_employee_information i ON i.IdPayee=e.TemplateIdPayee;

    INSERT dbo._tb_employee_organization
    (IdPayee,PersonnelNumber,EffectiveDate,EndDate,ReportManager,CostCenter,BusinessUnit,BusinessArea,
     Department,LegalEntity,id_user,CreatedDate,ModificationDate,ParentId,pipeline_processing_id,file_processing_id)
    SELECT e.IdPayee,e.PersonnelNumber,@EntryDate,'29991231',o.ReportManager,o.CostCenter,o.BusinessUnit,
           o.BusinessArea,o.Department,o.LegalEntity,@UserId,@Now,@Now,1,-9999,-9999
    FROM #SeedEmployees e CROSS APPLY
    (SELECT TOP (1) o.* FROM dbo._tb_employee_organization o
     JOIN dbo._ref_CostCenter cc ON cc.CostCenterCode=o.CostCenter
     JOIN dbo._ref_BusinessUnit bu ON bu.BusinessUnitCode=o.BusinessUnit
     JOIN dbo._ref_BusinessArea ba ON ba.BusinessAreaCode=o.BusinessArea
     JOIN dbo._ref_Department dp ON dp.DepartmentCode=o.Department
     JOIN dbo._ref_LegalEntity le ON le.CompanyCode=o.LegalEntity
     WHERE o.IdPayee=e.TemplateIdPayee
     AND @Snapshot BETWEEN o.EffectiveDate AND o.EndDate ORDER BY o.EffectiveDate DESC,o.employeeOrganizationId DESC) o;

    INSERT dbo._tb_employee_Job
    (IdPayee,PersonnelNumber,EffectiveDate,EndDate,JobCode,id_user,CreatedDate,ModificationDate,ParentId,pipeline_processing_id,file_processing_id)
    SELECT e.IdPayee,e.PersonnelNumber,@EntryDate,'29991231',j.JobCode,@UserId,@Now,@Now,1,-9999,-9999
    FROM #SeedEmployees e CROSS APPLY
    (SELECT TOP (1) j.JobCode FROM dbo._tb_employee_Job j JOIN dbo._ref_JobCode r ON r.JobCode=j.JobCode
     WHERE j.IdPayee=e.TemplateIdPayee AND @Snapshot BETWEEN j.EffectiveDate AND j.EndDate
     ORDER BY j.EffectiveDate DESC,j.employeeJobId DESC) j;

    INSERT dbo._tb_employee_Title
    (IdPayee,PersonnelNumber,EffectiveDate,EndDate,TitleCode,id_user,CreatedDate,ModificationDate,ParentId,pipeline_processing_id,file_processing_id)
    SELECT e.IdPayee,e.PersonnelNumber,@EntryDate,'29991231',j.TitleCode,@UserId,@Now,@Now,1,-9999,-9999
    FROM #SeedEmployees e CROSS APPLY
    (SELECT TOP (1) j.TitleCode FROM dbo._tb_employee_Title j JOIN dbo._ref_JobTitle r ON r.JobTitleCode=j.TitleCode
     WHERE j.IdPayee=e.TemplateIdPayee AND @Snapshot BETWEEN j.EffectiveDate AND j.EndDate
     ORDER BY j.EffectiveDate DESC,j.employeeTitleId DESC) j;

    INSERT dbo._tb_employee_fte
    (IdPayee,PersonnelNumber,EffectiveDate,EndDate,FTE,id_user,CreatedDate,ModificationDate,ParentId,pipeline_processing_id,file_processing_id)
    SELECT IdPayee,PersonnelNumber,@EntryDate,'29991231',FTE,@UserId,@Now,@Now,1,-9999,-9999 FROM #SeedEmployees;

    -- Non-overlapping annual salary and bonus history; current records remain open.
    INSERT dbo._tb_employee_compensation
    (IdPayee,PersonnelNumber,PayrollType,AwardDate,EndDate,TargetValueMin,TargetValueMax,
     TargetValue,PaidDate,PaidValue,Currency,id_user,CreatedDate,ModificationDate,ParentId,pipeline_processing_id,file_processing_id)
    SELECT e.IdPayee,e.PersonnelNumber,c.PayrollType,DATEFROMPARTS(@PlanYear+y.OffsetYear,1,1),
           CASE WHEN y.OffsetYear=0 THEN CONVERT(date,'29991231') ELSE DATEFROMPARTS(@PlanYear+y.OffsetYear,12,31) END,
           NULL,NULL,c.TargetValue,
           CASE WHEN y.OffsetYear<0 THEN DATEFROMPARTS(@PlanYear+y.OffsetYear,12,20) END,
           c.PaidValue,N'CHF',@UserId,@Now,@Now,1,-9999,-9999
    FROM #SeedEmployees e CROSS JOIN (VALUES(-2),(-1),(0)) y(OffsetYear)
    CROSS APPLY (VALUES
      (@SalaryCode,CONVERT(decimal(32,2),NULL),CONVERT(decimal(32,2),e.Salary*(1+y.OffsetYear*0.03))),
      (@BonusCode,CONVERT(decimal(32,2),e.Bonus*(1+y.OffsetYear*0.05)),
       CONVERT(decimal(32,2),CASE WHEN y.OffsetYear<0 THEN e.Bonus*(1+y.OffsetYear*0.05)*0.9 END))
    ) c(PayrollType,TargetValue,PaidValue);

    INSERT dbo._tb_hierarchy_data
    (Emp_IdPayee,Emp_Id,Emp_FirstName,Emp_Lastname,Emp_ShortSign,Mgr_IdPayee,Mgr_ID,Mgr_FirstName,Mgr_LastName,
     FirstInput_Idpayee,FirstInput_Id,FirstInput_ShortSign,SecondInput_IdPayee,SecondInput_Id,SecondInput_ShortSign,
     View_IdPayee,View_Id,View_ShortSign,FinalInput_IdPayee,FinalInput_Id,FinalInput_ShortSign,ParentId)
    SELECT e.IdPayee,e.PersonnelNumber,e.FirstName,e.LastName,CONCAT(N'T',RIGHT(CONCAT(N'0000',e.N),4)),
           h.Mgr_IdPayee,h.Mgr_ID,h.Mgr_FirstName,h.Mgr_LastName,
           h.FirstInput_Idpayee,h.FirstInput_Id,h.FirstInput_ShortSign,h.SecondInput_IdPayee,h.SecondInput_Id,h.SecondInput_ShortSign,
           h.View_IdPayee,h.View_Id,h.View_ShortSign,h.FinalInput_IdPayee,h.FinalInput_Id,h.FinalInput_ShortSign,1
    FROM #SeedEmployees e CROSS APPLY
    (SELECT TOP (1) * FROM dbo._tb_hierarchy_data h WHERE h.Emp_IdPayee=e.TemplateIdPayee
     AND h.FirstInput_Idpayee IS NOT NULL AND h.FinalInput_IdPayee IS NOT NULL ORDER BY hierarchydataId DESC) h;

    INSERT dbo.py_PayeeHisto (start_date_histo,end_date_histo,idPayee,codePayee)
    SELECT @PlanStart,@PlanEnd,IdPayee,CONVERT(nvarchar(15),PersonnelNumber) FROM #SeedEmployees;

    -- Refresh actual populations attached to this plan; never force employees
    -- into populations whose filters exclude them.
    DECLARE @PopulationId int;
    DECLARE populations CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT p.idPop FROM dbo.k_m_plans_affectations a
    JOIN dbo.pop_Population p ON p.idPop=a.id_assignee
    WHERE a.id_plan=@PlanId AND a.type_affectation='P';
    OPEN populations;
    FETCH NEXT FROM populations INTO @PopulationId;
    WHILE @@FETCH_STATUS=0
    BEGIN
        EXEC dbo.sp_global_refresh_population @id_pop=@PopulationId;
        FETCH NEXT FROM populations INTO @PopulationId;
    END;
    CLOSE populations;
    DEALLOCATE populations;

    -- The same assignment fields as _sp_process_conf_refresh_payees_steps,
    -- restricted to new employees; one population assignment per employee.
    INSERT dbo.k_m_plans_payees_steps
    (id_plan,id_assignment,id_payee,start_step,end_step,id_user_create,date_create_assignment,
     id_user_update,date_update_assignment,locked,frequency_index)
    SELECT @PlanId,a.id_affectation,e.IdPayee,@PlanStart,@PlanEnd,@UserId,@Now,NULL,NULL,0,1
    FROM #SeedEmployees e CROSS APPLY
    (SELECT TOP (1) a.id_affectation FROM dbo.k_m_plans_affectations a
     JOIN dbo.pop_Population p ON p.idPop=a.id_assignee
     JOIN dbo.pop_VersionContent v ON v.idPopVersion=p.lastVersion AND v.idColl=e.IdPayee
     WHERE a.id_plan=@PlanId AND a.type_affectation='P' ORDER BY a.id_affectation) a;
    IF (SELECT COUNT(*) FROM dbo.k_m_plans_payees_steps s JOIN #SeedEmployees e ON e.IdPayee=s.id_payee
        WHERE s.id_plan=@PlanId) <> 20
        THROW 51000, 'Not all employees qualify for the attached CRP populations. Review population filters/templates; batch rolled back.', 1;

    DECLARE @AuditStart int = ISNULL((SELECT MAX(LogId) FROM dbo._tb_audit_log),0);
    EXEC dbo.sp_publish_Hierarchy @qc_audit_key=-1, @UserId=@UserId;
    IF XACT_STATE() <> 1 OR @@TRANCOUNT <> 1
        THROW 51000, 'Hierarchy publishing did not preserve the seed transaction. Inspect _tb_audit_log.', 1;
    IF EXISTS (SELECT 1 FROM dbo._tb_audit_log WHERE LogId>@AuditStart AND ErrorFlag=1
               AND SubProcess IN (N'sp_publish_Hierarchy',N'_sp_lgt_refresh_crp_process_dataset'))
        THROW 51000, 'Hierarchy/dataset procedure logged an error. Inspect _tb_audit_log.', 1;

    -- Match the application's employee-specific master-data save sequence.
    DECLARE @IdPayee int;
    DECLARE employees CURSOR LOCAL FAST_FORWARD FOR SELECT IdPayee FROM #SeedEmployees ORDER BY N;
    OPEN employees;
    FETCH NEXT FROM employees INTO @IdPayee;
    WHILE @@FETCH_STATUS=0
    BEGIN
        EXEC dbo.sp_refresh_process_default_values_employee @idpayee=@IdPayee;
        EXEC dbo._sp_refresh_calculated_fields_employee @idpayee=@IdPayee;
        FETCH NEXT FROM employees INTO @IdPayee;
    END;
    CLOSE employees;
    DEALLOCATE employees;

    -- Fail before commit if any employee is missing a required integration.
    IF EXISTS
    (SELECT 1 FROM #SeedEmployees e WHERE e.IdPayee IS NULL
     OR NOT EXISTS (SELECT 1 FROM dbo._tb_lgt_crp_process_dataset d WHERE d.IdPayee=e.IdPayee AND d.id_plan=@PlanId)
     OR NOT EXISTS (SELECT 1 FROM dbo.hm_NodelinkPublished h WHERE h.idChild=e.IdPayee AND h.idType=14)
     OR NOT EXISTS (SELECT 1 FROM dbo.k_m_plans_payees_steps s JOIN dbo.k_m_values v ON v.id_step=s.id_step
                    WHERE s.id_payee=e.IdPayee AND s.id_plan=@PlanId)
     OR (SELECT COUNT(*) FROM dbo._tb_employee_compensation c WHERE c.IdPayee=e.IdPayee)<>6)
        THROW 51000, 'Employee integration verification failed; batch rolled back.', 1;

    COMMIT TRANSACTION;
    SELECT e.PersonnelNumber,e.FirstName,e.LastName,e.IdPayee,e.TemplateIdPayee,
           @PlanId AS ActivePlanId,@PlanYear AS PlanYear,e.Salary AS CurrentSalaryCHF,e.Bonus AS TargetBonusCHF,e.FTE,
           N'Created; CRP, hierarchy and compensation history verified' AS Result
    FROM #SeedEmployees e ORDER BY e.N;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    -- Publishing uses IDENTITY_INSERT internally; clear it after a failure.
    SET IDENTITY_INSERT dbo.hm_NodeTree OFF;
    SET IDENTITY_INSERT dbo.hm_NodeTreePublished OFF;
    THROW;
END CATCH;
