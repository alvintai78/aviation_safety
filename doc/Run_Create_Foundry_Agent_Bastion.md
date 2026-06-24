# Run `create_foundry_agent.py` from the Bastion Host

This registers the **Safety Intelligence Bot** as a Foundry v2 `PromptAgent`
on the locked-down `srgsib-foundry` project.

> **Why the Bastion host?** Foundry has `publicNetworkAccess = Disabled`. The
> script makes a **data-plane** call to `srgsib-foundry.services.ai.azure.com`,
> which only resolves/answers from inside the private network. Your laptop on
> the public internet would get a DNS/403 failure. The Bastion host (inside, or
> peered to, `srgsib-vnet`) has the required line-of-sight.

---

## What the script does

- Reads `AZURE_AI_PROJECT_ENDPOINT` (and a few optional vars) from
  `agent/.env.foundry` / `agent/.env` or the process environment.
- Authenticates with `DefaultAzureCredential` (your `az login` / the host's
  managed identity — **no keys**).
- Finds the project's **Azure AI Search connection** (`srgsib-search-conn`,
  already created by the Bicep).
- Registers a v2 PromptAgent named `safety-intelligence-bot` on `gpt-5.2`, wired
  with the AI Search tool plus the `nl2sql`, `chart_spec`, `dashboard_spec`
  function tools.

---

## 0. Prerequisites on the Bastion host

- The host can resolve `srgsib-foundry.services.ai.azure.com` to a
  `privatelink` (10.x) address:
  ```bash
  nslookup srgsib-foundry.services.ai.azure.com
  # expect a 10.x.x.x answer, NOT a public IP
  ```
- Azure CLI installed and logged in as an identity that has **Azure AI Developer**
  (or higher) on the Foundry project:
  ```bash
  az login            # or: az login --identity   (if using the host's MI)
  az account set --subscription 57bbd325-81fb-4c5f-adee-489263236d32
  ```
- Python 3.11+ and `git` available.

---

## 1. Get the code onto the host

If the repo isn't already there, clone or copy it, then `cd` into it:

```bash
cd ~
git clone <your-repo-url> SafetyRegulation     # or scp/rsync the folder
cd SafetyRegulation
```

---

## 2. Create the virtual environment and install dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r agent/requirements.txt
```

---

## 3. Set the Foundry endpoint

Create `agent/.env.foundry` with the project endpoint (and optional overrides):

```bash
cat > agent/.env.foundry <<'EOF'
AZURE_AI_PROJECT_ENDPOINT=https://srgsib-foundry.services.ai.azure.com/api/projects/srgsib-prj
AZURE_OPENAI_DEPLOYMENT=gpt-5.2
FOUNDRY_AGENT_NAME=safety-intelligence-bot
SEARCH_INDEX=safety-docs
EOF
```

> **Alternative (auto-fetch from the deployment):**
> ```bash
> FOUNDRY_DEPLOYMENT_NAME=srgsib-foundry-20260624-190856 \
>   ./agent/scripts/load_foundry_env.sh
> ```
> This queries the ARM deployment output and writes `agent/.env.foundry` for you.
> (Pass the real deployment name — the script's built-in default is stale.)

---

## 4. Run the registration script

```bash
source .venv/bin/activate        # if not already active
python agent/scripts/create_foundry_agent.py
```

> Run it with the explicit `python ...` form. The script's shebang points at a
> non-existent `agent/.venv`; activating the repo-root `.venv` and calling
> `python` avoids that.

On success it prints something like:

```
Created agent version:
  agent_name : safety-intelligence-bot
  version    : 1
  id         : asst_...
Set this on the Container App:
  FOUNDRY_AGENT_NAME=safety-intelligence-bot
```

---

## 5. Verify

```bash
az login   # already done
# List agents on the project (data-plane; run from the Bastion host too)
python - <<'PY'
import os
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
ep = "https://srgsib-foundry.services.ai.azure.com/api/projects/srgsib-prj"
c = AIProjectClient(endpoint=ep, credential=DefaultAzureCredential())
for a in c.agents.list_versions(agent_name="safety-intelligence-bot"):
    print(a.name, getattr(a, "version", "?"), getattr(a, "id", "?"))
PY
```

You can also confirm it in the **Azure AI Foundry portal → srgsib-prj → Agents**.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `AZURE_AI_PROJECT_ENDPOINT is missing or not https` | env not set | Recheck Step 3 (`agent/.env.foundry`). |
| DNS resolves to a public IP / connection timeout | host has no private line-of-sight | Confirm the Bastion host is in (or peered to) `srgsib-vnet` and the `privatelink.services.ai.azure.com` zone is linked. |
| `403` / `AuthorizationFailed` on the data-plane call | identity lacks role | Grant **Azure AI Developer** on the Foundry project to your `az login` identity. |
| `No Azure AI Search connection found on this project` | connection missing | It should exist as `srgsib-search-conn` from the Bicep; re-deploy Foundry if absent. |
| ODBC / `pyodbc` build errors during `pip install` | missing system ODBC driver | Only needed for the app's `nl2sql` runtime, not for agent registration — you can install `msodbcsql18` later. |

> **Note:** Agent *creation* succeeds even before the `safety-docs` AI Search
> index is built — but the search tool won't return results at runtime until that
> index exists (Step 12 of the Container App guide).
