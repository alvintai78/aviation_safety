// =============================================================================
//  Foundry-ONLY deployment - STANDARD setup, full lockdown
//
//  Scope: deploys ONLY Azure AI Foundry (Microsoft.CognitiveServices/accounts,
//  kind=AIServices) and the minimum back-end resources required to run the
//  Foundry Agent Service in STANDARD mode:
//      * Foundry account + project
//      * Chat + embedding model deployments
//      * Azure AI Search   -> agent vector store
//      * Cosmos DB (NoSQL) -> agent thread store
//      * Storage account   -> agent file store
//      * VNet + Private DNS zones + Private Endpoints for ALL of the above
//
//  It does NOT deploy Container Apps, ACR, App Insights, or touch the existing
//  Synapse / ADLS resources.
//
//  Security baseline (NON-NEGOTIABLE - "lockdown"):
//      * publicNetworkAccess = Disabled on EVERY resource
//      * ALL access via Private Endpoints only
//      * Auth = Microsoft Entra ID + Managed Identity ONLY
//      * disableLocalAuth / no account keys / no SAS / no API keys anywhere
// =============================================================================

targetScope = 'resourceGroup'

// ----------------------------- Parameters ------------------------------------

@description('Short solution name, used as a name prefix.')
param namePrefix string = 'srgsib'

@description('Location for all new resources.')
param location string = resourceGroup().location

@description('Set true to CREATE a new VNet + PE subnet (greenfield). Leave false to REUSE an existing VNet/subnet (preserves hub peerings and existing private endpoints).')
param createVnet bool = false

@description('Name of the VNet to use for Private Endpoints. When createVnet=false this must already exist.')
param vnetName string = '${namePrefix}-vnet'

@description('Name of the subnet (inside vnetName) to place Private Endpoints in.')
param peSubnetName string = 'snet-pe'

@description('Address space for the VNet (only used when createVnet=true).')
param vnetAddressPrefix string = '10.50.0.0/22'

@description('Subnet prefix for Private Endpoints (only used when createVnet=true).')
param peSubnetPrefix string = '10.50.0.0/24'

@description('Object ID of an Entra user/group to grant data-plane access for testing (Azure AI User on Foundry). Leave empty to skip.')
param adminPrincipalObjectId string = ''

@description('Chat model deployment name + Azure OpenAI model id/version.')
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

@description('Tag map applied to every resource.')
param tags object = {
  workload: 'safety-intelligence-bot'
  classification: 'official-sensitive'
  env: 'poc'
  component: 'foundry'
}

// ----------------------------- Variables -------------------------------------

var foundryName    = '${namePrefix}-foundry'
var foundryPrjName = '${namePrefix}-prj'
var searchName     = '${namePrefix}-search'

var roleIds = {
  azureAIUser:          '53ca6127-db72-4b80-b1b0-d745d6d5456d' // Azure AI User (Foundry Agent Service caller)
  cogsvcOpenAIUser:     'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services OpenAI User
  searchIndexDataCtb:   '8ebe5a00-799e-43f5-93ac-243d3dce84a7' // Search Index Data Contributor (Standard agent setup)
  searchSvcContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // Search Service Contributor
  storageBlobDataOwn:   'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner (Standard agent setup writes files)
  cosmosDbOperator:     '230815da-be43-4aae-9cb4-875f7bd000aa' // Cosmos DB Operator (Standard agent setup control plane)
}

// ----------------------------- Networking ------------------------------------
// By default we REUSE an existing VNet + PE subnet so we never touch hub
// peerings or the private endpoints of other workloads (Synapse / ADLS).
// Set createVnet=true for a greenfield deployment.

resource vnetNew 'Microsoft.Network/virtualNetworks@2023-11-01' = if (createVnet) {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ vnetAddressPrefix ] }
    subnets: [
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource vnetExisting 'Microsoft.Network/virtualNetworks@2023-11-01' existing = if (!createVnet) {
  name: vnetName
}

// Resolve the IDs without referencing a conditional resource outside its branch.
var vnetId     = createVnet ? vnetNew.id : vnetExisting.id
var peSubnetId = '${vnetId}/subnets/${peSubnetName}'

// ----------------------------- Private DNS Zones -----------------------------

var dnsZoneNames = [
  'privatelink.openai.azure.com'             // 0 - AOAI on the Foundry account
  'privatelink.cognitiveservices.azure.com'  // 1 - Cognitive Services
  'privatelink.services.ai.azure.com'        // 2 - Foundry project endpoints
  'privatelink.search.windows.net'           // 3 - AI Search
  'privatelink.blob.core.windows.net'        // 4 - Agent file store
  'privatelink.documents.azure.com'          // 5 - Cosmos DB thread store
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
    virtualNetwork: { id: vnetId }
  }
}]

var idxAoai   = 0
var idxCog    = 1
var idxAiSvc  = 2
var idxSearch = 3
var idxBlob   = 4
var idxCosmos = 5

// ----------------------------- Azure AI Search -------------------------------
// Agent vector store. Private, keyless.

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
// THE Azure OpenAI + Foundry Agent Service resource. Locked down.

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: foundryName
    allowProjectManagement: true   // enables Foundry projects (Agent Service)
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true         // NO API KEYS
    networkAcls: { defaultAction: 'Deny' }
  }
}

// Foundry project (hosts agents/threads/runs)
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
// =============================================================================

var agentStorageRaw  = toLower(replace('${namePrefix}agst${uniqueString(resourceGroup().id, 'agentstorage')}', '-', ''))
var agentStorageName = length(agentStorageRaw) > 24 ? substring(agentStorageRaw, 0, 24) : agentStorageRaw
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

// ---- Private endpoints for the Standard-setup back-end resources -----------
module peAgentStorage 'modules/private-endpoint.bicep' = {
  name: 'pe-agent-storage'
  params: {
    name: '${agentStorage.name}-pe-blob'
    location: location
    tags: tags
    subnetId: peSubnetId
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
    subnetId: peSubnetId
    privateLinkServiceId: cosmos.id
    groupId: 'Sql'
    privateDnsZoneIds: [ dnsZones[idxCosmos].id ]
  }
}

module peSearch 'modules/private-endpoint.bicep' = {
  name: 'pe-search'
  params: {
    name: '${search.name}-pe'
    location: location
    tags: tags
    subnetId: peSubnetId
    privateLinkServiceId: search.id
    groupId: 'searchService'
    privateDnsZoneIds: [ dnsZones[idxSearch].id ]
  }
}

// Foundry resource PE (single PE serves AOAI + Cognitive Services + AI Services)
module peFoundry 'modules/private-endpoint.bicep' = {
  name: 'pe-foundry'
  params: {
    name: '${foundry.name}-pe'
    location: location
    tags: tags
    subnetId: peSubnetId
    privateLinkServiceId: foundry.id
    groupId: 'account'
    privateDnsZoneIds: [
      dnsZones[idxAoai].id
      dnsZones[idxCog].id
      dnsZones[idxAiSvc].id
    ]
  }
  // Gate the PE behind the model deployments so the account is fully
  // provisioned (Succeeded, not Accepted) before the private endpoint attaches.
  dependsOn: [
    chatModel
    embedModel
  ]
}

// ---- RBAC: PROJECT managed identity gets data-plane roles ------------------

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
//   This is what flips the agent service into STANDARD mode.
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
    peSearch
    peFoundry
  ]
}

// ---- Admin/dev RBAC on Foundry (optional - portal build/test) --------------
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

// ----------------------------- Outputs ---------------------------------------

output foundryAccountName string = foundry.name
output foundryProjectName string = foundryProject.name
output foundryProjectEndpoint string = 'https://${foundry.name}.services.ai.azure.com/api/projects/${foundryProject.name}'
output aoaiEndpoint string = 'https://${foundry.name}.openai.azure.com'
output chatDeploymentName string = chatModel.name
output embedDeploymentName string = embedModel.name
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output agentStorageAccountName string = agentStorage.name
output cosmosAccountName string = cosmos.name
output vnetName string = vnetName
output foundrySetupMode string = 'Standard'
