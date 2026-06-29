# Deploy the Safety Intelligence Bot — Step-by-Step (PowerShell)

Manual, command-by-command version of [deploy-app.ps1](deploy-app.ps1). Run each
block in order in **PowerShell 7+** with the Azure CLI logged in (`az login`).
Assumes the infra (resource group, VNet, peering, private DNS, ACR, Container
Apps environment, RBAC) already exists. Only does: build image → create/update
Container App → register Foundry agent.

> Run the **Foundry agent** step (Step 7) from a host with private line-of-sight
> to the Foundry endpoint (e.g. a Bastion jumpbox) — Foundry has public access
> disabled.

---

## 0. Set variables

```powershell
# --- existing backend (CAAS) ---
$SubscriptionId   = "57bbd325-81fb-4c5f-adee-489263236d32"
$BackendRg        = "CAAS"
$FoundryName      = "srgsib-foundry"
$FoundryProject   = "srgsib-prj"
$SearchName       = "srgsib-search"
$AdlsName         = "caasadlsv2"
$SynapseName      = "caassynapse"
$SynapseSqlPool   = "caasedms"

# --- existing app environment ---
$AppRg            = "CAAS-APP"
$CaeName          = "srgsib-app-cae"
$AppName          = "srgsib-app"
$AcrName          = ""              # auto-detected below if empty
$ImageTag         = "v1"
$ImageRepo        = "safety-bot"

# --- model / index config ---
$OpenAiDeployment      = "gpt-5.2"
$OpenAiEmbedDeployment = "text-embedding-3-large"
$OpenAiApiVersion      = "2025-04-01-preview"
$SearchIndex           = "safety-docs"
$AgentName             = "safety-intelligence-bot"
```

---

## 1. Pre-flight: extension, providers, subscription

```powershell
az extension add --name containerapp --upgrade --only-show-errors
az provider register --namespace Microsoft.App --only-show-errors
az provider register --namespace Microsoft.OperationalInsights --only-show-errors
az account set --subscription $SubscriptionId
```

---

## 2. Resolve the ACR

```powershell
if (-not $AcrName) {
    $AcrName = az acr list -g $AppRg --query "[?starts_with(name,'srgsibappacr')].name | [0]" -o tsv
    if (-not $AcrName) { $AcrName = az acr list -g $AppRg --query "[0].name" -o tsv }
}
$AcrLoginServer = az acr show -g $AppRg -n $AcrName --query loginServer -o tsv
$Image = "$AcrLoginServer/$($ImageRepo):$ImageTag"
"ACR   : $AcrName ($AcrLoginServer)"
"Image : $Image"
```

---

## 3. Build & push the image (inside ACR)

Run from the repo root (where the `agent/` folder lives):

```powershell
az acr build -r $AcrName -t "$($ImageRepo):$ImageTag" -f agent/Dockerfile agent
```

> Skip this if you're reusing an existing tag.

---

## 4. Build the env-var list

```powershell
$FoundryProjectEndpoint = "https://$FoundryName.services.ai.azure.com/api/projects/$FoundryProject"

$envVars = @(
  "AZURE_AI_PROJECT_ENDPOINT=$FoundryProjectEndpoint",
  "AZURE_OPENAI_ENDPOINT=https://$FoundryName.openai.azure.com",
  "AZURE_OPENAI_DEPLOYMENT=$OpenAiDeployment",
  "AZURE_OPENAI_EMBED_DEPLOYMENT=$OpenAiEmbedDeployment",
  "AZURE_OPENAI_API_VERSION=$OpenAiApiVersion",
  "SEARCH_ENDPOINT=https://$SearchName.search.windows.net",
  "SEARCH_INDEX=$SearchIndex",
  "SYNAPSE_SQL_SERVER=$SynapseName.sql.azuresynapse.net",
  "SYNAPSE_SQL_DATABASE=$SynapseSqlPool",
  "ADLS_ACCOUNT=$AdlsName",
  "ADLS_DOCS_FILESYSTEM=docs",
  "FOUNDRY_AGENT_NAME=$AgentName"
)
```

---

## 5. Create OR update the Container App

Check if it exists:

```powershell
$appExists = az containerapp list -g $AppRg --query "[?name=='$AppName'].name | [0]" -o tsv
```

**If it does NOT exist — create:**

```powershell
az containerapp create `
  -g $AppRg -n $AppName `
  --environment $CaeName `
  --image $Image `
  --registry-server $AcrLoginServer `
  --registry-identity system `
  --system-assigned `
  --ingress external --target-port 8080 --transport auto `
  --min-replicas 1 --max-replicas 3 `
  --cpu 0.5 --memory 1Gi `
  --env-vars @envVars
```

**If it ALREADY exists — update:**

```powershell
az containerapp update `
  -g $AppRg -n $AppName `
  --image $Image `
  --set-env-vars @envVars
```

---

## 6. Show identity + FQDN

```powershell
$AppMi   = az containerapp show -g $AppRg -n $AppName --query identity.principalId -o tsv
$AppFqdn = az containerapp show -g $AppRg -n $AppName --query properties.configuration.ingress.fqdn -o tsv
"Container App MI : $AppMi"
"Container App FQDN: $AppFqdn"
```

---

## 7. Register the Foundry agent

Run from a host with private line-of-sight to the Foundry endpoint. Pick a
Python interpreter (prefer the repo `.venv`):

```powershell
$env:AZURE_AI_PROJECT_ENDPOINT = $FoundryProjectEndpoint
$env:AZURE_OPENAI_DEPLOYMENT   = $OpenAiDeployment
$env:FOUNDRY_AGENT_NAME        = $AgentName
$env:SEARCH_INDEX              = $SearchIndex

cd C:\Users\alvintai\aviation_safety\agent
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt

cd C:\Users\alvintai\aviation_safety
python agent/scripts/create_foundry_agent.py
```

> Needs Python 3.11+ with `agent/requirements.txt` installed. The script uses
> `DefaultAzureCredential` — on a VM/Bastion jumpbox it picks up the VM managed
> identity (no `az login` needed) if that identity has the **Foundry User** role.

---

## 7b. Mirror of `create_foundry_agent.py` (manual, step-by-step)

If you want to register the agent interactively instead of running the script,
open a Python REPL (`python`) in the repo root and run these blocks in order.
They reproduce exactly what [create_foundry_agent.py](../create_foundry_agent.py) does.

**1. Imports + config**

```python
import os
from pathlib import Path
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AISearchIndexResource, AzureAISearchQueryType, AzureAISearchTool,
    AzureAISearchToolResource, FunctionTool, PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential

ENDPOINT         = os.environ["AZURE_AI_PROJECT_ENDPOINT"]          # https://srgsib-foundry.services.ai.azure.com/api/projects/srgsib-prj
MODEL_DEPLOYMENT = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-5.2")
AGENT_NAME       = os.environ.get("FOUNDRY_AGENT_NAME", "safety-intelligence-bot")
SEARCH_INDEX     = os.environ.get("SEARCH_INDEX", "safety-docs")
assert ENDPOINT.startswith("https://"), "AZURE_AI_PROJECT_ENDPOINT not set"
```

**2. Load instructions (system prompt + NL2SQL examples)**

```python
PROMPTS = Path("agent/prompts")
INSTRUCTIONS = (PROMPTS / "system.md").read_text() + "\n\n---\n" + (PROMPTS / "nl2sql_examples.md").read_text()
```

**3. Connect to the project**

```python
project = AIProjectClient(endpoint=ENDPOINT, credential=DefaultAzureCredential())
```

**4. Find the Azure AI Search connection (by type)**

```python
search_conn = next(
    (c for c in project.connections.list()
     if str(getattr(c, "type", "")).lower().endswith("azure_ai_search")),
    None,
)
assert search_conn, "No Azure AI Search connection on the project — add it in Foundry portal first"
print("Using search connection:", search_conn.name, search_conn.id)
```

**5. Define the 4 tools**

```python
ai_search_tool = AzureAISearchTool(
    azure_ai_search=AzureAISearchToolResource(indexes=[
        AISearchIndexResource(
            project_connection_id=search_conn.id,
            index_name=SEARCH_INDEX,
            query_type=AzureAISearchQueryType.SEMANTIC,
            top_k=8,
        )
    ])
)

nl2sql_tool = FunctionTool(
    name="nl2sql",
    description="Run a single read-only T-SQL SELECT against vw_SafetyIntel_* views in Synapse.",
    parameters={
        "type": "object",
        "properties": {"sql": {"type": "string", "description": "Single T-SQL SELECT, vw_SafetyIntel_* only."}},
        "required": ["sql"], "additionalProperties": False,
    },
    strict=True,
)

chart_tool = FunctionTool(
    name="chart_spec",
    description="Convert nl2sql rows into a Vega-Lite chart spec. Call AFTER nl2sql with the actual rows.",
    parameters={
        "type": "object",
        "properties": {
            "intent": {"type": "string", "enum": ["bar","line","pie","area","scatter","heatmap","table"]},
            "rows": {"type": "array", "items": {"type": "object"}, "minItems": 1},
            "x": {"type": "string"}, "y": {"type": "string"},
            "color": {"type": "string"}, "title": {"type": "string"},
        },
        "required": ["intent", "rows"], "additionalProperties": False,
    },
    strict=False,
)

dashboard_tool = FunctionTool(
    name="dashboard_spec",
    description="Assemble multiple nl2sql result sets into an ops-dashboard artifact.",
    parameters={
        "type": "object",
        "properties": {
            "title": {"type": "string"}, "domain": {"type": "string"}, "focus": {"type": "string"},
            "datasets": {"type": "array", "minItems": 1, "items": {
                "type": "object",
                "properties": {"name": {"type": "string"}, "title": {"type": "string"},
                               "rows": {"type": "array", "items": {"type": "object"}}},
                "required": ["name", "rows"], "additionalProperties": False,
            }},
        },
        "required": ["datasets"], "additionalProperties": False,
    },
    strict=False,
)
```

**6. Create the agent version**

```python
definition = PromptAgentDefinition(
    model=MODEL_DEPLOYMENT,
    instructions=INSTRUCTIONS,
    tools=[ai_search_tool, nl2sql_tool, chart_tool, dashboard_tool],
)

version = project.agents.create_version(
    agent_name=AGENT_NAME,
    definition=definition,
    description="Safety Intelligence Bot — NL2SQL + doc grounding for the CAAS Safety Regulation warehouse.",
)

print("agent_name:", AGENT_NAME)
print("version   :", getattr(version, "version", "?"))
print("id        :", getattr(version, "id", "?"))
print("=> set FOUNDRY_AGENT_NAME=", AGENT_NAME)
```

> The Container App must use the printed `FOUNDRY_AGENT_NAME` (not a legacy
> `asst_xxx` ID). The Search connection must already exist on the project.

---

## Done

- Container App: `$AppName` (`$AppFqdn`)
- Foundry agent: `$AgentName`
