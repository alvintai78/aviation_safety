using './main.bicep'

// ---- EDIT THESE FOUR VALUES BEFORE DEPLOYMENT --------------------------------
param namePrefix                  = 'srgsib'
param existingSynapseWorkspaceName = 'caassynapse'
param existingAdlsAccountName      = 'caasadlsv2'
param adminPrincipalObjectId       = 'a169b169-6a3e-44d1-8e7d-e4f5cd4b5dd5'
// ------------------------------------------------------------------------------

// Optional overrides
// param location          = 'southeastasia'
// param vnetAddressPrefix = '10.50.0.0/22'
// param peSubnetPrefix    = '10.50.0.0/24'
// param appSubnetPrefix   = '10.50.1.0/24'
