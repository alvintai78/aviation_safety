"""FastAPI BFF for the Safety Intelligence Bot front-end.

Endpoints
---------
- GET  /healthz  -> always 200 ok (liveness)
- GET  /readyz   -> 200 if FOUNDRY_AGENT_NAME is set, else 503 with hint
- POST /chat     -> streams agent reply as SSE

Auth: managed identity (DefaultAzureCredential). No API keys.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from agent import run_chat_stream
from mock_chat import run_mock_chat_stream

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("safety-intel-bot")

app = FastAPI(title="Safety Intelligence Bot")


def _demo_mode_enabled() -> bool:
    return os.environ.get("SAFETY_INTEL_DEMO_MODE", "").strip().lower() in {"1", "true", "yes", "on"}

# Built React SPA (web/ -> static/ via `npm run build`).
_STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
_STATIC_AVAILABLE = os.path.isdir(_STATIC_DIR) and os.path.isfile(
    os.path.join(_STATIC_DIR, "index.html")
)


class ChatIn(BaseModel):
    session_id: str
    message: str


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz() -> dict[str, str]:
    if _demo_mode_enabled():
        return {"status": "ready", "agent_name": "demo-mode"}

    name = os.environ.get("FOUNDRY_AGENT_NAME")
    if not name:
        raise HTTPException(
            503,
            "FOUNDRY_AGENT_NAME not set. Run scripts/create_foundry_agent.py "
            "(Post_Deployment_Steps.md §6) and set the env var (§7).",
        )
    return {"status": "ready", "agent_name": name}


@app.post("/chat")
async def chat(body: ChatIn):
    if not _demo_mode_enabled() and not os.environ.get("FOUNDRY_AGENT_NAME"):
        raise HTTPException(503, "FOUNDRY_AGENT_NAME not set; see /readyz")

    async def stream():
        try:
            runner = run_mock_chat_stream if _demo_mode_enabled() else run_chat_stream
            async for event in runner(body.session_id, body.message):
                yield f"data: {json.dumps(event)}\n\n"
                await asyncio.sleep(0)
        except Exception as e:  # noqa: BLE001
            log.exception("agent run failed")
            yield f"data: {json.dumps({'type': 'error', 'data': str(e)})}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


# Mount the React SPA last so /chat, /healthz, /readyz keep priority.
if _STATIC_AVAILABLE:
    app.mount(
        "/assets",
        StaticFiles(directory=os.path.join(_STATIC_DIR, "assets")),
        name="assets",
    )

    @app.get("/")
    async def _spa_root() -> FileResponse:
        return FileResponse(os.path.join(_STATIC_DIR, "index.html"))

    @app.get("/{spa_path:path}")
    async def _spa_catchall(spa_path: str) -> FileResponse:
        # Serve a real file if it exists (favicon, etc.); otherwise fall back to index.html.
        candidate = os.path.join(_STATIC_DIR, spa_path)
        if os.path.isfile(candidate):
            return FileResponse(candidate)
        return FileResponse(os.path.join(_STATIC_DIR, "index.html"))
else:
    log.info("static/ not found — SPA disabled (API-only mode)")
