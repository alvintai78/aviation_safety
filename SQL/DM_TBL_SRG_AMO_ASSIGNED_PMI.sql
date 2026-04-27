/***************************************************************************************
 Table   : DM_TBL_SRG_AMO_ASSIGNED_PMI
 Source  : SAR-145 Assigned PMI (Raw)
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores Principal Maintenance Inspector (PMI) assignments for each
           Approved Maintenance Organisation (AMO) under SAR-145, administered
           by CAAS Safety Regulation Dept.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_AMO_ASSIGNED_PMI', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_AMO_ASSIGNED_PMI;
GO

CREATE TABLE dbo.DM_TBL_SRG_AMO_ASSIGNED_PMI
(
    Organisation        VARCHAR(255)  NULL,  -- Name of the organisation
    AWI_No              VARCHAR(50)   NULL,  -- Approval No. (e.g. AWI/001)
    Location            VARCHAR(50)   NULL,  -- Local (within Singapore) or overseas
    PMI                 VARCHAR(255)  NULL,  -- Principal Maintenance Inspector assigned
    data_last_updated   DATETIME2(0)  NULL,  -- Timestamp when data was last updated in source
    dm_refresh_date     DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
