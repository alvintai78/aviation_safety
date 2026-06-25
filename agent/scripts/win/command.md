Install libraries in Windows

# from the repo root
Remove-Item -Recurse -Force .venv
py -m venv .venv                       # or: py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r agent\requirements.txt

py -0p            # lists all installed versions + paths
python --version  # what's first on PATH
py -3.13 --version

az extension add --name containerapp --upgrade

# === 0. Variables ===
$SUB        = "57bbd325-81fb-4c5f-adee-489263236d32"
$BACKEND_RG = "CAAS"
$APP_RG     = "CAAS-APP"
$APP_NAME   = "srgsib-app"

az account set --subscription $SUB

# === 1. Delete the current Container App ===
az containerapp delete -g $APP_RG -n $APP_NAME --yes

# === 2. Redeploy with the script (creates app + registers agent) ===
pwsh .\agent\scripts\win\deploy-app.ps1

# === 3. Capture the NEW managed identity + resource IDs ===
$APP_MI     = az containerapp show -g $APP_RG -n $APP_NAME --query identity.principalId -o tsv
$FOUNDRY_ID = az cognitiveservices account show -g $BACKEND_RG -n srgsib-foundry --query id -o tsv
$SEARCH_ID  = az search service show -g $BACKEND_RG -n srgsib-search --query id -o tsv
$ADLS_ID    = az storage account show -g $BACKEND_RG -n caasadlsv2 --query id -o tsv
$ACR_NAME   = az acr list -g $APP_RG --query "[0].name" -o tsv
$ACR_ID     = az acr show -g $APP_RG -n $ACR_NAME --query id -o tsv

Write-Host "New Container App MI: $APP_MI"

# === 4. Re-grant RBAC to the NEW identity ===
az role assignment create --assignee-object-id $APP_MI --assignee-principal-type ServicePrincipal --role "Foundry User" --scope $FOUNDRY_ID
az role assignment create --assignee-object-id $APP_MI --assignee-principal-type ServicePrincipal --role "Cognitive Services OpenAI User" --scope $FOUNDRY_ID
az role assignment create --assignee-object-id $APP_MI --assignee-principal-type ServicePrincipal --role "Search Index Data Reader" --scope $SEARCH_ID
az role assignment create --assignee-object-id $APP_MI --assignee-principal-type ServicePrincipal --role "Storage Blob Data Reader" --scope $ADLS_ID
az role assignment create --assignee-object-id $APP_MI --assignee-principal-type ServicePrincipal --role "AcrPull" --scope $ACR_ID

# Step 5 — Recreate the Synapse SQL user. This is T-SQL, not PowerShell. Run it against the dedicated SQL pool as an Entra admin. The PowerShell way is to invoke sqlcmd with Entra auth (needs private line-of-sight to the Synapse endpoint):

$query = @"
DROP USER IF EXISTS [srgsib-app];
CREATE USER [srgsib-app] FROM EXTERNAL PROVIDER;
EXEC sp_addrolemember 'db_datareader', 'srgsib-app';
"@

sqlcmd -S "caassynapse.sql.azuresynapse.net" -d "caasedms" -G -Q $query


## Step 6 — Verify the app is healthy.

$APP_FQDN = az containerapp show -g $APP_RG -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv
Write-Host "App FQDN: $APP_FQDN"
az containerapp logs show -g $APP_RG -n $APP_NAME --tail 50