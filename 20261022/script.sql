/*
Uruchom w bazie aplikacji (SSMS). Skrypt odczytuje dane i korzysta z tabel
tymczasowych; nie uruchamia raportu i nie zmienia danych aplikacji.
Wynik 1: sprawdzone zestawy z danymi i gotowym EXEC.
Wynik 2: bledy poszczegolnych prob (jezeli wystapily).

Opcjonalne filtry ponizej pozwalaja sprawdzic konkretnego uzytkownika/profil/drzewo.
Limit dotyczy liczby prob, nie liczby znalezionych zestawow. Brak wynikow nie
oznacza braku danych w calej bazie: zwieksz limit lub zawez filtry.
Nie obejmuje wszystkich mozliwych wybranych managerow: sprawdza wlasny wezel
uzytkownika, wezly przypisane przez security oraz korzenie dla administratorow.
@idProcess i @planFilterCustom nie sa uzywane przez obecna wersje raportu.
Profil 1 oraz region USA ukrywaja wiek i date urodzenia.
*/
SET NOCOUNT ON;

DECLARE @OnlyUser INT = NULL;
DECLARE @OnlyProfile INT = NULL;
DECLARE @OnlyTree INT = NULL;
DECLARE @MaxAttempts INT = 100;
DECLARE @PlanFilterLevel NVARCHAR(100) = N'1,2,3,4,-1';
DECLARE @AsOf DATETIME = GETDATE();
DECLARE @UtcNow DATETIME = GETUTCDATE();

IF @MaxAttempts IS NULL OR @MaxAttempts < 1
    THROW 50000, 'MaxAttempts musi byc wieksze od zera.', 1;

DROP TABLE IF EXISTS #drmEligible;
DROP TABLE IF EXISTS #drmCandidates;
DROP TABLE IF EXISTS #drmScope;
DROP TABLE IF EXISTS #drmResults;
DROP TABLE IF EXISTS #drmErrors;

-- Dokladnie te same polaczenia i warunek aktualnosci organizacji co w raporcie.
-- DISTINCT usuwa mnozenie historii przez referencje/organizacje przy rankingu.
SELECT titles.idPayee, titles.ScopePayee, COUNT_BIG(*) AS TitleRows,
       MAX(titles.IsUSA) AS IsUSA
INTO #drmEligible
FROM
(
    SELECT DISTINCT pp.idPayee, tei.IdPayee AS ScopePayee, teb.EffectiveDate, teb.TitleCode,
           CASE WHEN rle.RegulatoryRegionCode = 'USA' THEN 1 ELSE 0 END AS IsUSA
    FROM dbo.py_Payee AS pp
    JOIN dbo._tb_employee_Title AS teb
        ON TRY_CAST(pp.codePayee AS INT) = teb.PersonnelNumber
    JOIN dbo._tb_employee_information AS tei ON teb.IdPayee = tei.IdPayee
    JOIN dbo._tb_employee_organization AS teo
        ON tei.IdPayee = teo.IdPayee AND @AsOf < teo.EndDate
    JOIN dbo._ref_CostCenter AS rcc ON teo.CostCenter = rcc.CostCenterCode
    JOIN dbo._ref_JobTitle AS rjt ON teb.TitleCode = rjt.JobTitleCode
    JOIN dbo._ref_LegalEntity AS rle ON teo.LegalEntity = rle.CompanyCode
) AS titles
GROUP BY titles.idPayee, titles.ScopePayee;

;WITH possible AS
(
    SELECT up.id_user AS idUser, up.id_profile AS idProfile,
           h.idTree, h.idChild AS idPayee
    FROM dbo.k_users AS u
    JOIN dbo.k_users_profiles AS up ON up.id_user = u.id_user
    JOIN dbo.hm_NodeLinkPublishedHierarchy AS h
        ON h.idChild = u.id_external_user AND h.idType = 14
    WHERE u.active_user = 1

    UNION

    SELECT up.id_user, up.id_profile, h.idTree, h.idChild
    FROM dbo.k_users AS u
    JOIN dbo.k_users_profiles AS up ON up.id_user = u.id_user
    JOIN dbo.k_tree_security AS sec ON sec.id_user_profile = up.idUserProfile
    JOIN dbo.hm_NodeLinkPublishedHierarchy AS h
        ON h.id_NodelinkPublished = sec.id_tree_node_published
    WHERE u.active_user = 1
      AND sec.begin_date < @UtcNow
      AND (sec.end_date IS NULL OR sec.end_date > @UtcNow)

    UNION

    SELECT up.id_user, up.id_profile, h.idTree, h.idChild
    FROM dbo.k_users AS u
    JOIN dbo.k_users_profiles AS up ON up.id_user = u.id_user
    CROSS JOIN dbo.hm_NodeLinkPublishedHierarchy AS h
    WHERE u.active_user = 1 AND u.isadmin_user = 1
      AND EXISTS
      (
          SELECT 1 FROM dbo.hm_NodelinkPublished AS root
          WHERE root.id = h.id_NodelinkPublished AND root.idParent = 0
      )
)
SELECT TOP (@MaxAttempts)
       ROW_NUMBER() OVER (ORDER BY p.idUser, p.idProfile, p.idTree, p.idPayee) AS Attempt,
       p.idUser, p.idProfile, p.idTree, p.idPayee
INTO #drmCandidates
FROM possible AS p
WHERE (@OnlyUser IS NULL OR p.idUser = @OnlyUser)
  AND (@OnlyProfile IS NULL OR p.idProfile = @OnlyProfile)
  AND (@OnlyTree IS NULL OR p.idTree = @OnlyTree)
  AND p.idPayee IS NOT NULL
ORDER BY p.idUser, p.idProfile, p.idTree, p.idPayee;

-- Typy i kolejnosc zgodne z INSERT EXEC w procedurze raportu.
CREATE TABLE #drmScope
(
    Included INT, HasChild INT, ChildLevel INT, idTreeSecurity INT,
    IdHierNode INT, IdChild INT, TypeId INT, IdParent INT, IdTypeParent INT,
    sort_order INT, ChildCodePayee BIGINT, NodeName NVARCHAR(150)
);
CREATE TABLE #drmResults
(
    idTree INT, idPayee INT, idUser INT, idProfile INT,
    Employees BIGINT, EmployeesWithHistory BIGINT, EmployeesWithFiveFormerTitles BIGINT,
    USAEmployees BIGINT, MaxTitleRows BIGINT
);
CREATE TABLE #drmErrors
(
    idTree INT, idPayee INT, idUser INT, idProfile INT,
    ErrorNumber INT, ErrorMessage NVARCHAR(4000)
);

DECLARE @Attempt BIGINT = 1, @Total BIGINT = (SELECT COUNT_BIG(*) FROM #drmCandidates);
DECLARE @Tree INT, @Payee INT, @User INT, @Profile INT;
WHILE @Attempt <= @Total
BEGIN
    SELECT @Tree = idTree, @Payee = idPayee, @User = idUser, @Profile = idProfile
    FROM #drmCandidates WHERE Attempt = @Attempt;

    TRUNCATE TABLE #drmScope;
    BEGIN TRY
        -- Wywolujemy helper bez zewnetrznego INSERT EXEC raportu:
        -- SQL Server nie dopuszcza zagniezdzonych INSERT EXEC.
        INSERT INTO #drmScope
        EXEC dbo._sp_lgt_Hierarchy_GetTreeContent_withLevel
             @idTree = @Tree,
             @idSelectedPayee = @Payee,
             @idUser = @User,
             @idProfileUser = @Profile,
             @payeeNameTemplate = N'lastname + char(13) + firstname',
             @planFilterLevel = @PlanFilterLevel;

        INSERT INTO #drmResults
        SELECT @Tree, @Payee, @User, @Profile,
               COUNT_BIG(*),
               SUM(CONVERT(BIGINT, CASE WHEN e.TitleRows >= 2 THEN 1 ELSE 0 END)),
               SUM(CONVERT(BIGINT, CASE WHEN e.TitleRows >= 6 THEN 1 ELSE 0 END)),
               SUM(CONVERT(BIGINT, e.IsUSA)), MAX(e.TitleRows)
        FROM
        (
            SELECT eligible.idPayee, MAX(eligible.TitleRows) AS TitleRows,
                   MAX(eligible.IsUSA) AS IsUSA
            FROM #drmEligible AS eligible
            WHERE EXISTS
                (SELECT 1 FROM #drmScope AS s WHERE s.IdChild = eligible.ScopePayee)
            GROUP BY eligible.idPayee
        ) AS e
        HAVING COUNT_BIG(*) > 0;
    END TRY
    BEGIN CATCH
        INSERT INTO #drmErrors
        VALUES (@Tree, @Payee, @User, @Profile, ERROR_NUMBER(), ERROR_MESSAGE());
    END CATCH;
    SET @Attempt += 1;
END;

SELECT r.*,
       CASE WHEN r.idProfile = 1 THEN N'Wiek i data urodzenia ukryte dla calego zakresu'
            ELSE N'Wiek i data urodzenia ukryte dla USA' END AS AgeVisibility,
       CONCAT(N'EXEC dbo.sp_report_Diversity_Report_Manager',
              N' @idTree = ', r.idTree,
              N', @idProcess = NULL, @idPayee = ', r.idPayee,
              N', @planFilterLevel = N''', REPLACE(@PlanFilterLevel, N'''', N''''''),
              N''', @planFilterCustom = NULL, @idUser = ', r.idUser,
              N', @idProfile = ', r.idProfile, N';') AS ExecuteReport
FROM #drmResults AS r
ORDER BY r.EmployeesWithFiveFormerTitles DESC, r.EmployeesWithHistory DESC,
         r.Employees DESC, r.idTree, r.idPayee, r.idUser, r.idProfile;

SELECT * FROM #drmErrors ORDER BY idUser, idProfile, idTree, idPayee;
DECLARE @Found INT = (SELECT COUNT(*) FROM #drmResults);
DECLARE @Errors INT = (SELECT COUNT(*) FROM #drmErrors);
PRINT CONCAT(N'Sprawdzono zestawow: ', @Total,
             N'. Zestawow z danymi: ', @Found,
             N'. Bledow: ', @Errors, N'.');
