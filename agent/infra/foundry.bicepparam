using './foundry.bicep'

// ---- Deployment parameters (Foundry-only, Standard mode, lockdown) ----------
param namePrefix             = 'srgsib'
param adminPrincipalObjectId = 'a169b169-6a3e-44d1-8e7d-e4f5cd4b5dd5'
// ------------------------------------------------------------------------------

// Optional overrides
// param location          = 'southeastasia'
// param vnetAddressPrefix = '10.50.0.0/22'
// param peSubnetPrefix    = '10.50.0.0/24'

// Model overrides (uncomment to change pinned versions / capacity)
// param chatModelDeploymentName = 'gpt-5.2'
// param chatModelName           = 'gpt-5.2'
// param chatModelVersion        = '2025-12-11'
// param chatModelSkuName        = 'GlobalStandard'
// param chatModelCapacity       = 50
// param embedDeploymentName     = 'text-embedding-3-large'
// param embedModelName          = 'text-embedding-3-large'
// param embedModelVersion       = '1'
// param embedSkuName            = 'Standard'
// param embedCapacity           = 50
