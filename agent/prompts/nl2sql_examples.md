# NL2SQL few-shot examples (Safety Intelligence Bot)

The schema the model may use (read-only views, distribution: ROUND_ROBIN):

```
vw_SafetyIntel_AMO              (AWI, Organisation_Name, Country, City, Highest_Rating, Status, Bilateral_Arrangement, Initial_Issue_Date, Approval_From, Approval_To, Accountable_Manager, Quality_Manager, Tier_Year, Current_Tier, Assigned_PMI)
vw_SafetyIntel_Findings         (AWI, Organisation_Name, Finding_Type, Finding_Date, Finding_Year, Area_Audited, Level_Of_Finding, Critical_Element, Root_Cause_Bucket, Root_Cause_Detail, Non_Compliance_Statement, Immediate_Action, Follow_Up_And_Closure)
vw_SafetyIntel_Audits           (AWI, Organisation_Name, Audit_Type, CAT, Country, City, Approval_Expiry_Date, Planned_Audit_Date, Completed_Audit_Date, Previous_Year_PMI, Current_Year_PMI, ESOMS_Reference_No, Remarks)
vw_SafetyIntel_TierTrend        (AWI, Organisation_Name, Year, Tier, Highest_Rating)
vw_SafetyIntel_Surveillance     (Activity_ID, Activity_Date, Activity_Type, Sector, AWI, Organisation_Name, Location, Inspector, Outcome, Findings_Count)
vw_SafetyIntel_Occurrences      (Occurrence_ID, Occurrence_Date, Occurrence_Year, Activity_Code, Occurrence_Subtype, AWI, Organisation_Name, Aircraft_Registration, Location, CE_Mapping, Finding_Level, Lead_Inspector, Target_Close_Date, Current_Status, ESOMS_Reference_No, Summary)
vw_SafetyIntel_OccurrenceOpsOverview (Activity_Code, Active_Tracks, Jamming_Index_Pct, Integrity_Index_Pct, Loss_Alert_Count, Records_Analyzed, Primary_Location)
vw_SafetyIntel_OccurrenceOps    (Track_ID, Snapshot_Timestamp, Activity_Code, AWI, Organisation_Name, Callsign, Tail_ID, Location, Latitude, Longitude, Heading_Deg, Ground_Speed_Kts, Altitude_Ft, Flight_Level, Integrity_Index_Pct, Jamming_Index_Pct, Conflict_Risk_Score, Conflict_Alert, Conflict_Pair, Current_Status)
vw_SafetyIntel_OccurrenceHotspots (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct)
vw_SafetyIntel_TacticalAudit    (Tactical_Audit_ID, Activity_Code, Track_ID, Tail_ID, Composite_Risk_Score, Intelligence_Summary, Action_1, Action_2, Action_3)
vw_SafetyIntel_ChangeMgmt       (Reference_ID, Reference_Date, Category, AWI, Organisation_Name, Title, Summary, Source_Document_URL)
vw_SafetyIntel_AOC_Applications (Application_ID, AOC_Number, Operator_Name, Application_Type, Application_Date, Decision_Date, Decision, Lead_Inspector, Application_Year)
vw_SafetyIntel_TAM              (Organisation_Name, Foreign_Approval_Number, Type_of_Agreement, Country, Status)
```

Rules:
- Always `SELECT` only. Never modify data.
- Reference only the views above. Never reference `DM_TBL_*` directly.
- Use `TOP n` if the user asks for "top", else cap at `TOP 200`.
- Date filters: use `>= '2024-01-01'` style, not `BETWEEN`.

---

### Example 1
User: All Level-1 CAN findings raised against AWI/004 in the last 3 years.
SQL:
```sql
SELECT TOP 200
    Finding_Date,
    Area_Audited,
    Level_Of_Finding,
    Critical_Element,
    Non_Compliance_Statement
FROM dbo.vw_SafetyIntel_Findings
WHERE AWI = 'AWI/004'
  AND Finding_Type = 'CAN'
  AND Level_Of_Finding = 'Level 1'
  AND Finding_Date >= DATEADD(YEAR, -3, CAST(GETDATE() AS DATE))
ORDER BY Finding_Date DESC;
```

### Example 2
User: Which AMOs had a downward tier change between 2023 and 2024?
SQL:
```sql
WITH t AS (
    SELECT AWI, Organisation_Name,
           MAX(CASE WHEN [Year] = 2023 THEN Tier END) AS Tier_2023,
           MAX(CASE WHEN [Year] = 2024 THEN Tier END) AS Tier_2024
    FROM dbo.vw_SafetyIntel_TierTrend
    WHERE [Year] IN (2023, 2024)
    GROUP BY AWI, Organisation_Name
)
SELECT TOP 200 AWI, Organisation_Name, Tier_2023, Tier_2024
FROM t
WHERE Tier_2023 IS NOT NULL AND Tier_2024 IS NOT NULL
  AND Tier_2024 > Tier_2023;
```

### Example 3
User: Surveillance activities (sector wide) by activity type in 2025.
SQL:
```sql
SELECT Activity_Type, COUNT(*) AS Activity_Count
FROM dbo.vw_SafetyIntel_Surveillance
WHERE YEAR(Activity_Date) = 2025
GROUP BY Activity_Type
ORDER BY Activity_Count DESC;
```

### Example 4
User: Show me bird strikes in the last 12 months.
SQL:
```sql
SELECT TOP 200
    Occurrence_Date, AWI, Organisation_Name, Aircraft_Registration,
    Location, Occurrence_Subtype, Finding_Level, Current_Status
FROM dbo.vw_SafetyIntel_Occurrences
WHERE Activity_Code = 'Bird Strike'
  AND Occurrence_Date >= DATEADD(MONTH, -12, CAST(GETDATE() AS DATE))
ORDER BY Occurrence_Date DESC;
```

### Example 5
User: AOC applications by request type in 2024.
SQL:
```sql
SELECT Application_Type, COUNT(*) AS Applications
FROM dbo.vw_SafetyIntel_AOC_Applications
WHERE Application_Year = 2024
GROUP BY Application_Type
ORDER BY Applications DESC;
```

### Example 6
User: Findings by Critical Element for Global Airways (Level 2 + OBS only).
SQL:
```sql
SELECT Critical_Element, Level_Of_Finding, COUNT(*) AS Finding_Count
FROM dbo.vw_SafetyIntel_Findings
WHERE Organisation_Name = 'Global Airways Pte Ltd'
  AND Level_Of_Finding IN ('Level 2', 'OBS')
GROUP BY Critical_Element, Level_Of_Finding
ORDER BY Critical_Element;
```

### Example 7
User: Recent change-management references for AWI/001.
SQL:
```sql
SELECT TOP 5
    Reference_Date, Category, Title, Summary, Source_Document_URL
FROM dbo.vw_SafetyIntel_ChangeMgmt
WHERE AWI = 'AWI/001'
ORDER BY Reference_Date DESC;
```

### Example 8
User: Runway incursions by month for the last 12 months.
SQL:
```sql
SELECT
    CONCAT(YEAR(Occurrence_Date), '-', RIGHT(CONCAT('0', MONTH(Occurrence_Date)), 2)) AS Occurrence_Month,
    COUNT(*) AS Runway_Incursion_Count
FROM dbo.vw_SafetyIntel_Occurrences
WHERE Activity_Code = 'Runway Incursion'
  AND Occurrence_Date >= DATEADD(MONTH, -12, CAST(GETDATE() AS DATE))
GROUP BY YEAR(Occurrence_Date), MONTH(Occurrence_Date)
ORDER BY YEAR(Occurrence_Date), MONTH(Occurrence_Date);
```

### Example 9
User: Open runway incursion occurrences by location in the last 12 months.
SQL:
```sql
SELECT
    Location,
    COUNT(*) AS Open_Incursion_Count
FROM dbo.vw_SafetyIntel_Occurrences
WHERE Activity_Code = 'Runway Incursion'
  AND Occurrence_Date >= DATEADD(MONTH, -12, CAST(GETDATE() AS DATE))
  AND Current_Status <> 'Closed'
GROUP BY Location
ORDER BY Open_Incursion_Count DESC, Location;
```

### Example 10
User: Bird strikes by month for the last 12 months.
SQL:
```sql
SELECT
    CONCAT(YEAR(Occurrence_Date), '-', RIGHT(CONCAT('0', MONTH(Occurrence_Date)), 2)) AS Occurrence_Month,
    COUNT(*) AS Bird_Strike_Count
FROM dbo.vw_SafetyIntel_Occurrences
WHERE Activity_Code = 'Bird Strike'
  AND Occurrence_Date >= DATEADD(MONTH, -12, CAST(GETDATE() AS DATE))
GROUP BY YEAR(Occurrence_Date), MONTH(Occurrence_Date)
ORDER BY YEAR(Occurrence_Date), MONTH(Occurrence_Date);
```

### Example 11
User: Bird strikes by subtype in the last 12 months.
SQL:
```sql
SELECT
    Occurrence_Subtype,
    COUNT(*) AS Bird_Strike_Count
FROM dbo.vw_SafetyIntel_Occurrences
WHERE Activity_Code = 'Bird Strike'
  AND Occurrence_Date >= DATEADD(MONTH, -12, CAST(GETDATE() AS DATE))
GROUP BY Occurrence_Subtype
ORDER BY Bird_Strike_Count DESC, Occurrence_Subtype;
```

### Example 12
User: Most recent runway incursion records.
SQL:
```sql
SELECT TOP 20
    Occurrence_Date,
    Location,
    Organisation_Name,
    Occurrence_Subtype,
    Finding_Level,
    Current_Status,
    Summary
FROM dbo.vw_SafetyIntel_Occurrences
WHERE Activity_Code = 'Runway Incursion'
ORDER BY Occurrence_Date DESC;
```

### Example 13
User: Runway incursion dashboard overview metrics.
SQL:
```sql
SELECT
  Activity_Code,
  Active_Tracks,
  Jamming_Index_Pct,
  Integrity_Index_Pct,
  Loss_Alert_Count,
  Records_Analyzed,
  Primary_Location
FROM dbo.vw_SafetyIntel_OccurrenceOpsOverview
WHERE Activity_Code = 'Runway Incursion';
```

### Example 14
User: Active runway incursion tracks for the operations console.
SQL:
```sql
SELECT TOP 20
  Track_ID,
  Callsign,
  Tail_ID,
  Location,
  Latitude,
  Longitude,
  Heading_Deg,
  Ground_Speed_Kts,
  Flight_Level,
  Integrity_Index_Pct,
  Jamming_Index_Pct,
  Conflict_Risk_Score,
  Conflict_Alert,
  Conflict_Pair,
  Current_Status
FROM dbo.vw_SafetyIntel_OccurrenceOps
WHERE Activity_Code = 'Runway Incursion'
ORDER BY Conflict_Risk_Score DESC, Callsign;
```

### Example 15
User: Bird-strike hotspots for the operations dashboard.
SQL:
```sql
SELECT
  Zone_ID,
  Zone_Label,
  Location,
  Center_Latitude,
  Center_Longitude,
  Event_Count,
  Severity_Band,
  Loss_Alert_Count,
  Integrity_Index_Pct,
  Jamming_Index_Pct
FROM dbo.vw_SafetyIntel_OccurrenceHotspots
WHERE Activity_Code = 'Bird Strike'
ORDER BY Event_Count DESC, Zone_ID;
```

### Example 16
User: Tactical audit note for runway incursion dashboard.
SQL:
```sql
SELECT TOP 1
  Tactical_Audit_ID,
  Track_ID,
  Tail_ID,
  Composite_Risk_Score,
  Intelligence_Summary,
  Action_1,
  Action_2,
  Action_3
FROM dbo.vw_SafetyIntel_TacticalAudit
WHERE Activity_Code = 'Runway Incursion'
ORDER BY Composite_Risk_Score DESC;
```
