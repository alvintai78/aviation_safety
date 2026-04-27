/***************************************************************************************
 Table   : DM_TBL_SRG_AOC
 Source  : Air Operator Certificate Register (Raw) - mocked for POC
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores AOC holders and their applications (New / Renewal / Variation)
           administered by CAAS Safety Regulation Dept. Drives the AOC sector tab
           and the "AOC Applications by Request Type" chart.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_AOC', 'U') IS NOT NULL DROP TABLE dbo.DM_TBL_SRG_AOC;
GO

CREATE TABLE dbo.DM_TBL_SRG_AOC
(
    AOC_Number          VARCHAR(50)   NULL,  -- AOC certificate number (e.g. AOC/SG/001)
    Operator_Name       VARCHAR(255)  NULL,  -- Name of the operator
    Country             VARCHAR(100)  NULL,
    City                VARCHAR(100)  NULL,
    [Status]            VARCHAR(50)   NULL,  -- Active / Suspended / Surrendered
    Initial_Issue_Date  DATE          NULL,
    Approval_From       DATE          NULL,
    Approval_To         DATE          NULL,
    Highest_Rating      VARCHAR(50)   NULL,
    Accountable_Manager VARCHAR(255)  NULL,
    data_last_updated   DATETIME2(0)  NULL,
    dm_refresh_date     DATETIME2(0)  NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, CLUSTERED COLUMNSTORE INDEX);
GO

IF OBJECT_ID('dbo.DM_TBL_SRG_AOC_APPLICATIONS', 'U') IS NOT NULL DROP TABLE dbo.DM_TBL_SRG_AOC_APPLICATIONS;
GO

CREATE TABLE dbo.DM_TBL_SRG_AOC_APPLICATIONS
(
    Application_ID      VARCHAR(50)   NULL,  -- e.g. AOC-APP-2024-0001
    AOC_Number          VARCHAR(50)   NULL,  -- FK to DM_TBL_SRG_AOC.AOC_Number
    Operator_Name       VARCHAR(255)  NULL,
    Application_Type    VARCHAR(50)   NULL,  -- New AMO / Renewal / Variation
    Application_Date    DATE          NULL,
    Decision_Date       DATE          NULL,
    Decision            VARCHAR(50)   NULL,  -- Approved / Rejected / In-progress
    Lead_Inspector      VARCHAR(100)  NULL,
    Remarks             VARCHAR(500)  NULL,
    data_last_updated   DATETIME2(0)  NULL,
    dm_refresh_date     DATETIME2(0)  NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, CLUSTERED COLUMNSTORE INDEX);
GO
