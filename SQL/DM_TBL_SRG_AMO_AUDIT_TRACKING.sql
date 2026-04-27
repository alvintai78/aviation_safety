/***************************************************************************************
 Table   : DM_TBL_SRG_AMO_AUDIT_TRACKING
 Source  : Audit Tracking (Raw)
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores audit-tracking records for Approved Maintenance Organisations
           (AMOs) administered by CAAS Safety Regulation Dept, including the
           scheduled / completed audits, assigned PMIs and eSOMS references.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_AMO_AUDIT_TRACKING', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_AMO_AUDIT_TRACKING;
GO

CREATE TABLE dbo.DM_TBL_SRG_AMO_AUDIT_TRACKING
(
    Organisations               VARCHAR(255)  NULL,  -- Name of organisation
    Approval_No                 VARCHAR(50)   NULL,  -- Approval No. (e.g. AWI/002)
    Highest_Rating              VARCHAR(50)   NULL,  -- Highest risk rating held by the AMO
    Audit_Type                  VARCHAR(50)   NULL,  -- HQ (Principal Place of Business) or Satellite
    CAT                         VARCHAR(50)   NULL,  -- Category of rating(s) held by the AMO
    Country                     VARCHAR(100)  NULL,  -- Country where the audit was conducted
    City                        VARCHAR(100)  NULL,  -- City where the audit was conducted
    Approval_Expiry_Date        DATE          NULL,  -- Date when the current AMO approval certificate expires
    Audit_Plan                  DATE          NULL,  -- Month of scheduled audit
    Previous_Year_PMI           VARCHAR(255)  NULL,  -- PMI assigned in the previous year
    Current_Year_PMI            VARCHAR(255)  NULL,  -- PMI assigned in current year
    Completed_Audit_Date        DATE          NULL,  -- Actual audit completion date
    ESOMS_AMO_Audit_Reference_No VARCHAR(100) NULL,  -- eSOMS case reference number
    Remarks                     VARCHAR(500)  NULL,  -- Additional notes or comments regarding the audit
    dw_silver_insert_date       DATETIME2(0)  NULL,  -- Data ingestion date from silver table
    dm_refresh_date             DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
