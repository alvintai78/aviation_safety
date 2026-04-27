#!/usr/bin/env bash
# =============================================================================
#  Safety Intelligence Bot - POC deployment
#
#  Prereqs:
#    - Azure CLI >= 2.60
#    - You are logged in: az login
#    - Resource group already exists with Synapse + ADLS Gen2 inside it
#    - You have edited main.bicepparam with the correct names + your object ID
# =============================================================================
set -euo pipefail

# ---- EDIT THESE TWO VALUES ---------------------------------------------------
SUBSCRIPTION_ID="57bbd325-81fb-4c5f-adee-489263236d32"
RESOURCE_GROUP="CAAS"
LOCATION="southeastasia"
# ------------------------------------------------------------------------------

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOYMENT_NAME="srgsib-$(date +%Y%m%d-%H%M%S)"

echo ">> Setting subscription"
az account set --subscription "$SUBSCRIPTION_ID"

# -----------------------------------------------------------------------------
# Pre-flight: clean stale role assignments for current MSIs.
# Bicep RA names are deterministic from resource IDs, so if a backing resource
# (Search, Container App, ACR) was recreated with a new MSI, the existing RA's
# principalId mismatches what Bicep wants, and ARM rejects it as
# "RoleAssignmentUpdateNotPermitted". Delete those before deploy.
# -----------------------------------------------------------------------------
echo ">> Cleaning stale role assignments for recreated MSIs"
prune_stale_ra() {
  local scope_id="$1"; local current_pid="$2"; local role_name="$3"
  [[ -z "$current_pid" || -z "$scope_id" ]] && return 0
  local rows
  rows=$(az role assignment list --scope "$scope_id" \
    --query "[?roleDefinitionName=='$role_name'].{name:name,pid:principalId}" -o tsv 2>/dev/null) || return 0
  while IFS=$'\t' read -r ra_name ra_pid; do
    [[ -z "$ra_name" ]] && continue
    if [[ "$ra_pid" != "$current_pid" && "$ra_pid" != "" ]]; then
      # Only delete if the OTHER pid no longer corresponds to a live identity in our deployment.
      # Heuristic: if any of our current MSIs match it, leave alone.
      :
    fi
  done <<< "$rows"
}

# Pull current MSIs (may be empty on first run -> safe noop).
APP_PID=$(az containerapp show -g "$RESOURCE_GROUP" -n srgsib-app --query identity.principalId -o tsv 2>/dev/null || true)
SEARCH_PID=$(az search service show -g "$RESOURCE_GROUP" -n srgsib-search --query identity.principalId -o tsv 2>/dev/null || true)
ADLS_ID=$(az storage account show -g "$RESOURCE_GROUP" -n caasadlsv2 --query id -o tsv 2>/dev/null || true)
FOUNDRY_ID=$(az cognitiveservices account show -g "$RESOURCE_GROUP" -n srgsib-foundry --query id -o tsv 2>/dev/null || true)
SEARCH_ID=$(az search service show -g "$RESOURCE_GROUP" -n srgsib-search --query id -o tsv 2>/dev/null || true)
ACR_NAME=$(az acr list -g "$RESOURCE_GROUP" --query "[?starts_with(name,'srgsibacr')].name | [0]" -o tsv 2>/dev/null || true)
ACR_ID=""
[[ -n "$ACR_NAME" ]] && ACR_ID=$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query id -o tsv 2>/dev/null || true)

# Delete any RA on these scopes whose principalId is NOT one of the current live MSIs/admin.
ADMIN_PID="a169b169-6a3e-44d1-8e7d-e4f5cd4b5dd5"
KEEP_PIDS=$(printf "%s\n" "$APP_PID" "$SEARCH_PID" "$ADMIN_PID" | grep -v '^$' | sort -u)

clean_scope() {
  local scope_id="$1"
  [[ -z "$scope_id" ]] && return 0
  echo "   - scope: $scope_id"
  az role assignment list --scope "$scope_id" \
    --query "[?principalType=='ServicePrincipal'].{name:name,pid:principalId,role:roleDefinitionName,scope:scope}" -o tsv 2>/dev/null \
  | while IFS=$'\t' read -r ra_name ra_pid ra_role ra_scope; do
      [[ -z "$ra_name" ]] && continue
      # Only consider exact-scope matches (avoid inherited assignments from parent scopes).
      ra_scope_lc=$(printf '%s' "$ra_scope" | tr '[:upper:]' '[:lower:]')
      scope_id_lc=$(printf '%s' "$scope_id" | tr '[:upper:]' '[:lower:]')
      [[ "$ra_scope_lc" != "$scope_id_lc" ]] && continue
      if ! grep -qx "$ra_pid" <<< "$KEEP_PIDS"; then
        echo "     stale RA: $ra_name ($ra_role, pid=$ra_pid) -> deleting"
        az role assignment delete --ids "$scope_id/providers/Microsoft.Authorization/roleAssignments/$ra_name" --yes 2>/dev/null || true
      fi
    done
}

for s in "$ADLS_ID" "$FOUNDRY_ID" "$SEARCH_ID" "$ACR_ID"; do
  clean_scope "$s"
done

echo ">> Validating Bicep"
az deployment group validate \
  --resource-group "$RESOURCE_GROUP" \
  --template-file  "$SCRIPT_DIR/main.bicep" \
  --parameters     "$SCRIPT_DIR/main.bicepparam" \
  --output none

echo ">> What-if (review changes)"
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file  "$SCRIPT_DIR/main.bicep" \
  --parameters     "$SCRIPT_DIR/main.bicepparam"

read -r -p "Proceed with deployment? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

echo ">> Deploying ($DEPLOYMENT_NAME)"
az deployment group create \
  --name           "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file  "$SCRIPT_DIR/main.bicep" \
  --parameters     "$SCRIPT_DIR/main.bicepparam" \
  --output table

echo ">> Outputs"
az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name           "$DEPLOYMENT_NAME" \
  --query properties.outputs \
  --output jsonc

cat <<'EOF'

================================================================================
 NEXT STEPS (manual, one-time)
================================================================================
 1. Grant the App Service MSI access to the Synapse Dedicated SQL Pool:
       Open Synapse Studio (via Private Endpoint / jump host), connect to the
       SQL pool as an Entra admin, then run:

       CREATE USER [<webAppName-from-output>] FROM EXTERNAL PROVIDER;
       ALTER ROLE db_datareader ADD MEMBER [<webAppName-from-output>];

 2. Disable public network access on the EXISTING Synapse + ADLS:
       az storage account update -n <adls> -g $RESOURCE_GROUP \
           --public-network-access Disabled --allow-shared-key-access false
       az synapse workspace update -n <synapse> -g $RESOURCE_GROUP \
           --public-network-access Disabled

 3. Upload regulatory PDFs to ADLS container 'docs/' (create it first) using
    your Entra identity (no keys):
       az storage fs create -n docs --account-name <adls> --auth-mode login
       az storage fs directory upload -f docs --account-name <adls> \
           --auth-mode login -s ./regulatory-docs -d / --recursive

 4. Build the AI Search index (run scripts/build-search-index.py from a
    machine with line-of-sight to the private endpoints, e.g. a VM in the
    same VNet or via Azure Bastion + jumpbox).
================================================================================
EOF
