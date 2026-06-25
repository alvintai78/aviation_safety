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
- Azure CLI installed and logged in as an identity that has the **`Foundry User`**
  role on the Foundry account (`srgsib-foundry`):
  ```bash
  az login            # or: az login --identity   (if using the host's MI)
  az account set --subscription 57bbd325-81fb-4c5f-adee-489263236d32
  ```
  > **Important — which role?** In this tenant the newer built-in roles
  > (`Azure AI User`, `Azure AI Developer`) are a **stale generation** and do
  > **not** grant the data action the script needs
  > (`Microsoft.CognitiveServices/accounts/AIServices/connections/read`).
  > The role that works here is **`Foundry User`**, whose data actions are
  > `Microsoft.CognitiveServices/*` (covers connection read, agent create, and
  > inference).
  >
  > **Heads-up:** when you run from the Bastion with `az login --identity`, the
  > script authenticates as the **VM's managed identity** (e.g. `vmwin11`), *not*
  > your user. That managed identity is the principal that needs `Foundry User`.
  > Grant it with:
  > ```bash
  > FID=$(az cognitiveservices account show -g CAAS -n srgsib-foundry --query id -o tsv)
  > MI_OBJ_ID=<managed-identity-object-id>   # from the PermissionDenied error, or the VM's identity
  > az role assignment create \
  >   --assignee-object-id "$MI_OBJ_ID" \
  >   --assignee-principal-type ServicePrincipal \
  >   --role "Foundry User" \
  >   --scope "$FID"
  > ```
  > Data-plane RBAC on Cognitive Services is cached — allow **5–10 minutes** for
  > a new assignment to take effect before retrying.
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

> If run into RBAC propagation issues, can run this command to refresh the token
az account get-access-token --resource https://cognitiveservices.azure.com --output none
python agent/scripts/create_foundry_agent.py

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
| `(PermissionDenied) Principal does not have access to API/Operation` on `project.connections.list()` | the running principal lacks the right Foundry data-plane role (in this tenant `Azure AI User` / `Azure AI Developer` do **not** cover `AIServices/connections/read`) | Grant **`Foundry User`** on the `srgsib-foundry` account to the principal in the error. With `az login --identity` that principal is the **VM's managed identity**, not your user. See the role-assignment snippet in [Prerequisites](#0-prerequisites-on-the-bastion-host). |
| Still `PermissionDenied` right after assigning `Foundry User` | data-plane RBAC propagation delay / cached token | Wait **5–10 minutes**, then re-run. If it persists, refresh the token: `az account get-access-token --resource https://cognitiveservices.azure.com --output none` and retry. |
| Error shows a different principal/object id than expected | `DefaultAzureCredential` picked a different identity (e.g. wrong user-assigned MI) | Run `az login --identity`; if the VM has multiple user-assigned identities, assign `Foundry User` to the one in the error, or set the client id so `DefaultAzureCredential` selects it. |
| `No Azure AI Search connection found on this project` | connection missing | It should exist as `srgsib-search-conn` from the Bicep; re-deploy Foundry if absent. |
| ODBC / `pyodbc` build errors during `pip install` | missing system ODBC driver | Only needed for the app's `nl2sql` runtime, not for agent registration — you can install `msodbcsql18` later. |

> **Note:** Agent *creation* succeeds even before the `safety-docs` AI Search
> index is built — but the search tool won't return results at runtime until that
> index exists (Step 12 of the Container App guide).
