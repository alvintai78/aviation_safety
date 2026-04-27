/***************************************************************************************
 Table   : DM_TBL_SRG_SURVEILLANCE_ACTIVITY
 Source  : Surveillance Activity Register (Raw) - mocked for POC
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores sector-wide surveillance activities performed by CAAS Safety
           Regulation Dept (FOI enroute inspection, Maintenance Ramp, Cabin ramp
           inspection, Audit, etc.). Drives the "Surveillance Activities (Sector
           Wide)" chart.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_SURVEILLANCE_ACTIVITY', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_SURVEILLANCE_ACTIVITY;
GO

CREATE TABLE dbo.DM_TBL_SRG_SURVEILLANCE_ACTIVITY
(
    Activity_ID         VARCHAR(50)   NULL,  -- Unique activity identifier (e.g. SURV-2024-0001)
    Activity_Date       DATE          NULL,  -- Date the activity was performed
    Activity_Type       VARCHAR(100)  NULL,  -- FOI enroute inspection / Maintenance Ramp / Cabin ramp inspection / Audit / Spot check
    Sector              VARCHAR(50)   NULL,  -- AMO / AOC / DOA/POA / DG
    Approval_Number     VARCHAR(50)   NULL,  -- Linked AWI (FK to MOA.Approval_Number) where applicable
    Organisation_Name   VARCHAR(255)  NULL,  -- Organisation surveyed
    Location            VARCHAR(255)  NULL,  -- Location / airport (e.g. WSSS, VHHH)
    Inspector           VARCHAR(100)  NULL,  -- Inspector performing the activity
    Outcome             VARCHAR(50)   NULL,  -- Pass / Findings Raised / Follow-up Required
    Findings_Count      INT           NULL,  -- Number of findings raised from this activity
    Remarks             VARCHAR(500)  NULL,  -- Additional notes
    data_last_updated   DATETIME2(0)  NULL,  -- Data last updated date
    dm_refresh_date     DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
