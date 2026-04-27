/***************************************************************************************
 Table   : DM_TBL_SRG_AMO_TAM_LIST
 Source  : TAM List (Raw)
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores Technical Arrangement / Maintenance (TAM) list of organisations
           under bilateral aviation safety agreements (FAA-MIP, CAAC-TAM, HKCAD-TAM,
           TCCA-TAM, UKCAA-TAM, etc.) administered by CAAS Safety Regulation Dept.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_AMO_TAM_LIST', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_AMO_TAM_LIST;
GO

CREATE TABLE dbo.DM_TBL_SRG_AMO_TAM_LIST
(
    Organisation_Name   VARCHAR(255)  NULL,  -- Name of the organisation
    Approval_Number     VARCHAR(50)   NULL,  -- Approval No. (e.g. TCCA 56-04)
    Type_of_Agreement   VARCHAR(255)  NULL,  -- FAA-MIP, CAAC-TAM, HKCAD-TAM, TCCA-TAM, UKCAA-TAM, etc.
    Country             VARCHAR(100)  NULL,  -- Country where the audit was conducted
    [Status]            VARCHAR(50)   NULL,  -- Participation status of bilateral agreement
    Status_From_MOA     VARCHAR(50)   NULL,  -- Participation status (only for records from MOA table)
    partition_key       VARCHAR(10)   NULL,  -- Partition key (YYYYMM)
    data_last_updated   DATETIME2(0)  NULL,  -- Data last updated date
    dm_refresh_date     DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
