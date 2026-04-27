/***************************************************************************************
 Script  : rollout_occurrence_ops_poc.sql
 Purpose : One-pass rollout for the occurrence-ops POC surfaces used by the
           runway-incursion and bird-strike dashboards.

 Execution order in this script:
   1. Create base tables
   2. Seed synthetic POC data
   3. Recreate the SafetyIntel views that expose the new surfaces

 Safe rerun behavior:
   - Each table/view uses DROP IF EXISTS style logic before CREATE.
****************************************************************************************/

/* -------------------------------------------------------------------------
   1. Base tables
   ------------------------------------------------------------------------- */

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

/* -------------------------------------------------------------------------
   2. Synthetic POC seed data
   ------------------------------------------------------------------------- */

INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-RI-001','2026-04-22 09:10:00','Runway Incursion','AWI/007','Hawker Pacific Airservices Pte Ltd','TGW598','9V-761','WSSS',1.354100,103.987100,266,265,9500,'FL95',96.0,3.0,25.0,'Conflict alert','SIA212','Monitoring','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-RI-002','2026-04-22 09:10:00','Runway Incursion','AWI/020','Changi Avionics Services Pte Ltd','TGW427','9V-427','WSSS',1.350800,103.992100,281,246,9000,'FL90',94.0,4.0,18.0,'Vehicle crossing active runway','TGW598','Monitoring','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-RI-003','2026-04-22 09:10:00','Runway Incursion','AWI/008','Singapore Technologies Aerospace (Paya Lebar)','TGW676','9V-676','WSSS',1.348700,103.998100,302,480,34000,'FL340',97.0,2.0,12.0,NULL,NULL,'Monitoring','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-RI-004','2026-04-22 09:10:00','Runway Incursion','AWI/012','SIAEC Line Maintenance (HKG)','SIA7430','9V-S30','WSSS',1.345200,103.999900,320,509,35000,'FL350',95.0,3.0,10.0,NULL,NULL,'Monitoring','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-RI-005','2026-04-22 09:10:00','Runway Incursion','AWI/014','GMF AeroAsia Indonesia','FJL744','PK-744','WSSS',1.342900,103.994700,178,179,11300,'FL113',93.0,5.0,8.0,NULL,NULL,'Monitoring','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-RI-006','2026-04-22 09:10:00','Runway Incursion','AWI/011','SIAEC Line Maintenance (KUL)','SIF747','9M-747','WSSS',1.339600,103.991100,166,477,35000,'FL350',92.0,4.0,9.0,NULL,NULL,'Monitoring','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-RI-007','2026-04-22 09:10:00','Runway Incursion','AWI/018','Qantas Engineering Australia','SIF721','VH-721','WSSS',1.336600,103.988100,154,534,37000,'FL370',94.0,3.0,7.0,NULL,NULL,'Monitoring','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-BS-001','2026-04-22 09:10:00','Bird Strike','AWI/002','ST Engineering Aerospace Services Pte Ltd','BIR231','9V-STF','WSSS',1.359200,103.975200,192,154,7000,'FL70',95.0,2.0,14.0,'Wildlife cluster ahead',NULL,'Open','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-BS-002','2026-04-22 09:10:00','Bird Strike','AWI/005','Jet Aviation Singapore Pte Ltd','BIR118','9V-JAS','WSSS',1.357800,103.979500,205,162,8200,'FL82',94.0,3.0,16.0,'Multiple flock signatures',NULL,'Open','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK (Track_ID, Snapshot_Timestamp, Activity_Code, Approval_Number, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status, data_last_updated, dm_refresh_date) VALUES ('OPS-BS-003','2026-04-22 09:10:00','Bird Strike','AWI/014','GMF AeroAsia Indonesia','BIR442','PK-GMF','WIII',-6.120100,106.655800,188,149,6500,'FL65',96.0,2.0,11.0,NULL,NULL,'Closed','2026-04-22 09:15:00','2026-04-22 09:15:00');
GO

INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct, data_last_updated, dm_refresh_date) VALUES ('GRID-RI-01','Runway Incursion','WSSS','South runway crossing',1.351900,103.991200,8,'critical',1,95.0,3.0,'2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct, data_last_updated, dm_refresh_date) VALUES ('GRID-RI-02','Runway Incursion','WSSS','Taxi lane cluster',1.349200,103.989800,6,'watch',0,94.0,4.0,'2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct, data_last_updated, dm_refresh_date) VALUES ('GRID-RI-03','Runway Incursion','WSSS','Apron transition',1.346800,103.995400,4,'watch',0,96.0,2.0,'2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct, data_last_updated, dm_refresh_date) VALUES ('GRID-BS-01','Bird Strike','WSSS','Approach wildlife corridor',1.357400,103.977900,7,'critical',0,95.0,2.0,'2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct, data_last_updated, dm_refresh_date) VALUES ('GRID-BS-02','Bird Strike','WSSS','Coastal climb-out corridor',1.360200,103.983600,5,'watch',0,94.0,3.0,'2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct, data_last_updated, dm_refresh_date) VALUES ('GRID-BS-03','Bird Strike','WIII','Jakarta final approach',-6.118300,106.657300,4,'watch',0,96.0,2.0,'2026-04-22 09:15:00','2026-04-22 09:15:00');
GO

INSERT INTO dbo.DM_TBL_SRG_TACTICAL_AUDIT (Tactical_Audit_ID, Activity_Code, Track_ID, Tail_ID, Composite_Risk_Score, Intelligence_Summary, Action_1, Action_2, Action_3, data_last_updated, dm_refresh_date) VALUES ('TACT-RI-001','Runway Incursion','OPS-RI-001','9V-761',25,'No direct investigation or surveillance notes were linked to track TGW598. General runway-incursion exposure remains driven by vehicle crossing risk, low-speed taxi confusion, and radio discipline gaps seen across recent occurrence records.','Reconfirm runway access control and escort procedure for all ground vehicles.','Issue targeted radio phraseology reminder to tug and maintenance crews.','Review hold-point signage and low-visibility taxi brief for current shift.','2026-04-22 09:15:00','2026-04-22 09:15:00');
INSERT INTO dbo.DM_TBL_SRG_TACTICAL_AUDIT (Tactical_Audit_ID, Activity_Code, Track_ID, Tail_ID, Composite_Risk_Score, Intelligence_Summary, Action_1, Action_2, Action_3, data_last_updated, dm_refresh_date) VALUES ('TACT-BS-001','Bird Strike','OPS-BS-002','9V-JAS',22,'Bird-strike exposure is concentrated on approach and climb-out corridors with repeated windshield and engine-ingestion subtypes. Wildlife dispersal timing and turnaround inspection discipline remain the main mitigations.','Synchronise wildlife dispersal patrols with the morning arrival bank.','Brief line inspectors to prioritise radome, windshield, and fan-blade checks after reports.','Track repeat subtypes by location to separate random strikes from persistent habitat issues.','2026-04-22 09:15:00','2026-04-22 09:15:00');
GO

/* -------------------------------------------------------------------------
   3. Views exposed to the NL2SQL agent
   ------------------------------------------------------------------------- */

IF OBJECT_ID('dbo.vw_SafetyIntel_OccurrenceOpsOverview','V') IS NOT NULL DROP VIEW dbo.vw_SafetyIntel_OccurrenceOpsOverview;
GO
CREATE VIEW dbo.vw_SafetyIntel_OccurrenceOpsOverview AS
SELECT
    t.Activity_Code,
    COUNT(*) AS Active_Tracks,
    CAST(AVG(t.Jamming_Index_Pct) AS DECIMAL(5,2)) AS Jamming_Index_Pct,
    CAST(AVG(t.Integrity_Index_Pct) AS DECIMAL(5,2)) AS Integrity_Index_Pct,
    SUM(CASE WHEN t.Conflict_Alert IS NOT NULL THEN 1 ELSE 0 END) AS Loss_Alert_Count,
    COUNT(*) AS Records_Analyzed,
    MAX(t.Location) AS Primary_Location
FROM dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK t
GROUP BY t.Activity_Code;
GO

IF OBJECT_ID('dbo.vw_SafetyIntel_OccurrenceOps','V') IS NOT NULL DROP VIEW dbo.vw_SafetyIntel_OccurrenceOps;
GO
CREATE VIEW dbo.vw_SafetyIntel_OccurrenceOps AS
SELECT
    t.Track_ID,
    t.Snapshot_Timestamp,
    t.Activity_Code,
    t.Approval_Number AS AWI,
    t.Organisation_Name,
    t.Callsign,
    t.Tail_ID,
    t.Location,
    t.Latitude,
    t.Longitude,
    t.Heading_Deg,
    t.Ground_Speed_Kts,
    t.Altitude_Ft,
    t.Flight_Level,
    t.Integrity_Index_Pct,
    t.Jamming_Index_Pct,
    t.Conflict_Risk_Score,
    t.Conflict_Alert,
    t.Conflict_Pair,
    t.Current_Status
FROM dbo.DM_TBL_SRG_OCCURRENCE_OPS_TRACK t;
GO

IF OBJECT_ID('dbo.vw_SafetyIntel_OccurrenceHotspots','V') IS NOT NULL DROP VIEW dbo.vw_SafetyIntel_OccurrenceHotspots;
GO
CREATE VIEW dbo.vw_SafetyIntel_OccurrenceHotspots AS
SELECT
    h.Zone_ID,
    h.Activity_Code,
    h.Location,
    h.Zone_Label,
    h.Center_Latitude,
    h.Center_Longitude,
    h.Event_Count,
    h.Severity_Band,
    h.Loss_Alert_Count,
    h.Integrity_Index_Pct,
    h.Jamming_Index_Pct
FROM dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT h;
GO

IF OBJECT_ID('dbo.vw_SafetyIntel_TacticalAudit','V') IS NOT NULL DROP VIEW dbo.vw_SafetyIntel_TacticalAudit;
GO
CREATE VIEW dbo.vw_SafetyIntel_TacticalAudit AS
SELECT
    a.Tactical_Audit_ID,
    a.Activity_Code,
    a.Track_ID,
    a.Tail_ID,
    a.Composite_Risk_Score,
    a.Intelligence_Summary,
    a.Action_1,
    a.Action_2,
    a.Action_3
FROM dbo.DM_TBL_SRG_TACTICAL_AUDIT a;
GO