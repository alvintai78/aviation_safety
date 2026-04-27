/***************************************************************************************
 Table   : DM_TBL_SRG_DOA_POA
 Source  : Design / Production Organisation Approval Register (Raw) - mocked for POC
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores Design Organisation Approval (DOA) and Production Organisation
           Approval (POA) holders administered by CAAS Safety Regulation Dept.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_DOA_POA', 'U') IS NOT NULL DROP TABLE dbo.DM_TBL_SRG_DOA_POA;
GO

CREATE TABLE dbo.DM_TBL_SRG_DOA_POA
(
    Approval_Number     VARCHAR(50)   NULL,  -- e.g. DOA/SG/001 or POA/SG/001
    Approval_Type       VARCHAR(20)   NULL,  -- DOA / POA
    Organisation_Name   VARCHAR(255)  NULL,
    Country             VARCHAR(100)  NULL,
    City                VARCHAR(100)  NULL,
    Scope               VARCHAR(500)  NULL,  -- Scope of approval
    Highest_Rating      VARCHAR(50)   NULL,
    [Status]            VARCHAR(50)   NULL,
    Initial_Issue_Date  DATE          NULL,
    Approval_From       DATE          NULL,
    Approval_To         DATE          NULL,
    Accountable_Manager VARCHAR(255)  NULL,
    data_last_updated   DATETIME2(0)  NULL,
    dm_refresh_date     DATETIME2(0)  NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, CLUSTERED COLUMNSTORE INDEX);
GO
