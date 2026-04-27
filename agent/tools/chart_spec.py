"""Chart spec tool — turns a result set into a Vega-Lite spec for the canvas.

Design: the **frontend** owns sizing and theming. We just emit a clean
data + mark + encoding spec with sensible field types. Supported intents:

    bar, line, pie, area, scatter, heatmap, table

Field-type inference is the part that traditionally breaks charts (e.g.
year integers misread as temporal). Rules:
- numeric → quantitative
- numeric column whose name looks like a year (Year, *_Year, YYYY) → ordinal
- ISO date string (YYYY-MM-DD…) → temporal
- everything else → nominal
"""
from __future__ import annotations

import re
from typing import Any, Iterable, Literal

ChartIntent = Literal["bar", "line", "pie", "area", "scatter", "heatmap", "table"]

_YEAR_NAME_RE = re.compile(r"(^|_)year($|_)|^yyyy$", re.IGNORECASE)
_ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}(-\d{2})?")


def _looks_like_year(name: str) -> bool:
    return bool(_YEAR_NAME_RE.search(name or ""))


def _looks_iso_date(v: Any) -> bool:
    return isinstance(v, str) and bool(_ISO_DATE_RE.match(v))


def _column_type(field: str, values: Iterable[Any]) -> str:
    """Best-guess Vega-Lite field type."""
    sample = [v for v in values if v is not None][:50]
    if not sample:
        return "nominal"
    # Year columns: keep as ordinal so axes show 2020, 2021… not 2,020.
    if _looks_like_year(field) and all(isinstance(v, (int, float)) for v in sample):
        return "ordinal"
    if all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in sample):
        return "quantitative"
    if all(_looks_iso_date(v) for v in sample):
        return "temporal"
    return "nominal"


def _pick_axes(rows: list[dict[str, Any]], x: str | None, y: str | None) -> tuple[str, str]:
    cols = list(rows[0].keys())
    if x is None:
        x = cols[0]
    if y is None:
        for c in cols:
            if c == x:
                continue
            if any(isinstance(r.get(c), (int, float)) and not isinstance(r.get(c), bool) for r in rows):
                y = c
                break
        if y is None:
            y = cols[1] if len(cols) > 1 else cols[0]
    return x, y


def chart_spec(
    rows: list[dict[str, Any]],
    intent: ChartIntent = "bar",
    x: str | None = None,
    y: str | None = None,
    color: str | None = None,
    title: str | None = None,
) -> dict[str, Any]:
    """Return a Vega-Lite v5 spec (or table artefact) the frontend renders."""
    if not rows:
        return {
            "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
            "title": title,
            "data": {"values": []},
            "mark": "bar",
        }

    if intent == "table":
        return {
            "type": "table",
            "columns": list(rows[0].keys()),
            "rows": rows,
            "title": title,
        }

    x, y = _pick_axes(rows, x, y)
    x_type = _column_type(x, (r.get(x) for r in rows))
    y_type = _column_type(y, (r.get(y) for r in rows))
    if y_type == "ordinal":
        y_type = "quantitative"

    n_rows = len(rows)
    # Long category labels (>14 chars) or many categories → rotate + truncate
    max_x_len = max(
        (len(str(r.get(x, ""))) for r in rows),
        default=0,
    )
    needs_rotation = x_type in ("nominal", "ordinal") and (n_rows > 6 or max_x_len > 14)

    encoding: dict[str, Any] = {}
    mark: Any

    if intent == "pie":
        # For pie, sort slices by value desc and limit legend size for readability
        encoding["theta"] = {
            "field": y, "type": "quantitative",
            "stack": True,
        }
        encoding["color"] = {
            "field": color or x, "type": "nominal",
            "legend": {"title": color or x, "orient": "right", "labelLimit": 180},
            "sort": {"field": y, "order": "descending"},
        }
        encoding["order"] = {"field": y, "type": "quantitative", "sort": "descending"}
        mark = {"type": "arc", "innerRadius": 0, "stroke": "#0f172a", "strokeWidth": 1}
    elif intent == "heatmap":
        cols = list(rows[0].keys())
        z = color or next((c for c in cols if c not in (x, y)), y)
        encoding["x"] = {
            "field": x, "type": x_type,
            "axis": {"labelAngle": -40, "labelLimit": 140},
        }
        encoding["y"] = {
            "field": y, "type": _column_type(y, (r.get(y) for r in rows)),
            "axis": {"labelLimit": 140},
        }
        encoding["color"] = {
            "field": z, "type": "quantitative",
            "scale": {"scheme": "blues"},
            "legend": {"title": z},
        }
        mark = {"type": "rect", "stroke": "#0f172a", "strokeWidth": 1}
    elif intent == "scatter":
        encoding["x"] = {"field": x, "type": x_type if x_type != "nominal" else "quantitative"}
        encoding["y"] = {"field": y, "type": y_type}
        if color:
            encoding["color"] = {"field": color, "type": "nominal"}
        mark = {"type": "point", "filled": True, "size": 80, "opacity": 0.85}
    else:
        x_axis: dict[str, Any] = {"labelLimit": 140}
        if needs_rotation:
            x_axis["labelAngle"] = -40
            x_axis["labelAlign"] = "right"
        else:
            x_axis["labelAngle"] = 0
        encoding["x"] = {"field": x, "type": x_type, "axis": x_axis}
        y_axis: dict[str, Any] = {"format": ",d"}
        y_scale: dict[str, Any] | None = None
        # If y is quantitative integer counts, force integer ticks. tickMinStep
        # alone isn't enough on small ranges (Vega still emits 2,2,1,1,1,0,0
        # because of label-formatting collisions); supply an explicit `values`
        # array and a nice domain so the axis shows 0..max with step 1.
        if y_type == "quantitative":
            y_vals = [r.get(y) for r in rows if isinstance(r.get(y), (int, float)) and not isinstance(r.get(y), bool)]
            if y_vals and all(float(v).is_integer() for v in y_vals):
                y_max = int(max(y_vals))
                if y_max <= 20:
                    y_axis["values"] = list(range(0, y_max + 1))
                    y_scale = {"domain": [0, y_max], "nice": False}
                else:
                    y_axis["tickMinStep"] = 1
        y_enc: dict[str, Any] = {"field": y, "type": y_type, "axis": y_axis}
        if y_scale:
            y_enc["scale"] = y_scale
        encoding["y"] = y_enc
        if color:
            encoding["color"] = {"field": color, "type": "nominal"}
        if intent == "line":
            mark = {"type": "line", "point": {"size": 60, "filled": True}, "interpolate": "monotone", "strokeWidth": 2.5}
        elif intent == "area":
            mark = {"type": "area", "opacity": 0.6, "line": True, "point": True}
        else:
            mark = {"type": "bar", "cornerRadiusEnd": 3}
            # For bar with a quantitative y, sort x by y descending so the
            # tallest bars come first (typical "top N" visual).
            if x_type in ("nominal", "ordinal") and y_type == "quantitative":
                encoding["x"]["sort"] = {"field": y, "order": "descending"}

    encoding["tooltip"] = [{"field": c} for c in rows[0].keys()]

    spec: dict[str, Any] = {
        "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
        "title": title,
        "data": {"values": rows},
        "mark": mark,
        "encoding": encoding,
    }

    # Heatmap: overlay numeric value as text on each cell so users can read
    # the actual count, not just guess from color saturation.
    if intent == "heatmap":
        cols = list(rows[0].keys())
        z = color or next((c for c in cols if c not in (x, y)), y)
        # Compute a midpoint so the text colour flips (white on dark cells, dark
        # on light cells). Hard-coding `>5` was wrong when max value was 1 or 2.
        z_vals = [r.get(z) for r in rows if isinstance(r.get(z), (int, float)) and not isinstance(r.get(z), bool)]
        z_max = max(z_vals) if z_vals else 1
        z_mid = z_max / 2.0
        spec = {
            "$schema": spec["$schema"],
            "title": title,
            "data": {"values": rows},
            "encoding": {
                "x": encoding["x"],
                "y": encoding["y"],
            },
            "layer": [
                {"mark": mark, "encoding": {"color": encoding["color"], "tooltip": encoding["tooltip"]}},
                {
                    "mark": {"type": "text", "fontSize": 11, "fontWeight": 600},
                    "encoding": {
                        "text": {"field": z, "type": "quantitative", "format": ",d"},
                        "color": {
                            "condition": {"test": f"datum['{z}'] > {z_mid}", "value": "white"},
                            "value": "#0f172a",
                        },
                    },
                },
            ],
        }

    return spec
