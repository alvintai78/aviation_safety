/***************************************************************************************
 Table   : DM_TBL_SRG_OCCURRENCE_OPS_TRACK
 Source  : Synthetic operational telemetry for POC dashboards
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Provides map/list telemetry rows for runway-incursion and bird-strike
           dashboards so the POC can mimic an operations console rather than a
           generic BI page.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK;
GO

CREATE TABLE dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK
(
    Track_ID                VARCHAR(50)   NOT NULL,
    Snapshot_Timestamp      DATETIME2(0)  NOT NULL,
    Activity_Code           VARCHAR(100)  NOT NULL,
    Approval_Number         VARCHAR(50)   NULL,
    Organisation_Name       VARCHAR(255)  NULL,
    Callsign                VARCHAR(20)   NULL,
    Tail_ID                 VARCHAR(20)   NULL,
    Location                VARCHAR(50)   NULL,
    Latitude                DECIMAL(10,6) NULL,
    Longitude               DECIMAL(10,6) NULL,
    Heading_Deg             INT           NULL,
    Ground_Speed_Kts        INT           NULL,
    Altitude_Ft             INT           NULL,
    Flight_Level            VARCHAR(10)   NULL,
    Integrity_Index_Pct     DECIMAL(5,2)  NULL,
    Jamming_Index_Pct       DECIMAL(5,2)  NULL,
    Conflict_Risk_Score     DECIMAL(5,2)  NULL,
    Conflict_Alert          VARCHAR(255)  NULL,
    Conflict_Pair           VARCHAR(50)   NULL,
    Current_Status          VARCHAR(50)   NULL,
    data_last_updated       DATETIME2(0)  NULL,
    dm_refresh_date         DATETIME2(0)  NULL
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO