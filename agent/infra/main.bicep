// =============================================================================
//  Safety Intelligence Bot - POC infra (Foundry-native)
//
//  Stack:
//    * Microsoft.CognitiveServices/accounts (kind=AIServices) = "Foundry resource"
//        - Hosts ALL Azure OpenAI model deployments (gpt-5.2, embeddings)
//        - Hosts Foundry Agent Service
//    * Microsoft.CognitiveServices/accounts/projects = Foundry project
//        - The endpoint the agent app talks to:
//          https://<foundry>.services.ai.azure.com/api/projects/<project>
//    * Azure AI Search (vector store for RAG)
//    * Azure Container Apps (workload profiles env, VNet-injected) running the agent BFF
//        - Ingress: EXTERNAL (public, HTTPS) - users hit it from the internet
//        - Egress + control plane: through the VNet, so it can reach Foundry / Search /
//          Synapse / ADLS over Private Endpoints with NO API keys
//
//  Security baseline (NON-NEGOTIABLE):
//    * publicNetworkAccess = Disabled on every backend PaaS resource
//    * All backend access via Private Endpoints
//    * Auth = Microsoft Entra ID + Managed Identity ONLY (no keys / SAS / SQL pwd)
//    * Container Apps ingress is the ONLY public surface.
// =============================================================================

targetScope = 'resourceGroup'

// ----------------------------- Parameters ------------------------------------

@description('Short solution name, used as a name prefix.')
param namePrefix string = 'srgsib'

@description('Location for all new resources.')
param location string = resourceGroup().location

@description('Name of EXISTING Synapse workspace in this resource group.')
param existingSynapseWorkspaceName string

@description('Name of EXISTING ADLS Gen2 storage account in this resource group.')
param existingAdlsAccountName string

@description('Address space for the new POC VNet.')
param vnetAddressPrefix string = '10.50.0.0/22'

@description('Subnet prefix for Private Endpoints.')
param peSubnetPrefix string = '10.50.0.0/24'

@description('Subnet prefix for Container Apps Environment (infrastructure + workload). Must be /23 or larger for workload-profile envs.')
param acaSubnetPrefix string = '10.50.2.0/23'

@description('Object ID of an Entra user/group to grant data-plane access for testing.')
param adminPrincipalObjectId string

@description('Set to false to skip creating Private Endpoints on the existing Synapse workspace.')
param deploySynapsePrivateEndpoints bool = true

@description('Chat model deployment name + Azure OpenAI model id/version. Edit if your region uses a different version.')
param chatModelDeploymentName string = 'gpt-5.2'
param chatModelName string = 'gpt-5.2'
param chatModelVersion string = '2025-12-11'
param chatModelSkuName string = 'GlobalStandard'
param chatModelCapacity int = 50

param embedDeploymentName string = 'text-embedding-3-large'
param embedModelName string = 'text-embedding-3-large'
param embedModelVersion string = '1'
param embedSkuName string = 'Standard'
param embedCapacity int = 50

@description('Container image for the agent BFF. Defaults to a public hello-world; replace with your own image (e.g. ACR built via deploy script).')
param agentContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container target port the app listens on.')
param agentContainerPort int = 80

@description('Azure Container Registry name (must be globally unique, 5-50 alphanumeric).')
param acrName string = toLower(replace('${namePrefix}acr${uniqueString(resourceGroup().id)}', '-', ''))

@description('Tag map applied to every resource.')
param tags object = {
  workload: 'safety-intelligence-bot'
  classification: 'official-sensitive'
  env: 'poc'
}

// ----------------------------- Variables -------------------------------------

var foundryName    = '${namePrefix}-foundry'
var foundryPrjName = '${namePrefix}-prj'
var searchName     = '${namePrefix}-search'
var caeName        = '${namePrefix}-cae'
var appName        = '${namePrefix}-app'
var vnetName       = '${namePrefix}-vnet'
var lawName        = '${namePrefix}-law'
var aiName         = '${namePrefix}-appi'

var roleIds = {
  azureAIUser:          '53ca6127-db72-4b80-b1b0-d745d6d5456d' // Azure AI User (Foundry Agent Service caller)
  cogsvcOpenAIUser:     'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services OpenAI User
  cogsvcUser:           'a97b65f3-24c7-4388-baec-2e87135dc908' // alias
  searchIndexDataRdr:   '1407120a-92aa-4202-b7e9-c0e197c71c8f' // Search Index Data Reader
  searchIndexDataCtb:   '8ebe5a00-799e-43f5-93ac-243d3dce84a7' // Search Index Data Contributor (Standard agent setup)
  searchSvcContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // Search Service Contributor
  storageBlobDataRdr:   '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' // Storage Blob Data Reader
  storageBlobDataCtb:   'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
  storageBlobDataOwn:   'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner (Standard agent setup writes files)
  cosmosDbOperator:     '230815da-be43-4aae-9cb4-875f7bd000aa' // Cosmos DB Operator (Standard agent setup needs control plane)
  acrPull:              '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
}

// ----------------------------- Existing refs ---------------------------------

resource existingSynapse 'Microsoft.Synapse/workspaces@2021-06-01' existing = if (deploySynapsePrivateEndpoints) {
  name: existingSynapseWorkspaceName
}

resource existingAdls 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: existingAdlsAccountName
}

// ----------------------------- Networking ------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ vnetAddressPrefix ] }
    subnets: [
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [{
            name: 'acadelegation'
            properties: { serviceName: 'Microsoft.App/environments' }
          }]
        }
      }
    ]
  }
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: 'snet-pe'
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: 'snet-aca'
}

// ----------------------------- Private DNS Zones -----------------------------

var dnsZoneNames = [
  'privatelink.openai.azure.com'             // 0
  'privatelink.cognitiveservices.azure.com'  // 1
  'privatelink.services.ai.azure.com'        // 2 - Foundry project endpoints
  'privatelink.search.windows.net'           // 3
  'privatelink.blob.core.windows.net'        // 4
  'privatelink.dfs.core.windows.net'         // 5
  'privatelink.sql.azuresynapse.net'         // 6
  'privatelink.dev.azuresynapse.net'         // 7
  'privatelink.azurecr.io'                   // 8 - ACR (covers both registry + regional data endpoint)
  'privatelink.documents.azure.com'          // 9 - Cosmos DB (Foundry Agent Service - Standard setup)
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in dnsZoneNames: {
  name: z
  location: 'global'
  tags: tags
}]

resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (z, i) in dnsZoneNames: {
  parent: dnsZones[i]
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}]

var idxAoai      = 0
var idxCog       = 1
var idxAiSvc     = 2
var idxSearch    = 3
var idxBlob      = 4
var idxDfs       = 5
var idxSynSql    = 6
var idxSynDev    = 7
var idxAcr       = 8
var idxCosmos    = 9

// ----------------------------- Observability ---------------------------------

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
    DisableLocalAuth: true
  }
}

// ----------------------------- Azure AI Search -------------------------------

resource search 'Microsoft.Search/searchServices@2024-03-01-preview' = {
  name: searchName
  location: location
  tags: tags
  sku: { name: 'standard' }
  identity: { type: 'SystemAssigned' }
  properties: {
    publicNetworkAccess: 'disabled'
    disableLocalAuth: true
    semanticSearch: 'standard'
  }
}

// ----------------------------- Foundry resource (AIServices) -----------------
// This is THE Azure OpenAI + Foundry Agent Service resource.

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: foundryName
    allowProjectManagement: true   // <-- enables Foundry projects (Agent Service)
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true         // NO API KEYS
    networkAcls: { defaultAction: 'Deny' }
  }
}

// Foundry project (default project that hosts agents/threads/runs)
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundry
  name: foundryPrjName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'Safety Intelligence Bot'
    description: 'CAAS Safety Regulation - inspector audit-prep agent (POC)'
  }
}

// Model deployments live on the Foundry resource.
resource chatModel 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: foundry
  name: chatModelDeploymentName
  sku: { name: chatModelSkuName, capacity: chatModelCapacity }
  properties: {
    model: { format: 'OpenAI', name: chatModelName, version: chatModelVersion }
  }
}

resource embedModel 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: foundry
  name: embedDeploymentName
  sku: { name: embedSkuName, capacity: embedCapacity }
  properties: {
    model: { format: 'OpenAI', name: embedModelName, version: embedModelVersion }
  }
  dependsOn: [ chatModel ] // serialize deployments on the same account
}

// =============================================================================
//  Foundry Agent Service - STANDARD SETUP (BYO thread store + file store)
//  -------------------------------------------------------------------
//  Basic setup (Microsoft-managed) is the default if you do nothing.
//  Standard setup uses customer-owned resources for:
//    * Cosmos DB (NoSQL)  -> agent threads + messages
//    * Storage account    -> agent files + uploaded blobs
//    * Azure AI Search    -> vector store (we reuse the existing 'search' above)
//
//  Wiring requires:
//    1. Three project-scoped CONNECTIONS (one per resource, AAD-auth)
//    2. RBAC: project MI gets data-plane roles on each resource
//    3. capabilityHosts on the ACCOUNT (empty stub) AND on the PROJECT
//       (project capHost references the three connection NAMES)
//
//  All three back-end resources are private (PE only, no keys).
// =============================================================================

var agentStorageName = toLower(substring(replace('${namePrefix}agst${uniqueString(resourceGroup().id, 'agentstorage')}', '-', ''), 0, 24))
var cosmosName       = '${namePrefix}-cosmos-${substring(uniqueString(resourceGroup().id, 'cosmos'), 0, 5)}'

// ---- Dedicated Storage account for agent files (KEYLESS, AAD-only) ----------
resource agentStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: agentStorageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false           // AAD only - no account keys
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// ---- Cosmos DB (NoSQL) for agent thread storage (KEYLESS, AAD-only) --------
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: cosmosName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      { locationName: location, failoverPriority: 0, isZoneRedundant: false }
    ]
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true                 // AAD only - no master keys
    enableAutomaticFailover: false
    capabilities: []
    isVirtualNetworkFilterEnabled: false   // PE-only access
    minimalTlsVersion: 'Tls12'
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

// ---- Private endpoints for the new Standard-setup resources ----------------
module peAgentStorage 'modules/private-endpoint.bicep' = {
  name: 'pe-agent-storage'
  params: {
    name: '${agentStorage.name}-pe-blob'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: agentStorage.id
    groupId: 'blob'
    privateDnsZoneIds: [ dnsZones[idxBlob].id ]
  }
}

module peCosmos 'modules/private-endpoint.bicep' = {
  name: 'pe-cosmos'
  params: {
    name: '${cosmos.name}-pe'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: cosmos.id
    groupId: 'Sql'
    privateDnsZoneIds: [ dnsZones[idxCosmos].id ]
  }
}

// ---- RBAC: PROJECT managed identity gets data-plane roles ------------------
//   (Standard setup requires the project MI - not the account MI - to read/write
//    threads, files and search docs.)

// Project MI -> Storage Blob Data Owner on agent storage (write/read agent files)
resource raProjAgentStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(agentStorage.id, foundryProject.id, roleIds.storageBlobDataOwn)
  scope: agentStorage
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataOwn)
  }
}

// Project MI -> Cosmos DB Operator (control-plane, allows DB/container provisioning)
resource raProjCosmos 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmos.id, foundryProject.id, roleIds.cosmosDbOperator)
  scope: cosmos
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.cosmosDbOperator)
  }
}

// Project MI -> Search Index Data Contributor + Search Service Contributor
resource raProjSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, foundryProject.id, roleIds.searchIndexDataCtb)
  scope: search
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.searchIndexDataCtb)
  }
}

resource raProjSearchSvc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, foundryProject.id, roleIds.searchSvcContributor)
  scope: search
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.searchSvcContributor)
  }
}

// ---- Project-scoped connections (one per BYO resource, all AAD) ------------
resource connSearch 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: '${searchName}-conn'
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${search.name}.search.windows.net'
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: search.id
      location: search.location
    }
  }
}

resource connCosmos 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: '${cosmosName}-conn'
  properties: {
    category: 'CosmosDB'
    target: cosmos.properties.documentEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmos.id
      location: cosmos.location
    }
  }
}

resource connStorage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: '${agentStorageName}-conn'
  properties: {
    category: 'AzureStorageAccount'
    target: agentStorage.properties.primaryEndpoints.blob
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: agentStorage.id
      location: agentStorage.location
    }
  }
}

// ---- capabilityHost on the ACCOUNT (empty stub - required first) -----------
resource accountCapHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = {
  parent: foundry
  name: '${foundryName}-caphost'
  properties: {
    capabilityHostKind: 'Agents'
  }
}

// ---- capabilityHost on the PROJECT (wires the three connections) -----------
//   This is the resource that actually flips the agent service into Standard
//   mode. Once it provisions, all NEW agents created in this project will
//   persist threads in your Cosmos and files in your Storage account.
resource projectCapHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: foundryProject
  name: '${foundryPrjName}-caphost'
  properties: {
    vectorStoreConnections:    [ connSearch.name ]
    storageConnections:        [ connStorage.name ]
    threadStorageConnections:  [ connCosmos.name ]
  }
  dependsOn: [
    accountCapHost
    raProjAgentStorage
    raProjCosmos
    raProjSearchData
    raProjSearchSvc
    peAgentStorage
    peCosmos
  ]
}

// ----------------------------- Azure Container Registry ---------------------
// Premium SKU is required for Private Endpoint + dataEndpointEnabled.
// adminUserEnabled=false  =>  no admin password; pulls happen via Container App MSI + AcrPull.

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: 'Premium' }
  identity: { type: 'SystemAssigned' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    dataEndpointEnabled: true            // required for private pulls
    anonymousPullEnabled: false
    zoneRedundancy: 'Disabled'
    policies: {
      azureADAuthenticationAsArmPolicy: { status: 'enabled' }   // disable username/password ARM tokens
      exportPolicy: { status: 'enabled' }
      quarantinePolicy: { status: 'disabled' }
      retentionPolicy: { days: 7, status: 'enabled' }
      trustPolicy: { type: 'Notary', status: 'disabled' }
    }
  }
}

// ----------------------------- Container Apps --------------------------------
// Workload-profile env, VNet-injected. internal=false  =>  ingress is PUBLIC
// (HTTPS, *.<env>.azurecontainerapps.io) but all egress to backend services
// flows through the VNet, so it reaches Foundry/Search/Synapse/ADLS over
// Private Endpoints with Managed Identity (no keys).

resource cae 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: caeName
  location: location
  tags: tags
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    vnetConfiguration: {
      internal: false                       // public ingress allowed
      infrastructureSubnetId: acaSubnet.id  // VNet-injected for private egress
    }
    appLogsConfiguration: {
      destination: 'azure-monitor'           // keyless; wired via diagnostic setting
    }
    publicNetworkAccess: 'Enabled'           // required for external ingress
    zoneRedundant: false
  }
}

// Forward env logs to Log Analytics (keyless, AAD-controlled)
resource caeDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: cae
  name: 'to-law'
  properties: {
    workspaceId: law.id
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
  }
}

resource app 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: appName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: cae.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: agentContainerPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          { latestRevision: true, weight: 100 }
        ]
      }
      // No 'secrets' and no 'registries' with passwords — image is public or pulled via MI from ACR.
    }
    template: {
      containers: [
        {
          name: 'agent'
          image: agentContainerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            // Foundry project endpoint - the ONLY endpoint the agent code needs
            { name: 'AZURE_AI_PROJECT_ENDPOINT', value: 'https://${foundry.name}.services.ai.azure.com/api/projects/${foundryProject.name}' }
            // Optional direct AOAI endpoint (same resource, useful for embeddings calls)
            { name: 'AZURE_OPENAI_ENDPOINT',     value: 'https://${foundry.name}.openai.azure.com' }
            { name: 'AZURE_OPENAI_DEPLOYMENT',   value: chatModel.name }
            { name: 'AZURE_OPENAI_EMBED_DEPLOYMENT', value: embedModel.name }
            { name: 'AZURE_OPENAI_API_VERSION',  value: '2025-04-01-preview' }
            { name: 'SEARCH_ENDPOINT',           value: 'https://${search.name}.search.windows.net' }
            { name: 'SEARCH_INDEX',              value: 'safety-docs' }
            { name: 'SYNAPSE_SQL_SERVER',        value: '${existingSynapseWorkspaceName}.sql.azuresynapse.net' }
            { name: 'SYNAPSE_SQL_DATABASE',      value: 'SafetyRegulationDM' }
            { name: 'ADLS_ACCOUNT',              value: existingAdls.name }
            { name: 'ADLS_DOCS_FILESYSTEM',      value: 'docs' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appi.properties.ConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// ----------------------------- RBAC (managed-identity only) ------------------

// App MSI -> Foundry resource: Azure AI User (Foundry Agent Service caller)
resource raAppFoundryAI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, app.id, roleIds.azureAIUser)
  scope: foundry
  properties: {
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.azureAIUser)
  }
}

// App MSI -> Foundry resource: Cognitive Services OpenAI User (direct AOAI calls / embeddings)
resource raAppFoundryAOAI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, app.id, roleIds.cogsvcOpenAIUser)
  scope: foundry
  properties: {
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.cogsvcOpenAIUser)
  }
}

// App MSI -> AI Search (read indexes)
resource raAppSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, app.id, roleIds.searchIndexDataRdr)
  scope: search
  properties: {
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.searchIndexDataRdr)
  }
}

// App MSI -> ADLS (read documents)
resource raAppAdls 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingAdls.id, app.id, roleIds.storageBlobDataRdr)
  scope: existingAdls
  properties: {
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataRdr)
  }
}

// AI Search MSI -> ADLS (so the indexer can pull documents)
resource raSearchAdls 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingAdls.id, search.id, roleIds.storageBlobDataRdr)
  scope: existingAdls
  properties: {
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataRdr)
  }
}

// AI Search MSI -> Foundry (so integrated vectorization can call embeddings)
resource raSearchFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, search.id, roleIds.cogsvcOpenAIUser)
  scope: foundry
  properties: {
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.cogsvcOpenAIUser)
  }
}

// Admin/dev -> Azure AI User on Foundry (so you can build/test agents from portal)
resource raAdminFoundryAI 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalObjectId)) {
  name: guid(foundry.id, adminPrincipalObjectId, roleIds.azureAIUser)
  scope: foundry
  properties: {
    principalId: adminPrincipalObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.azureAIUser)
  }
}

resource raAdminFoundryAOAI 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalObjectId)) {
  name: guid(foundry.id, adminPrincipalObjectId, roleIds.cogsvcOpenAIUser)
  scope: foundry
  properties: {
    principalId: adminPrincipalObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.cogsvcOpenAIUser)
  }
}

resource raAdminSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalObjectId)) {
  name: guid(search.id, adminPrincipalObjectId, roleIds.searchSvcContributor)
  scope: search
  properties: {
    principalId: adminPrincipalObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.searchSvcContributor)
  }
}

resource raAdminAdls 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalObjectId)) {
  name: guid(existingAdls.id, adminPrincipalObjectId, roleIds.storageBlobDataCtb)
  scope: existingAdls
  properties: {
    principalId: adminPrincipalObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataCtb)
  }
}

// App MSI -> ACR: AcrPull (so Container App can pull images via MI, no password)
resource raAppAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, app.id, roleIds.acrPull)
  scope: acr
  properties: {
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.acrPull)
  }
}

// ----------------------------- Private Endpoints -----------------------------

// Foundry resource PE (single PE serves AOAI + Cognitive Services + AI Services)
module peFoundry 'modules/private-endpoint.bicep' = {
  name: 'pe-foundry'
  params: {
    name: '${foundry.name}-pe'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: foundry.id
    groupId: 'account'
    privateDnsZoneIds: [
      dnsZones[idxAoai].id
      dnsZones[idxCog].id
      dnsZones[idxAiSvc].id
    ]
  }
}

module peSearch 'modules/private-endpoint.bicep' = {
  name: 'pe-search'
  params: {
    name: '${search.name}-pe'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: search.id
    groupId: 'searchService'
    privateDnsZoneIds: [ dnsZones[idxSearch].id ]
  }
}

module peAcr 'modules/private-endpoint.bicep' = {
  name: 'pe-acr'
  params: {
    name: '${acr.name}-pe'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: acr.id
    groupId: 'registry'
    privateDnsZoneIds: [ dnsZones[idxAcr].id ]
  }
}

module peAdlsBlob 'modules/private-endpoint.bicep' = {
  name: 'pe-adls-blob'
  params: {
    name: '${existingAdls.name}-pe-blob'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: existingAdls.id
    groupId: 'blob'
    privateDnsZoneIds: [ dnsZones[idxBlob].id ]
  }
}

module peAdlsDfs 'modules/private-endpoint.bicep' = {
  name: 'pe-adls-dfs'
  params: {
    name: '${existingAdls.name}-pe-dfs'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: existingAdls.id
    groupId: 'dfs'
    privateDnsZoneIds: [ dnsZones[idxDfs].id ]
  }
}

module peSynSql 'modules/private-endpoint.bicep' = if (deploySynapsePrivateEndpoints) {
  name: 'pe-synapse-sql'
  params: {
    name: '${existingSynapse.name}-pe-sql'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: existingSynapse.id
    groupId: 'Sql'
    privateDnsZoneIds: [ dnsZones[idxSynSql].id ]
  }
}

module peSynDev 'modules/private-endpoint.bicep' = if (deploySynapsePrivateEndpoints) {
  name: 'pe-synapse-dev'
  params: {
    name: '${existingSynapse.name}-pe-dev'
    location: location
    tags: tags
    subnetId: peSubnet.id
    privateLinkServiceId: existingSynapse.id
    groupId: 'Dev'
    privateDnsZoneIds: [ dnsZones[idxSynDev].id ]
  }
}

// ----------------------------- Outputs ---------------------------------------

output containerAppName string = app.name
output containerAppFqdn string = app.properties.configuration.ingress.fqdn
output containerAppPrincipalId string = app.identity.principalId
output containerAppsEnvName string = cae.name
output foundryAccountName string = foundry.name
output foundryProjectName string = foundryProject.name
output foundryProjectEndpoint string = 'https://${foundry.name}.services.ai.azure.com/api/projects/${foundryProject.name}'
output aoaiEndpoint string = 'https://${foundry.name}.openai.azure.com'
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output appInsightsConnectionString string = appi.properties.ConnectionString
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output agentStorageAccountName string = agentStorage.name
output cosmosAccountName string = cosmos.name
output foundrySetupMode string = 'Standard'
