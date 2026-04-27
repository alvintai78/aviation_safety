/***************************************************************************************
 Table   : DM_TBL_SRG_TACTICAL_AUDIT
 Source  : Synthetic risk narrative for POC dashboards
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores tactical audit narratives and recommended actions for the
           right-hand intelligence panel.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_TACTICAL_AUDIT', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_TACTICAL_AUDIT;
GO

CREATE TABLE dbo.DM_TBL_SRG_TACTICAL_AUDIT
(
    Tactical_Audit_ID       VARCHAR(50)   NOT NULL,
    Activity_Code           VARCHAR(100)  NOT NULL,
    Track_ID                VARCHAR(50)   NULL,
    Tail_ID                 VARCHAR(20)   NULL,
    Composite_Risk_Score    DECIMAL(5,2)  NULL,
    Intelligence_Summary    VARCHAR(2000) NULL,
    Action_1                VARCHAR(500)  NULL,
    Action_2                VARCHAR(500)  NULL,
    Action_3                VARCHAR(500)  NULL,
    data_last_updated       DATETIME2(0)  NULL,
    dm_refresh_date         DATETIME2(0)  NULL
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO