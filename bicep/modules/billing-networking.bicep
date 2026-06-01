// =============================================================================
//  modules/billing-networking.bicep
//  Lab 2 – Billing-VNet with BillingSubnet + BillingAppSubnet
//          Also creates the Billing → Grid peering leg.
//  Deployed to: Billing-RG
// =============================================================================

@description('Azure region.')
param location string

@description('Resource ID of LightUP-VNet in Grid-Prod-RG (for peering).')
param gridVnetId string

// ── NSG: BillingSubnet ────────────────────────────────────────────────────────

resource billingNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'BillingSubnet-NSG'
  location: location
  tags: { project: 'LightUP-Energy', component: 'Billing' }
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority:                 100
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange:     '443'
          description:              'Allow HTTPS to billing tier'
        }
      }
      {
        name: 'Allow-From-GridVNet'
        properties: {
          priority:                 200
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 '*'
          sourceAddressPrefix:      '10.0.0.0/16'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange:     '*'
          description:              'Allow all traffic from Grid VNet (VNet peer)'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          priority:                 4096
          direction:                'Inbound'
          access:                   'Deny'
          protocol:                 '*'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
        }
      }
    ]
  }
}

// ── VNet: Billing-VNet ────────────────────────────────────────────────────────
// Subnets:
//   BillingSubnet    10.1.1.0/24 – VoltBill portal backend
//   BillingAppSubnet 10.1.2.0/24 – Additional app tier

resource billingVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'Billing-VNet'
  location: location
  tags: { project: 'LightUP-Energy', component: 'Billing', lab: 'Lab2-Networking' }
  properties: {
    addressSpace: {
      addressPrefixes: ['10.1.0.0/16']
    }
    subnets: [
      {
        name: 'BillingSubnet'
        properties: {
          addressPrefix:          '10.1.1.0/24'
          networkSecurityGroup: { id: billingNsg.id }
        }
      }
      {
        name: 'BillingAppSubnet'
        properties: {
          addressPrefix: '10.1.2.0/24'
        }
      }
    ]
  }
}

// ── VNet Peering: Billing → Grid (one leg; Grid → Billing is in vnet-peering.bicep) ──

resource billingToGridPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: billingVnet
  name: 'Billing-to-Grid'
  properties: {
    remoteVirtualNetwork:    { id: gridVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic:     false
    allowGatewayTransit:       false
    useRemoteGateways:         false
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output vnetId          string = billingVnet.id
output vnetName        string = billingVnet.name
output billingSubnetId string = billingVnet.properties.subnets[0].id
