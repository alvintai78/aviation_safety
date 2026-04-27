/***************************************************************************************
 Table   : DM_TBL_SRG_OCCURRENCES
 Source  : Safety Occurrence Reporting (Raw) - mocked for POC
 Target  : Azure Synapse Analytics - Dedicated SQL Pool
 Purpose : Stores aviation safety occurrences (bird strikes, runway incursions,
           fuel spills, external damage, taxi errors, accident investigations, etc.)
           reported to CAAS Safety Regulation Dept. Drives the "Drill-Down: Detailed
           Safety Records" table and the left-pane prompts (Bird Strikes, Runway
           Incursion dashboard).
****************************************************************************************/

IF OBJECT_ID('dbo.DM_TBL_SRG_OCCURRENCES', 'U') IS NOT NULL
    DROP TABLE dbo.DM_TBL_SRG_OCCURRENCES;
GO

CREATE TABLE dbo.DM_TBL_SRG_OCCURRENCES
(
    Occurrence_ID           VARCHAR(50)   NULL,  -- Unique occurrence identifier (e.g. OCC-2024-0001)
    Occurrence_Date         DATE          NULL,  -- Date the occurrence happened
    Activity_Code           VARCHAR(100)  NULL,  -- Activity classification (Accident Investigation, Taxi Error Investigation, External Damage, Fuel Spill, Bird Strike, Runway Incursion, etc.)
    Occurrence_Subtype      VARCHAR(100)  NULL,  -- Granular subtype (Structural failure, Hail damage, Fuel pit leak, Excessive speed, etc.)
    Approval_Number         VARCHAR(50)   NULL,  -- Linked AWI (FK to MOA.Approval_Number) where applicable
    Organisation_Name       VARCHAR(255)  NULL,  -- Organisation involved
    Aircraft_Registration   VARCHAR(20)   NULL,  -- Aircraft registration (e.g. 9V-ABC)
    Location                VARCHAR(255)  NULL,  -- Location / airport (e.g. WSSS, VHHH)
    CE_Mapping              VARCHAR(50)   NULL,  -- Critical Element category (Technical / Process / Human)
    Finding_Level           VARCHAR(50)   NULL,  -- Severity: Level 1 / Level 2 / Level 3 / OBS
    Lead_Inspector          VARCHAR(100)  NULL,  -- Inspector leading the investigation (e.g. Senior Lead 4)
    Target_Close_Date       DATE          NULL,  -- Target closure date
    Current_Status          VARCHAR(50)   NULL,  -- Open / In-progress / Target <YYYY-MM> / Closed
    ESOMS_Reference_No      VARCHAR(100)  NULL,  -- eSOMS case reference
    Summary                 VARCHAR(2000) NULL,  -- Short narrative describing the occurrence
    data_last_updated       DATETIME2(0)  NULL,  -- Data last updated date
    dm_refresh_date         DATETIME2(0)  NULL   -- Date of DW refresh
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO
