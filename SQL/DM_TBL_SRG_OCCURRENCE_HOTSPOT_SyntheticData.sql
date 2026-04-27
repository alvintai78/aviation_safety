INSERT INTO dbo.DM_TBL_SRG_OCCURRENCE_HOTSPOT (Zone_ID, Activity_Code, Location, Zone_Label, Center_Latitude, Center_Longitude, Event_Count, Severity_Band, Loss_Alert_Count, Integrity_Index_Pct, Jamming_Index_Pct, data_last_updated, dm_refresh_date) VALUES
('GRID-RI-01','Runway Incursion','WSSS','South runway crossing',1.351900,103.991200,8,'critical',1,95.0,3.0,'2026-04-22 09:15:00','2026-04-22 09:15:00'),
('GRID-RI-02','Runway Incursion','WSSS','Taxi lane cluster',1.349200,103.989800,6,'watch',0,94.0,4.0,'2026-04-22 09:15:00','2026-04-22 09:15:00'),
('GRID-RI-03','Runway Incursion','WSSS','Apron transition',1.346800,103.995400,4,'watch',0,96.0,2.0,'2026-04-22 09:15:00','2026-04-22 09:15:00'),
('GRID-BS-01','Bird Strike','WSSS','Approach wildlife corridor',1.357400,103.977900,7,'critical',0,95.0,2.0,'2026-04-22 09:15:00','2026-04-22 09:15:00'),
('GRID-BS-02','Bird Strike','WSSS','Coastal climb-out corridor',1.360200,103.983600,5,'watch',0,94.0,3.0,'2026-04-22 09:15:00','2026-04-22 09:15:00'),
('GRID-BS-03','Bird Strike','WIII','Jakarta final approach',-6.118300,106.657300,4,'watch',0,96.0,2.0,'2026-04-22 09:15:00','2026-04-22 09:15:00');
GO