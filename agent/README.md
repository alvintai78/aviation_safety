# Safety Intelligence Bot — Agent

Microsoft Foundry agent for the CAAS Safety Regulation Department.

## Security baseline (mandatory)

| Concern | Choice |
|---|---|
| Authentication | **Microsoft Entra ID only** via `DefaultAzureCredential` (managed identity in Azure, `az login` locally). |
| API keys / connection strings | **Forbidden.** No `AZURE_OPENAI_API_KEY`, `AZURE_SEARCH_API_KEY`, SQL passwords, or service-principal secrets. |
| Networking | All Azure resources reachable **only via private endpoints** in the CAAS VNet. Public network access disabled on each PaaS resource. |
| Secrets in code | None. Everything is either an Entra-ID token or a non-sensitive resource URL injected via App Settings / env vars. |
| Key Vault | Used only for non-token secrets we cannot avoid (e.g. third-party OAuth client IDs, if any). Accessed via managed identity, never via a key. |

## Components

- `app.py` — FastAPI BFF that exposes `/chat` and streams Foundry agent responses to the React canvas UI.
- `agent.py` — runs the Foundry Responses client and dispatches four local tools: `nl2sql`, `doc_search`, `chart_spec`, `dashboard_spec`.
- `tools/nl2sql.py` — schema-grounded NL→T-SQL over `vw_SafetyIntel_*` views, executed via `pyodbc` with **Entra ID access token** (no SQL login).
- `tools/doc_search.py` — Azure AI Search retrieval against the `safety-docs` index using **managed-identity** auth.
- `tools/chart_spec.py` — returns a Vega-Lite spec the canvas renders.
- `tools/dashboard_spec.py` — assembles multiple occurrence result sets into a specialised operations-dashboard artifact for the cockpit-style UI.
- `mock_chat.py` — local demo-mode SSE flow for the runway-incursion and bird-strike showcase prompts.
- `prompts/system.md` — system prompt with guardrails and citation rules.
- `prompts/nl2sql_examples.md` — few-shot examples grounded in the `vw_SafetyIntel_*` views.
- `requirements.txt` — pinned packages.
- `infra/main.bicep` (skeleton) — provisions Foundry, AOAI, Synapse-link, AI Search, ADLS, Key Vault, App Service with **system-assigned managed identity**, **private endpoints** and **public network access disabled**.

## Local dev

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
az login                                # interactive Entra ID login
cp .env.example .env
export AZURE_OPENAI_ENDPOINT="https://<your-aoai>.openai.azure.com"
export AZURE_OPENAI_DEPLOYMENT="gpt-4o"
export SYNAPSE_SQL_SERVER="<workspace>.sql.azuresynapse.net"
export SYNAPSE_SQL_DATABASE="SafetyRegulationDM"
export SEARCH_ENDPOINT="https://<your-search>.search.windows.net"
export SEARCH_INDEX="safety-docs"
uvicorn app:app --reload --port 7700
```

To refresh the Foundry-specific local env file directly from the known ARM deployment:

```bash
cd agent
scripts/load_foundry_env.sh
```

`scripts/create_foundry_agent.py` now auto-loads `agent/.env.foundry` first and
then `agent/.env`, so direct execution works without re-exporting the project
endpoint every time.

In Azure, the same env vars are set as App Settings; **no keys, no passwords**. The App Service / Container App's system-assigned managed identity has these RBAC role assignments:

| Resource | Role |
|---|---|
| Azure OpenAI | Cognitive Services OpenAI User |
| Azure AI Foundry project | Azure AI User |
| Azure AI Search | Search Index Data Reader |
| ADLS Gen2 (docs container) | Storage Blob Data Reader |
| Synapse SQL Pool | Database role: `db_datareader` granted to the managed identity (Entra ID login) on `vw_SafetyIntel_*` views only |
| Key Vault (if used) | Key Vault Secrets User |

## Local demo mode

For UI-only preview without Foundry or Synapse, run:

```bash
cd agent
chmod +x scripts/run_demo_mode.sh
scripts/run_demo_mode.sh
```

This enables `SAFETY_INTEL_DEMO_MODE=1`, makes `/readyz` return `demo-mode`,
and serves canned SSE responses for:

- `Show me the runway incursion dashboard`
- `Analyze recent bird strike`

## POC SQL rollout

Use [SQL/rollout_occurrence_ops_poc.sql](/Users/alvintai/work/code/CAAS/SafetyRegulation/SQL/rollout_occurrence_ops_poc.sql) to create the new occurrence-ops tables, seed the synthetic data, and recreate the new views in one pass.
