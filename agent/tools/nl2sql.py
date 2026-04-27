"""NL→T-SQL tool for Synapse Dedicated SQL Pool.

Security:
- Auth via Microsoft Entra ID access token (DefaultAzureCredential).
- Connects to Synapse using ODBC Driver 18 with `Authentication=ActiveDirectoryAccessToken`.
- No username/password / no connection string secret.
- Statements are validated as a single read-only SELECT against vw_SafetyIntel_* views.
"""
from __future__ import annotations

import os
import re
import struct
from decimal import Decimal
from typing import Any

import pyodbc
from azure.identity import DefaultAzureCredential

# --- allowed surface --------------------------------------------------------
_ALLOWED_VIEW_PREFIX = "vw_safetyintel_"
_FORBIDDEN_RE = re.compile(
    r"\b(insert|update|delete|merge|drop|alter|truncate|grant|revoke|deny|exec|execute|"
    r"sp_|xp_|create|backup|restore|shutdown|kill|use|openrowset|opendatasource|bulk)\b",
    re.IGNORECASE,
)
_SELECT_RE = re.compile(r"^\s*(with\b.+?\bselect\b|select\b)", re.IGNORECASE | re.DOTALL)
_VIEW_REF_RE = re.compile(r"\b(?:dbo\.)?(vw_safetyintel_[a-z_]+)", re.IGNORECASE)


class SqlSafetyError(ValueError):
    """Raised when generated SQL violates the read-only allow-list."""


def _validate_sql(sql: str) -> None:
    sql_stripped = sql.strip().rstrip(";")
    if ";" in sql_stripped:
        raise SqlSafetyError("Multiple statements are not allowed.")
    if not _SELECT_RE.match(sql_stripped):
        raise SqlSafetyError("Only SELECT/CTE statements are allowed.")
    if _FORBIDDEN_RE.search(sql_stripped):
        raise SqlSafetyError("Statement contains forbidden keywords.")
    refs = _VIEW_REF_RE.findall(sql_stripped)
    if not refs:
        raise SqlSafetyError("Statement must reference vw_SafetyIntel_* views only.")
    for ref in refs:
        if not ref.lower().startswith(_ALLOWED_VIEW_PREFIX):
            raise SqlSafetyError(f"View '{ref}' is not in the allow-list.")


# --- connection (Entra ID token, no password) -------------------------------
_credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)


def _build_connection() -> pyodbc.Connection:
    server = os.environ["SYNAPSE_SQL_SERVER"]    # e.g. workspace.sql.azuresynapse.net
    database = os.environ["SYNAPSE_SQL_DATABASE"]
    conn_str = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server=tcp:{server},1433;"
        f"Database={database};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    token = _credential.get_token("https://database.windows.net/.default").token
    token_bytes = token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    SQL_COPT_SS_ACCESS_TOKEN = 1256  # noqa: N806
    return pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct})


# --- public tool entry point ------------------------------------------------
def run_nl2sql(sql: str, max_rows: int = 200) -> dict[str, Any]:
    """Execute an LLM-generated SELECT against Synapse and return JSON rows.

    Args:
        sql: SQL produced by the LLM. Must be a single SELECT/CTE that reads
             only from vw_SafetyIntel_* views.
        max_rows: hard cap on rows returned to the agent.

    Returns:
        {"columns": [...], "rows": [...], "row_count": n, "sql": <validated>}
    """
    _validate_sql(sql)
    with _build_connection() as conn, conn.cursor() as cur:
        cur.execute(sql)
        columns = [d[0] for d in cur.description] if cur.description else []
        rows = []
        for i, r in enumerate(cur.fetchmany(max_rows)):
            rows.append({c: _coerce(v) for c, v in zip(columns, r)})
            if i + 1 >= max_rows:
                break
    return {"columns": columns, "rows": rows, "row_count": len(rows), "sql": sql}


def _coerce(v: Any) -> Any:
    if v is None:
        return None
    if isinstance(v, Decimal):
        if v == v.to_integral_value():
            return int(v)
        return float(v)
    if hasattr(v, "isoformat"):
        return v.isoformat()
    return v
