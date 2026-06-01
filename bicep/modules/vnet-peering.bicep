// =============================================================================
//  modules/vnet-peering.bicep
//  Lab 2 – Adds the Grid → Billing peering leg onto LightUP-VNet.
//          Deployed to: Grid-Prod-RG
//          (The reverse Billing → Grid leg lives in billing-networking.bicep)
// =============================================================================

@description('Name of the local VNet to add the peering to.')
param localVnetName string

@description('Friendly peering name.')
param peeringName string

@description('Resource ID of the remote VNet to peer with.')
param remoteVnetId string

// Reference the existing local VNet (already created by networking.bicep)
resource localVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: localVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: localVnet
  name: peeringName
  properties: {
    remoteVirtualNetwork:      { id: remoteVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic:     false
    allowGatewayTransit:       false
    useRemoteGateways:         false
  }
}

output peeringId string = peering.id
