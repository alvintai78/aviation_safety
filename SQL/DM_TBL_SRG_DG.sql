/***************************************************************************************
 Table   : DM_TBL_SRG_DG
 Source  : Dangerous Goods Operator Register (Raw) - mocked for POC
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores Dangerous Goods (DG) shippers, freight forwarders and operators
           regulated by CAAS Safety Regulation Dept.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_DG', 'U') IS NOT NULL DROP TABLE dbo.DM_TBL_SRG_DG;
GO

CREATE TABLE dbo.DM_TBL_SRG_DG
(
    DG_Approval_Number  VARCHAR(50)   NULL,  -- e.g. DG/SG/001
    Organisation_Name   VARCHAR(255)  NULL,
    Organisation_Type   VARCHAR(50)   NULL,  -- Shipper / Freight Forwarder / Operator / Ground Handler
    Country             VARCHAR(100)  NULL,
    City                VARCHAR(100)  NULL,
    DG_Classes_Held     VARCHAR(255)  NULL,  -- e.g. "Class 1, Class 3, Class 9"
    [Status]            VARCHAR(50)   NULL,
    Initial_Issue_Date  DATE          NULL,
    Approval_From       DATE          NULL,
    Approval_To         DATE          NULL,
    Highest_Rating      VARCHAR(50)   NULL,
    data_last_updated   DATETIME2(0)  NULL,
    dm_refresh_date     DATETIME2(0)  NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, CLUSTERED COLUMNSTORE INDEX);
GO
