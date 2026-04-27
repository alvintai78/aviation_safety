/***************************************************************************************
 Table   : DM_TBL_SRG_AMO_CAN_OBS_DIS_SUMMARY
 Source  : CAN Report for AMO (Raw)
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores Corrective Action Notice (CAN), Observations (OBS) and
           Discrepancy (DIS) summary findings raised from AMO audits by
           CAAS Safety Regulation Dept.
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_AMO_CAN_OBS_DIS_SUMMARY', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_AMO_CAN_OBS_DIS_SUMMARY;
GO

CREATE TABLE dbo.DM_TBL_SRG_AMO_CAN_OBS_DIS_SUMMARY
(
    Approval_Number                 VARCHAR(50)    NULL,  -- Approval No. (e.g. AWI/200)
    Approval_Type                   VARCHAR(50)    NULL,  -- Type of approval granted (e.g. MOA, design, production, maintenance)
    Application_Type                VARCHAR(50)    NULL,  -- Type of application (Initial, Renewal, Variation)
    Organisation_Name               VARCHAR(255)   NULL,  -- Name of the organisation
    Evaluation_Action_Type          VARCHAR(20)    NULL,  -- CAN, OBS, DIS
    Evaluation_Action_Issue_Date    DATETIME2(0)   NULL,  -- Date when the evaluation action was issued
    Area_Audited                    VARCHAR(255)   NULL,  -- Specific area/department of the AMO that was audited
    Level_Of_Finding                VARCHAR(20)    NULL,  -- Severity level (Level 1, Level 2, Level 3)
    Non_Compliance_Statement        VARCHAR(2000)  NULL,  -- Description of the non-compliance identified
    Reference_To_National_Legislations VARCHAR(255) NULL, -- Citation of relevant national regulations / legislation
    Critical_Element                VARCHAR(255)   NULL,  -- ICAO critical element(s) related to the finding
    Immediate_Action                VARCHAR(2000)  NULL,  -- Immediate corrective actions required or taken
    Root_Cause_Analysis             VARCHAR(2000)  NULL,  -- Analysis identifying the underlying cause
    Preventive_Action_Plan          VARCHAR(2000)  NULL,  -- Plan to prevent recurrence
    Root_Cause_Classification       VARCHAR(255)   NULL,  -- Category or classification of the root cause
    Follow_Up_And_Closure           VARCHAR(2000)  NULL,  -- Status and details of follow-up actions and closure
    Actions_Taken                   VARCHAR(2000)  NULL,  -- Specific actions taken to address the finding
    data_last_updated               DATETIME2(0)   NULL,  -- Timestamp when data was last updated in source
    dm_refresh_date                 DATETIME2(0)   NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
