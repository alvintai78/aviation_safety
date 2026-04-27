/***************************************************************************************
 Table   : DM_TBL_SRG_CHANGE_MGMT_REF
 Source  : Change Management References (Raw) - mocked for POC
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores recent change-management references surfaced on the "Recent Change
           Management References" cards (Maintenance / Training / Regulatory) on the
           Org 360 dashboard for an individual organisation.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_CHANGE_MGMT_REF', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_CHANGE_MGMT_REF;
GO

CREATE TABLE dbo.DM_TBL_SRG_CHANGE_MGMT_REF
(
    Reference_ID        VARCHAR(50)   NULL,  -- Unique reference (e.g. CM-2024-0001)
    Reference_Date      DATE          NULL,  -- Date of the change management reference
    Category            VARCHAR(50)   NULL,  -- Maintenance / Training / Regulatory / Operational
    Approval_Number     VARCHAR(50)   NULL,  -- Linked AWI (FK to MOA.Approval_Number)
    Organisation_Name   VARCHAR(255)  NULL,  -- Organisation
    Title               VARCHAR(255)  NULL,  -- Short headline (e.g. "Structural Integrity Review")
    Summary             VARCHAR(2000) NULL,  -- Description / context
    Source_Document_URL VARCHAR(1000) NULL,  -- Pointer to source document in repository
    data_last_updated   DATETIME2(0)  NULL,  -- Data last updated date
    dm_refresh_date     DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
