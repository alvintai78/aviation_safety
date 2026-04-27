/***************************************************************************************
 Table   : DM_TBL_SRG_AMO_TIER
 Source  : AMO Tier (Raw)
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores annual risk-tier classification for each Approved Maintenance
           Organisation (AMO) administered by CAAS Safety Regulation Dept.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_AMO_TIER', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_AMO_TIER;
GO

CREATE TABLE dbo.DM_TBL_SRG_AMO_TIER
(
    AWI                 VARCHAR(50)   NULL,  -- Approval No. (e.g. AWI/001)
    Highest_Rating      VARCHAR(50)   NULL,  -- Highest risk rating held by the AMO
    [Year]              INT           NULL,  -- Calendar year for which the tier applies
    Tier                VARCHAR(50)   NULL,  -- Risk tier classification (e.g. Low Tier 3)
    data_last_updated   DATETIME2(0)  NULL,  -- Data last updated date
    dm_refresh_date     DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
