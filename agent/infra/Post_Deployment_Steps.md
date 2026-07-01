# Safety Intelligence Bot — Post-Deployment Steps

You have run `infra/deploy.sh` successfully and all SQL objects are present in Synapse. This document is the **step-by-step checklist** to take the deployment from "infrastructure exists" to "agent visible in Microsoft Foundry portal and answering questions from the React canvas".

> **Why no agent shows up in Foundry yet?**
> `main.bicep` only creates the **Foundry resource** (`srgsib-foundry`) and a **Foundry project** (`srgsib-prj`), and wires the project into **Standard Agent Setup** (BYO Cosmos DB, BYO Storage, existing AI Search, all keyless via project MI). It does **not** create an agent. The Container App talks to Foundry through the **v2 Agents API (Responses)** — `azure-ai-projects` 2.x + the `openai` SDK pointed at the agent endpoint. To make the bot work end-to-end you must register a **PromptAgent** via the v2 SDK. Steps 6–7 below do exactly that. Until §6 is done, `/healthz` returns 200 but `/chat` returns 503 with a hint.
>
> **Standard vs Basic Agent Setup**: This deployment runs **Standard** (output `foundrySetupMode = "Standard"`). All threads/messages persist in your Cosmos DB account `srgsib-cosmos-xxxxx` and uploaded files persist in your dedicated Storage account `srgsibagstxxxxxxx`. Both are private (PE-only, AAD-only). The first agent created via §6 will be the first one bound to these stores.

---

## 0. Confirm what was deployed

```bash
export RG=CAAS
export SUB=57bbd325-81fb-4c5f-adee-489263236d32
az account set --subscription "$SUB"

# Pick the latest SUCCESSFUL srgsib-* deployment (sorted by timestamp).
export DEPLOY=$(az deployment group list -g "$RG" \
  --query "sort_by([?starts_with(name,'srgsib-') && properties.provisioningState=='Succeeded'], &properties.timestamp)[-1].name" \
  -o tsv)
echo "DEPLOY=$DEPLOY"

# Sanity-check: dump the outputs object.
az deployment group show -g "$RG" -n "$DEPLOY" --query properties.outputs -o jsonc
```

Capture these values — every step below uses them:

| Variable | Output key |
|---|---|
| `FOUNDRY` | `foundryAccountName` (e.g. `srgsib-foundry`) |
| `PROJECT` | `foundryProjectName` (e.g. `srgsib-prj`) |
| `PROJECT_ENDPOINT` | `foundryProjectEndpoint` |
| `AOAI_ENDPOINT` | `aoaiEndpoint` |
| `SEARCH_ENDPOINT` | `searchEndpoint` |
| `ACR` | `acrName` |
| `ACR_LOGIN` | `acrLoginServer` |
| `APP_NAME` | `containerAppName` (e.g. `srgsib-app`) |
| `APP_FQDN` | `containerAppFqdn` |
| `APP_PID` | `containerAppPrincipalId` |

```bash
# Read all 10 outputs into shell vars. `paste -s -d' ' -` flattens the
# 10 tab-separated values onto one line so `read` can split them.
read FOUNDRY PROJECT PROJECT_ENDPOINT AOAI_ENDPOINT SEARCH_ENDPOINT \
     ACR ACR_LOGIN APP_NAME APP_FQDN APP_PID <<<"$(
  az deployment group show -g "$RG" -n "$DEPLOY" --query \
    "[properties.outputs.foundryAccountName.value, \
      properties.outputs.foundryProjectName.value, \
      properties.outputs.foundryProjectEndpoint.value, \
      properties.outputs.aoaiEndpoint.value, \
      properties.outputs.searchEndpoint.value, \
      properties.outputs.acrName.value, \
      properties.outputs.acrLoginServer.value, \
      properties.outputs.containerAppName.value, \
      properties.outputs.containerAppFqdn.value, \
      properties.outputs.containerAppPrincipalId.value]" \
    -o tsv | paste -s -d' ' -
)"

# Verify (none of these should be empty or 'None')
printf '%-18s %s\n' FOUNDRY "$FOUNDRY" PROJECT "$PROJECT" \
  PROJECT_ENDPOINT "$PROJECT_ENDPOINT" APP_NAME "$APP_NAME" \
  APP_FQDN "$APP_FQDN" APP_PID "$APP_PID" ACR_LOGIN "$ACR_LOGIN"
```

> **If any variable is empty:**
> 1. `echo $RG $DEPLOY` — both must be non-empty (the most common cause of the original failure was running the `read ...` line in a fresh shell where `RG` and `DEPLOY` were never set).
> 2. `az deployment group list -g "$RG" --query "[?starts_with(name,'srgsib-')].{n:name,s:properties.provisioningState}" -o table` — confirm at least one `Succeeded` deployment exists.
> 3. The query path **must** be `properties.outputs.<key>.value` (not `outputs.<key>.value`) when using `az deployment group show`.

Verify the model deployments exist on the Foundry account:

```bash
az cognitiveservices account deployment list -g "$RG" -n "$FOUNDRY" -o table
# expect: gpt-5.2 (chatModelDeploymentName), text-embedding-3-large
```

---

## 1. Grant the Container App MSI access to the Synapse SQL pool

The Container App's system-assigned MI must be a Synapse SQL pool user with `db_datareader`. Do this from a host that can reach the Synapse private endpoint (jumpbox in the VNet, Bastion, or Synapse Studio if you opened a temporary firewall rule).

Connect to the dedicated SQL pool **as an Entra admin** and run:

```sql
-- Use the Container App name as the external user (Entra MSI).
-- NOTE: Azure Synapse Dedicated SQL Pool does NOT support
-- `ALTER ROLE db_datareader ADD MEMBER ...` (that is Azure SQL DB / SQL Server
-- syntax). Use the legacy stored procedure instead.
CREATE USER [srgsib-app] FROM EXTERNAL PROVIDER;
EXEC sp_addrolemember 'db_datareader', 'srgsib-app';

-- Optional: scope tighter than the role default (views only)
GRANT SELECT ON SCHEMA::dbo TO [srgsib-app];
DENY  SELECT ON OBJECT::dbo.DM_TBL_SRG_AMO_MOA TO [srgsib-app];   -- example: block raw tables
-- ...repeat DENY for each base table you want hidden, or just keep db_datareader.
```

> If your tenant has `Allow Azure AD only authentication` on the Synapse workspace, you must already be signed in as an Entra admin to issue these statements.

---

## 2. Create the AI Search index `safety-docs`

The Container App expects an index named `safety-docs` (`SEARCH_INDEX` env var) reachable over the private endpoint. The index needs:

- A vector field (`content_vector`, dim = 3072 for `text-embedding-3-large`)
- A semantic config named `safety-docs-semantic`
- An indexer reading from the ADLS `docs/` filesystem, with **integrated vectorization** pointing at the `text-embedding-3-large` deployment on the Foundry resource

Easiest path (run from a VNet-attached jumpbox so private endpoints resolve):

```bash
# 2a. Create the docs container in ADLS (keyless, MI/Entra)
az storage fs create -n docs --account-name caasadlsv2 --auth-mode login

# 2b. Upload your regulatory PDFs / DOCX
az storage fs directory upload \
  -f docs --account-name caasadlsv2 --auth-mode login \
  -s ./regulatory-docs -d / --recursive
```

Then create the index + indexer. Recommended: use the **Azure AI Search "Import and vectorize data"** wizard (the new Foundry portal no longer hosts the index-creation wizard for an external Search service — you build the index in Azure AI Search and then *attach* it as Knowledge in Foundry afterward).

**A. Build the index in Azure AI Search**

1. Azure portal → search service `srgsib-search` → **Overview** → **Import and vectorize data**.
2. Scenario tile: choose **RAG** (text-only). Pick *Multimodal RAG* only if you need image/diagram understanding.
3. **Connect to your data** → **Azure Blob Storage / ADLS Gen2**:
   - Subscription / Storage account: `caasadlsv2`
   - Blob container (filesystem): `docs`
   - Authentication: **System-assigned managed identity** (the Search service MI already has `Storage Blob Data Reader` granted by Bicep).
4. **Vectorize your text**:
   - Kind: **Azure OpenAI**
   - Subscription + AI Foundry/OpenAI service: `srgsib-foundry`
   - Model deployment: `text-embedding-3-large` (3072 dim)
   - Authentication: **System-assigned managed identity**
   - Acknowledge the billing checkbox.
5. **Vectorize and enrich your images**: leave OFF for RAG (text-only).
6. **Advanced settings**:
   - ✅ Enable **semantic ranker**
   - Schedule: Once (you can re-run later)
7. **Review and create**:
   - **Objects name prefix**: `safety-docs` → this produces index `safety-docs`, indexer `safety-docs-indexer`, data source `safety-docs-datasource`, skillset `safety-docs-skillset`.
   - Click **Create**.
8. After creation, open the index **`safety-docs`** → **Semantic configurations** → confirm one exists and **rename it to `safety-docs-semantic`** (or recreate with that exact name). The agent code looks up that config by name.
9. **Indexers** blade → run `safety-docs-indexer` → wait for *Success* and confirm **Documents processed > 0**.

**B. (Optional, usually skip) Attach the index in Foundry IQ as a Knowledge source**

> ⚠️ **This will fail by design in our setup.** Foundry IQ / Knowledge calls the AI Search REST API from the **public Foundry control plane**, not from your bastion. Since `srgsib-search` has `publicNetworkAccess: Disabled`, you will see:
> *"Error loading knowledge bases — Request is denied as the source is not allowed by applicable rules."*
>
> The Container App does **not** need this attachment — it queries AI Search directly via the private endpoint using `SEARCH_ENDPOINT` + `SEARCH_INDEX=safety-docs`. **Skip step B unless you specifically want to test the index from the Foundry Playground.**

If you really need it (temporary public exposure with IP allowlist):

```bash
# TEMP: open Search to your current public IP only
MYIP=$(curl -s ifconfig.me)
az search service update -g "$RG" -n srgsib-search \
  --public-network-access enabled --ip-rules "$MYIP"

# Then in Foundry portal → project srgsib-prj → Knowledge → + Add knowledge
#   → Azure AI Search → connection srgsib-search → index safety-docs → Save.

# Re-lock immediately after
az search service update -g "$RG" -n srgsib-search --public-network-access disabled
```

---

## 3. Build and push the agent container image

The Bicep currently runs the public `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` placeholder. You need to build the real BFF (`agent/`) and push it to ACR.

### 3a. Create the Dockerfile (one-time)

```bash
cd /Users/alvintai/work/code/CAAS/SafetyRegulation/agent

cat > Dockerfile <<'EOF'
FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates apt-transport-https \
        unixodbc-dev gcc g++ \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
 && echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
        > /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

ENV PORT=7700
EXPOSE 7700
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7700"]
EOF
```

### 3b. Build and push — pick ONE option

> Pre-req: ACR public access must be temporarily enabled (you've already done this):
> ```bash
> az acr update -n "$ACR" --public-network-access Enabled
> ```
> Re-disable it after §3 finishes (see end of this section).

#### Option 1 — `az acr build` (recommended, no Docker needed) ✅

Builds server-side on Azure-managed agents. Works from your Mac VS Code terminal **or the Windows bastion**, no Docker Desktop required, no architecture mismatch, no `az acr login` needed (source is uploaded via the ARM management plane using your `az login` session).

```bash
cd /Users/alvintai/work/code/CAAS/SafetyRegulation/agent
az acr build -r "$ACR" -t "safety-intel-bot:v1" .
```

#### Option 2 — Local Docker build + push

Requires **Docker Desktop running** on your Mac.

```bash
cd /Users/alvintai/work/code/CAAS/SafetyRegulation/agent

az acr login -n "$ACR"

# --platform linux/amd64 is REQUIRED on Apple Silicon (M1/M2/M3/M4).
# Container Apps runs amd64; an arm64 image will fail with "exec format error".
docker buildx build --platform linux/amd64 \
  -t "${ACR_LOGIN}/safety-intel-bot:v1" \
  --push .
```

#### Option 3 — VS Code Docker extension (GUI)

Requires the **Docker** extension (`ms-azuretools.vscode-docker`) and Docker Desktop running.

1. Open `agent/Dockerfile` in VS Code.
2. Right-click the Dockerfile → **Build Image…** → when prompted for the tag, paste:
   `<acrLoginServer>/safety-intel-bot:v1`  (e.g. `srgsibacr1234.azurecr.io/safety-intel-bot:v1` — get it via `echo $ACR_LOGIN`).
3. Open the **Docker** side panel → **Registries** → **Connect Registry…** → **Azure** → sign in → expand your ACR.
4. Under **Images** in the side panel, find the tag you just built → right-click → **Push**.

> ⚠️ The GUI build will produce an **arm64** image on Apple Silicon, which will crash on Container Apps. Prefer **Option 1** for that reason. If you must use Option 3, manually run a one-off `docker buildx build --platform linux/amd64 ...` instead of the right-click build.

### 3c. Re-lock ACR after the push

```bash
az acr update -n "$ACR" --public-network-access Disabled
```

---

## 4. Point the Container App at the new image and the right port

The Container App was created with `targetPort=80` and the hello-world image. **Order matters** — register the ACR pull identity **before** changing the image, otherwise ACA tries to pull anonymously and you get `UNAUTHORIZED: authentication required`.

```bash
# 4a. Tell ACA to authenticate to ACR with the system-assigned MI
#     (AcrPull is already granted in Bicep). DO THIS FIRST.
az containerapp registry set \
  -g "$RG" -n "$APP_NAME" \
  --server "$ACR_LOGIN" --identity system

# 4b. Now swap the image
az containerapp update \
  -g "$RG" -n "$APP_NAME" \
  --image "${ACR_LOGIN}/safety-intel-bot:v1"

# 4c. Open the right port
az containerapp ingress update \
  -g "$RG" -n "$APP_NAME" \
  --target-port 7700 --type external --transport auto
```

Tail logs and confirm `Agent built; tools=['nl2sql', 'doc_search', 'chart_spec']`:

```bash
az containerapp logs show -g "$RG" -n "$APP_NAME" --follow --tail 100
```

Smoke test (note: `APP_FQDN` must be the bare hostname, **without** `https://`):

```bash
# Correct:   APP_FQDN=srgsib-app.delightfulpond-edd2033f.southeastasia.azurecontainerapps.io
# Incorrect: APP_FQDN=https://srgsib-app.delightfulpond-edd2033f.southeastasia.azurecontainerapps.io
curl -sS "https://${APP_FQDN}/healthz"
```

---

## 5. (Optional) Re-bake the Bicep so it stops resetting the image

After the first successful deploy, change `agentContainerImage` in `agent/infra/main.bicepparam` to `"<acrLoginServer>/safety-intel-bot:v1"` and `agentContainerPort` to `7700`, so the next `deploy.sh` doesn't revert to hello-world.

---

## 6. Create the Foundry **v2 PromptAgent** (REQUIRED — `/chat` is 503 until this is done)

The Container App's `agent.py` calls Foundry through the **v2 Responses API** (the OpenAI SDK pointed at `…/agents/<agent_name>/endpoint/protocols/openai`). It does **not** use the deprecated Assistants/Persistent-Agents runtime. The agent is identified by **name** (`FOUNDRY_AGENT_NAME`), not by `asst_xxx`.

### Recommended — From code (reproducible)

The script `agent/scripts/create_foundry_agent.py` registers a v2 **PromptAgent** named `safety-intelligence-bot` with three tools wired in:

- **AzureAISearchTool** → project connection `srgsib-foundry-aisearch-existing`, index `safety-docs`, `query_type=semantic`, `top_k=8` (handled server-side by Foundry).
- **FunctionTool `nl2sql`** → executed locally by `agent.py` against the Synapse views.
- **FunctionTool `chart_spec`** → executed locally by `agent.py` to build a Vega-Lite spec.

Prerequisites (one-time):

```bash
# Your signed-in user must have a data-plane role on the Foundry account
# (Bicep grants this to adminPrincipalObjectId; if that's wrong, do it manually):
ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Azure AI User" \
  --scope "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$FOUNDRY"
```

Run:

```bash
cd agent
python3.12 -m venv .venv && source .venv/bin/activate     # Python 3.10+ required
pip install -r requirements.txt

export AZURE_AI_PROJECT_ENDPOINT="$PROJECT_ENDPOINT"     # from §0
export AZURE_OPENAI_DEPLOYMENT="gpt-5.2"
python scripts/create_foundry_agent.py
```

Expected output:

```
Using search connection: srgsib-foundry-aisearch-existing  (/subscriptions/.../connections/srgsib-foundry-aisearch-existing)
Created agent version:
  agent_name : safety-intelligence-bot
  version    : 1
  id         : safety-intelligence-bot:1

Set this on the Container App:
  FOUNDRY_AGENT_NAME=safety-intelligence-bot
```

Re-running the script publishes a new **version** of the same agent (v2 → v3 → …) and the latest is served by default.

The agent appears in the new Foundry portal under **Agents** (it will *not* show in any "Persistent Agents / Assistants" view — those are the deprecated surface we deliberately do not use).

---

## 7. Wire the Container App to the v2 agent (REQUIRED)

```bash
az containerapp update -g "$RG" -n "$APP_NAME" \
  --set-env-vars "FOUNDRY_AGENT_NAME=safety-intelligence-bot" \
  --remove-env-vars FOUNDRY_AGENT_ID    # drop any leftover from the legacy run
```

After the new revision rolls out, `GET /readyz` returns `{"status":"ready", "agent_name":"safety-intelligence-bot"}` and `POST /chat` works. `agent.py` reads `FOUNDRY_AGENT_NAME` at request time, opens a Responses-API session against `…/agents/<name>/endpoint/protocols/openai`, and dispatches `nl2sql` / `chart_spec` tool calls locally while letting Foundry handle Azure AI Search server-side.

> Per-session conversation continuity is achieved via `previous_response_id` (kept in-memory in `agent.py`'s `_sessions` dict). For multi-replica scale-out, move that map to Cosmos/Redis.

---

## 8. End-to-end smoke test

```bash
# Health
curl -sS "https://${APP_FQDN}/healthz"

# Ask the agent something that triggers nl2sql
curl -N -sS "https://${APP_FQDN}/chat" \
  -H "Content-Type: application/json" \
  -d '{"session_id":"t1","message":"How many CAN findings did Global Airways receive in 2024?"}'
```

You should see SSE chunks with `tool_call` (nl2sql) → `tool_result` → `final` text. In Foundry portal → **Agents** → `safety-intelligence-bot` → **Traces**, the response is also visible (v2 Responses API; conversations are linked via `previous_response_id`).

---

## 9. Quick troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Agent not in Foundry portal | v2 agent never created | Run step 6 (`scripts/create_foundry_agent.py`) |
| Container App shows "hello world" page | Image still placeholder | Step 4 (`az containerapp update --image`) |
| `/chat` returns 500 with `Login failed for user '<token-identified principal>'` | Step 1 not done — MSI is not a Synapse SQL user | Re-run the `CREATE USER ... FROM EXTERNAL PROVIDER` block |
| `doc_search` returns 0 results | Index `safety-docs` not built or empty | Step 2 — re-run indexer |
| `403 PublicNetworkAccess is disabled` from `az acr build` | ACR is private | Use `az acr build` (server-side) — never `docker push` from outside the VNet |
| `RoleAssignmentUpdateNotPermitted` on re-deploy | Stale RA from a recreated MSI | `deploy.sh` already prunes; if it re-occurs, delete the offending RA manually then redeploy |

---

## What's still optional / future work

- Replace the React canvas placeholder dashboards (Org 360, Ops 360, etc.) with the SSE-driven chat + chart pane.
- Add Application Insights custom events from `app.py` for tool-call traces.
- Move from `db_datareader` to per-view `GRANT SELECT` for least privilege.
- Lock down Container Apps ingress with Front Door + WAF if exposed externally.
