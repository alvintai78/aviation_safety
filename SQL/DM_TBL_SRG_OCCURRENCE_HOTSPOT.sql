/***************************************************************************************
 Table   : DM_TBL_SRG_OCCURRENCE_HOTSPOT
 Source  : Synthetic hotspot overlay for POC dashboards
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Supplies gridded hotspot cells for the map overlay used by runway-
           incursion and bird-strike dashboards.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT;
GO

CREATE TABLE dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT
(
    Zone_ID                 VARCHAR(50)   NOT NULL,
    Activity_Code           VARCHAR(100)  NOT NULL,
    Location                VARCHAR(50)   NULL,
    Zone_Label              VARCHAR(100)  NULL,
    Center_Latitude         DECIMAL(10,6) NULL,
    Center_Longitude        DECIMAL(10,6) NULL,
    Event_Count             INT           NULL,
    Severity_Band           VARCHAR(30)   NULL,
    Loss_Alert_Count        INT           NULL,
    Integrity_Index_Pct     DECIMAL(5,2)  NULL,
    Jamming_Index_Pct       DECIMAL(5,2)  NULL,
    data_last_updated       DATETIME2(0)  NULL,
    dm_refresh_date         DATETIME2(0)  NULL
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO