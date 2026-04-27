/***************************************************************************************
 Table   : DM_TBL_SRG_AMO_MOA
 Source  : MOA (Raw)
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores Approved Maintenance Organisation (AMO) details sourced from MOA.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_AMO_MOA', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_AMO_MOA;
GO

CREATE TABLE dbo.DM_TBL_SRG_AMO_MOA
(
    Approval_Number        VARCHAR(50)   NULL,  -- Approval No. (e.g. AWI/001)
    Name_of_AMO            VARCHAR(255)  NULL,  -- Name of the organisation
    Location               VARCHAR(50)   NULL,  -- Local (within Singapore) or overseas
    [Address]              VARCHAR(500)  NULL,  -- Full postal address of the location
    Ratings                VARCHAR(255)  NULL,  -- Current ratings held by the AMO at that location
    Highest_Rating         VARCHAR(50)   NULL,  -- Highest risk rating held by the AMO
    Bilateral_Arrangement  VARCHAR(255)  NULL,  -- Details of bilateral aviation safety agreements
    [Status]               VARCHAR(50)   NULL,  -- Participation status of bilateral agreements
    Initial_Issue_Date     DATE          NULL,  -- Date when the AMO approval was first issued
    ANOPara                VARCHAR(100)  NULL,  -- Air Navigation Order paragraph(s)
    Approval_From          DATE          NULL,  -- Start date of the current approval period
    Approval_To            DATE          NULL,  -- End date of the current approval period
    Country                VARCHAR(100)  NULL,  -- Country where the audit was conducted
    City                   VARCHAR(100)  NULL,  -- City where the audit was conducted
    FAA_Approval_No        VARCHAR(50)   NULL,  -- FAA approval number under the MIP
    FAA_Approval_From      DATE          NULL,  -- Start date of FAA approval under the MIP
    FAA_Approval_To        DATE          NULL,  -- End date of FAA approval under the MIP
    AM_Appointment         VARCHAR(255)  NULL,  -- Designation of the Accountable Manager
    AM_Email               VARCHAR(255)  NULL,  -- Email of the Accountable Manager
    AM_Name                VARCHAR(255)  NULL,  -- Name of the Accountable Manager
    AM_Contact             VARCHAR(50)   NULL,  -- Contact number of the Accountable Manager
    QM_Appointment         VARCHAR(255)  NULL,  -- Designation of the Quality Manager
    QM_Email               VARCHAR(255)  NULL,  -- Email of the Quality Manager
    QM_Name                VARCHAR(255)  NULL,  -- Name of the Quality Manager
    QM_Contact             VARCHAR(50)   NULL,  -- Contact number of the Quality Manager
    MM_Appointment         VARCHAR(255)  NULL,  -- Designation of the Maintenance Manager
    MM_Email               VARCHAR(255)  NULL,  -- Email of the Maintenance Manager
    MM_Name                VARCHAR(255)  NULL,  -- Name of the Maintenance Manager
    MM_Contact             VARCHAR(50)   NULL,  -- Contact number of the Maintenance Manager
    Surrender_Date         DATE          NULL,  -- Date when the AMO approval was surrendered
    partition_key          VARCHAR(10)   NULL,  -- Partition key extracted from the input file date (YYYYMM)
    data_last_updated      DATETIME2(0)  NULL,  -- Data last updated date
    dm_refresh_date        DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
