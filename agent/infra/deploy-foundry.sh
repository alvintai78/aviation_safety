#!/usr/bin/env bash
# =============================================================================
#  Foundry-ONLY deployment - STANDARD setup, full lockdown
#
#  Deploys ONLY Azure AI Foundry and the back-end resources it needs to run the
#  Agent Service in STANDARD mode (Cosmos thread store, Storage file store,
#  AI Search vector store), all behind Private Endpoints, Entra ID + Managed
#  Identity only, with NO API keys / SAS / local auth anywhere.
#
#  Prereqs:
#    - Azure CLI >= 2.60
#    - You are logged in:  az login
#    - The resource group already exists
#    - (Optional) you edited foundry.bicepparam (admin object id / model pins)
# =============================================================================
set -euo pipefail

# ---- Fixed deployment target ------------------------------------------------
SUBSCRIPTION_ID="57bbd325-81fb-4c5f-adee-489263236d32"
RESOURCE_GROUP="CAAS"
LOCATION="southeastasia"
# ------------------------------------------------------------------------------

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOYMENT_NAME="srgsib-foundry-$(date +%Y%m%d-%H%M%S)"

echo ">> Setting subscription"
az account set --subscription "$SUBSCRIPTION_ID"

# -----------------------------------------------------------------------------
# Pre-flight: purge any soft-deleted Foundry account with the same name.
# Cognitive Services accounts are soft-deleted on removal; a stale soft-deleted
# account blocks redeploy under the same name. Purge it if present.
# -----------------------------------------------------------------------------
FOUNDRY_NAME="srgsib-foundry"
echo ">> Checking for a soft-deleted Foundry account ($FOUNDRY_NAME)"
if az cognitiveservices account list-deleted \
      --query "[?name=='$FOUNDRY_NAME'] | [0].name" -o tsv 2>/dev/null | grep -q .; then
  echo "   - found soft-deleted '$FOUNDRY_NAME' -> purging"
  az cognitiveservices account purge \
    --name     "$FOUNDRY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" 2>/dev/null || true
else
  echo "   - none found (clean)"
fi

echo ">> Validating Bicep"
az deployment group validate \
  --resource-group "$RESOURCE_GROUP" \
  --template-file  "$SCRIPT_DIR/foundry.bicep" \
  --parameters     "$SCRIPT_DIR/foundry.bicepparam" \
  --output none

echo ">> What-if (review changes)"
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file  "$SCRIPT_DIR/foundry.bicep" \
  --parameters     "$SCRIPT_DIR/foundry.bicepparam"

read -r -p "Proceed with deployment? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

echo ">> Deploying ($DEPLOYMENT_NAME)"
az deployment group create \
  --name           "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file  "$SCRIPT_DIR/foundry.bicep" \
  --parameters     "$SCRIPT_DIR/foundry.bicepparam" \
  --output table

echo ">> Outputs"
az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name           "$DEPLOYMENT_NAME" \
  --query properties.outputs \
  --output jsonc

cat <<'EOF'

================================================================================
 Foundry deployed in STANDARD mode, fully locked down.
 - publicNetworkAccess = Disabled on Foundry, Search, Cosmos, Storage
 - All access via Private Endpoints
 - Entra ID + Managed Identity only (no API keys)

 NOTE: because every back-end is private, data-plane operations (creating
 agents, building the search index, uploading files) must run from a host with
 line-of-sight to the Private Endpoints (a VM in the same VNet, or via Bastion /
 jumpbox / VPN). The agent's project endpoint is in the deployment outputs above
 (foundryProjectEndpoint).
================================================================================
EOF
