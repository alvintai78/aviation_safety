# Safety Intelligence Bot — Web UI

Vite + React + TypeScript SPA that talks to the FastAPI backend (`agent/app.py`) over SSE.

## Layout
- **Left rail** — analyst chat with the Foundry agent (`/chat` SSE).
- **Main workspace** — modern operations canvas with KPI strip, spotlight visualization, intelligence rail, and supporting analytics.
- **Artifacts supported**:
  - **Vega-Lite charts** from `chart_spec`
  - **Table artifacts** from `chart_spec(intent="table")`
  - **Ops dashboard artifacts** from `dashboard_spec` for runway-incursion and bird-strike POC screens
- **Tool trace** — every `nl2sql` / `chart_spec` / `dashboard_spec` / `doc_search` call with arguments and outputs.

## Develop locally
```bash
cd agent/web
npm install
npm run dev          # http://localhost:5173, proxies /chat to :7700
# In another terminal:
cd agent && uvicorn app:app --reload --port 7700
```

## Build for production
```bash
cd agent/web
npm run build        # emits to ../static (mounted by FastAPI)
```

The Dockerfile runs the build automatically (multi-stage).

## Local POC preview

If you only want to preview the runway-incursion and bird-strike cockpit UI,
start the backend in demo mode:

```bash
cd agent
scripts/run_demo_mode.sh
```

Then open the SPA and send either demo prompt. The backend will emit canned
`dashboard_spec` and `chart_spec` artifacts without requiring Foundry or Synapse.
