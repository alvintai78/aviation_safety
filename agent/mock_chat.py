"""Local demo-mode chat stream for UI preview without Foundry.

Enable with:
    SAFETY_INTEL_DEMO_MODE=1
"""
from __future__ import annotations

import asyncio
import json
from typing import AsyncIterator

from tools import chart_spec, dashboard_spec


RUNWAY_OVERVIEW = [{
    "Activity_Code": "Runway Incursion",
    "Active_Tracks": 7,
    "Jamming_Index_Pct": 3,
    "Integrity_Index_Pct": 94,
    "Loss_Alert_Count": 1,
    "Records_Analyzed": 30,
    "Primary_Location": "WSSS",
}]

RUNWAY_TRACKS = [
    {"Track_ID": "OPS-RI-001", "Callsign": "TGW598", "Tail_ID": "9V-761", "Location": "WSSS", "Latitude": 1.3541, "Longitude": 103.9871, "Heading_Deg": 266, "Ground_Speed_Kts": 265, "Flight_Level": "FL95", "Integrity_Index_Pct": 96, "Jamming_Index_Pct": 3, "Conflict_Risk_Score": 25, "Conflict_Alert": "Conflict alert", "Conflict_Pair": "SIA212", "Current_Status": "Monitoring"},
    {"Track_ID": "OPS-RI-002", "Callsign": "TGW427", "Tail_ID": "9V-427", "Location": "WSSS", "Latitude": 1.3508, "Longitude": 103.9921, "Heading_Deg": 281, "Ground_Speed_Kts": 246, "Flight_Level": "FL90", "Integrity_Index_Pct": 94, "Jamming_Index_Pct": 4, "Conflict_Risk_Score": 18, "Conflict_Alert": "Vehicle crossing active runway", "Conflict_Pair": "TGW598", "Current_Status": "Monitoring"},
    {"Track_ID": "OPS-RI-003", "Callsign": "TGW676", "Tail_ID": "9V-676", "Location": "WSSS", "Latitude": 1.3487, "Longitude": 103.9981, "Heading_Deg": 302, "Ground_Speed_Kts": 480, "Flight_Level": "FL340", "Integrity_Index_Pct": 97, "Jamming_Index_Pct": 2, "Conflict_Risk_Score": 12, "Conflict_Alert": None, "Conflict_Pair": None, "Current_Status": "Monitoring"},
]

RUNWAY_HOTSPOTS = [
    {"Zone_ID": "GRID-RI-01", "Zone_Label": "South runway crossing", "Location": "WSSS", "Center_Latitude": 1.3519, "Center_Longitude": 103.9912, "Event_Count": 8, "Severity_Band": "critical", "Loss_Alert_Count": 1, "Integrity_Index_Pct": 95, "Jamming_Index_Pct": 3},
    {"Zone_ID": "GRID-RI-02", "Zone_Label": "Taxi lane cluster", "Location": "WSSS", "Center_Latitude": 1.3492, "Center_Longitude": 103.9898, "Event_Count": 6, "Severity_Band": "watch", "Loss_Alert_Count": 0, "Integrity_Index_Pct": 94, "Jamming_Index_Pct": 4},
]

RUNWAY_TACTICAL = [{
    "Tactical_Audit_ID": "TACT-RI-001",
    "Track_ID": "OPS-RI-001",
    "Tail_ID": "9V-761",
    "Composite_Risk_Score": 25,
    "Intelligence_Summary": "Vehicle crossing risk remains concentrated on the southern runway transition with one active conflict pair still under watch.",
    "Action_1": "Reconfirm runway access control and escort procedure for all ground vehicles.",
    "Action_2": "Issue a targeted radio phraseology reminder to tug and maintenance crews.",
    "Action_3": "Review hold-point signage and low-visibility taxi brief for the current shift.",
}]

RUNWAY_RECENT = [
    {"Occurrence_Date": "2025-01-22", "Location": "WSSS", "Organisation_Name": "Hawker Pacific Airservices Pte Ltd", "Occurrence_Subtype": "Unauthorised entry", "Finding_Level": "Level 2", "Current_Status": "In-progress", "Summary": "Ground vehicle entered active runway without ATC clearance; investigation ongoing."},
    {"Occurrence_Date": "2024-12-11", "Location": "WSSS", "Organisation_Name": "Changi Avionics Services Pte Ltd", "Occurrence_Subtype": "Vehicle on active runway", "Finding_Level": "Level 2", "Current_Status": "Closed", "Summary": "Maintenance van entered active runway; SOP gap closed with new radio procedure."},
    {"Occurrence_Date": "2024-06-08", "Location": "VHHH", "Organisation_Name": "SIAEC Line Maintenance (HKG)", "Occurrence_Subtype": "Taxi past hold point", "Finding_Level": "Level 2", "Current_Status": "Closed", "Summary": "Aircraft taxied past CAT II hold point; crew briefed on low-visibility procedures."},
]

BIRD_TREND = [
    {"Occurrence_Month": "2025-05", "Bird_Strike_Count": 2},
    {"Occurrence_Month": "2025-06", "Bird_Strike_Count": 3},
    {"Occurrence_Month": "2025-07", "Bird_Strike_Count": 3},
    {"Occurrence_Month": "2025-08", "Bird_Strike_Count": 4},
    {"Occurrence_Month": "2025-09", "Bird_Strike_Count": 5},
    {"Occurrence_Month": "2025-10", "Bird_Strike_Count": 4},
    {"Occurrence_Month": "2025-11", "Bird_Strike_Count": 3},
    {"Occurrence_Month": "2025-12", "Bird_Strike_Count": 4},
    {"Occurrence_Month": "2026-01", "Bird_Strike_Count": 6},
    {"Occurrence_Month": "2026-02", "Bird_Strike_Count": 5},
    {"Occurrence_Month": "2026-03", "Bird_Strike_Count": 7},
    {"Occurrence_Month": "2026-04", "Bird_Strike_Count": 6},
]

BIRD_HOTSPOTS = [
    {"Zone_ID": "GRID-BS-01", "Zone_Label": "Approach wildlife corridor", "Location": "WSSS", "Center_Latitude": 1.3574, "Center_Longitude": 103.9779, "Event_Count": 7, "Severity_Band": "critical", "Loss_Alert_Count": 0, "Integrity_Index_Pct": 95, "Jamming_Index_Pct": 2},
    {"Zone_ID": "GRID-BS-02", "Zone_Label": "Coastal climb-out corridor", "Location": "WSSS", "Center_Latitude": 1.3602, "Center_Longitude": 103.9836, "Event_Count": 5, "Severity_Band": "watch", "Loss_Alert_Count": 0, "Integrity_Index_Pct": 94, "Jamming_Index_Pct": 3},
]

BIRD_TRACKS = [
    {"Track_ID": "OPS-BS-001", "Callsign": "BIR231", "Tail_ID": "9V-STF", "Location": "WSSS", "Latitude": 1.3592, "Longitude": 103.9752, "Heading_Deg": 192, "Ground_Speed_Kts": 154, "Flight_Level": "FL70", "Integrity_Index_Pct": 95, "Jamming_Index_Pct": 2, "Conflict_Risk_Score": 14, "Conflict_Alert": "Wildlife cluster ahead", "Conflict_Pair": None, "Current_Status": "Open"},
    {"Track_ID": "OPS-BS-002", "Callsign": "BIR118", "Tail_ID": "9V-JAS", "Location": "WSSS", "Latitude": 1.3578, "Longitude": 103.9795, "Heading_Deg": 205, "Ground_Speed_Kts": 162, "Flight_Level": "FL82", "Integrity_Index_Pct": 94, "Jamming_Index_Pct": 3, "Conflict_Risk_Score": 16, "Conflict_Alert": "Multiple flock signatures", "Conflict_Pair": None, "Current_Status": "Open"},
]

BIRD_TACTICAL = [{
    "Tactical_Audit_ID": "TACT-BS-001",
    "Track_ID": "OPS-BS-002",
    "Tail_ID": "9V-JAS",
    "Composite_Risk_Score": 22,
    "Intelligence_Summary": "Bird-strike pressure remains concentrated on approach and climb-out corridors, with windshield and ingestion events overrepresented.",
    "Action_1": "Synchronise wildlife dispersal patrols with the morning arrival bank.",
    "Action_2": "Brief line inspectors to prioritise radome, windshield, and fan-blade checks after reports.",
    "Action_3": "Track repeat subtypes by location to separate random strikes from persistent habitat issues.",
}]

BIRD_RECENT = [
    {"Occurrence_Date": "2025-04-02", "Location": "KATL", "Organisation_Name": "Delta TechOps", "Occurrence_Subtype": "Engine fan damage", "Finding_Level": "Level 2", "Current_Status": "In-progress", "Summary": "Bird ingestion caused fan blade damage; engine removed for shop inspection."},
    {"Occurrence_Date": "2025-01-05", "Location": "OMAA", "Organisation_Name": "Etihad Engineering", "Occurrence_Subtype": "Cockpit window", "Finding_Level": "Level 3", "Current_Status": "In-progress", "Summary": "Bird strike on First Officer windshield during descent; inner-pane crack."},
    {"Occurrence_Date": "2024-07-01", "Location": "WIII", "Organisation_Name": "GMF AeroAsia Indonesia", "Occurrence_Subtype": "Lower fuselage", "Finding_Level": "OBS", "Current_Status": "Closed", "Summary": "Bird remains found on lower fuselage post-landing; no damage."},
]

BIRD_SUBTYPES = [
    {"Occurrence_Subtype": "Engine fan damage", "Bird_Strike_Count": 4},
    {"Occurrence_Subtype": "Cockpit window", "Bird_Strike_Count": 3},
    {"Occurrence_Subtype": "Windshield impact", "Bird_Strike_Count": 3},
    {"Occurrence_Subtype": "Lower fuselage", "Bird_Strike_Count": 2},
]


async def run_mock_chat_stream(session_id: str, message: str) -> AsyncIterator[dict]:
    del session_id
    text = message.strip().lower()

    if "runway incursion" in text:
        async for event in _runway_dashboard_events():
            yield event
        return

    if "bird strike" in text:
        async for event in _bird_dashboard_events():
            yield event
        return

    yield {
        "type": "final",
        "data": "Demo mode is active. Try one of these prompts: 'Show me the runway incursion dashboard' or 'Analyze recent bird strike'.",
    }


async def _runway_dashboard_events() -> AsyncIterator[dict]:
    dashboard = dashboard_spec(
        datasets=[
            {"name": "overview", "rows": RUNWAY_OVERVIEW},
            {"name": "tracks", "rows": RUNWAY_TRACKS},
            {"name": "hotspots", "rows": RUNWAY_HOTSPOTS},
            {"name": "tactical_audit", "rows": RUNWAY_TACTICAL},
            {"name": "recent_records", "rows": RUNWAY_RECENT},
        ],
        title="Runway Incursion Operations Dashboard",
        domain="runway_incursion",
        focus="Runway incursion control-tower view",
    )
    yield {"type": "tool_call", "data": {"name": "dashboard_spec", "arguments": {"domain": "runway_incursion"}}}
    await asyncio.sleep(0)
    yield {"type": "tool_result", "data": {"name": "dashboard_spec", "output": json.dumps(dashboard)}}
    await asyncio.sleep(0)
    yield {
        "type": "final",
        "data": "- One active conflict pair remains concentrated on the WSSS south-runway crossing corridor.\n- Telemetry quality is stable, but vehicle-crossing and phraseology gaps still dominate the open risk picture.\n- Recent records show the same runway-transition pattern repeating across tug, maintenance-vehicle, and taxi-hold events.\n\nSources:\n- vw_SafetyIntel_OccurrenceOpsOverview\n- vw_SafetyIntel_OccurrenceOps\n- vw_SafetyIntel_OccurrenceHotspots\n- vw_SafetyIntel_TacticalAudit\n- vw_SafetyIntel_Occurrences",
    }


async def _bird_dashboard_events() -> AsyncIterator[dict]:
    trend = chart_spec(BIRD_TREND, intent="line", x="Occurrence_Month", y="Bird_Strike_Count", title="Bird strikes by month (last 12 months)")
    breakdown = chart_spec(BIRD_SUBTYPES, intent="bar", x="Occurrence_Subtype", y="Bird_Strike_Count", title="Bird strike subtypes")
    dashboard = dashboard_spec(
        datasets=[
            {"name": "tracks", "rows": BIRD_TRACKS},
            {"name": "hotspots", "rows": BIRD_HOTSPOTS},
            {"name": "tactical_audit", "rows": BIRD_TACTICAL},
            {"name": "recent_records", "rows": BIRD_RECENT},
        ],
        title="Bird Strike Operations Dashboard",
        domain="bird_strike",
        focus="Recent bird-strike review",
    )
    for name, output in (
        ("chart_spec", trend),
        ("chart_spec", breakdown),
        ("dashboard_spec", dashboard),
    ):
        yield {"type": "tool_call", "data": {"name": name, "arguments": {"demo": True}}}
        await asyncio.sleep(0)
        yield {"type": "tool_result", "data": {"name": name, "output": json.dumps(output)}}
        await asyncio.sleep(0)
    yield {
        "type": "final",
        "data": "- Bird-strike counts are trending upward into the latest quarter, with the highest pressure in the most recent two months.\n- Engine, windshield, and cockpit-window events remain the dominant subtype pattern.\n- Current hotspots cluster around WSSS approach and climb-out corridors, which matches the tactical note's mitigation focus.\n\nSources:\n- vw_SafetyIntel_Occurrences\n- vw_SafetyIntel_OccurrenceHotspots\n- vw_SafetyIntel_OccurrenceOps\n- vw_SafetyIntel_TacticalAudit",
    }