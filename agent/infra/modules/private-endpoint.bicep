// Reusable Private Endpoint + Private DNS Zone Group module.
param name string
param location string
param tags object = {}
param subnetId string
param privateLinkServiceId string
param groupId string
param privateDnsZoneIds array

resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [{
      name: groupId
      properties: {
        privateLinkServiceId: privateLinkServiceId
        groupIds: [ groupId ]
      }
    }]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, i) in privateDnsZoneIds: {
      name: 'config${i}'
      properties: { privateDnsZoneId: zoneId }
    }]
  }
}

output id string = pe.id
