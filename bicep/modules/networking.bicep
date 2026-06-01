// =============================================================================
//  modules/networking.bicep
//  Lab 2 – Grid networking: LightUP-VNet, NSGs, Load Balancer, DNS Zone
//  Deployed to: Grid-Prod-RG
// =============================================================================

@description('Azure region.')
param location string

// ── NSG: AppSubnet – allow HTTPS (443) inbound only ──────────────────────────

resource appNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'AppSubnet-NSG'
  location: location
  tags: { project: 'LightUP-Energy' }
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
          description:              'Allow HTTPS traffic to the GridFlow / VoltBill app tier'
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
          description:              'Implicit deny – Zero Trust default'
        }
      }
    ]
  }
}

// ── NSG: DBSubnet – allow SQL from AppSubnet only ─────────────────────────────

resource dbNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'DBSubnet-NSG'
  location: location
  tags: { project: 'LightUP-Energy' }
  properties: {
    securityRules: [
      {
        name: 'Allow-SQL-From-AppSubnet'
        properties: {
          priority:                 100
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      '10.0.1.0/24'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange:     '1433'
          description:              'Allow SQL Server traffic from AppSubnet only'
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
          description:              'Implicit deny – Zero Trust default'
        }
      }
    ]
  }
}

// ── VNet: LightUP-VNet ────────────────────────────────────────────────────────
// Subnets:
//   AppSubnet          10.0.1.0/24  – VMSS / GridFlow / VoltBill
//   DBSubnet           10.0.2.0/24  – VoltBill DB VM
//   AzureBastionSubnet 10.0.3.0/26

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'LightUP-VNet'
  location: location
  tags: { project: 'LightUP-Energy', lab: 'Lab2-Networking' }
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'AppSubnet'
        properties: {
          addressPrefix:          '10.0.1.0/24'
          networkSecurityGroup: { id: appNsg.id }
        }
      }
      {
        name: 'DBSubnet'
        properties: {
          addressPrefix:          '10.0.2.0/24'
          networkSecurityGroup: { id: dbNsg.id }
        }
      }
      {
        // Azure Bastion subnet – name is fixed by the platform
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.3.0/26'
          // No NSG here; Bastion manages its own security
        }
      }
    ]
  }
}

// ── Public IP for Load Balancer ───────────────────────────────────────────────

resource lbPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'LightUP-LB-PIP'
  location: location
  tags: { project: 'LightUP-Energy' }
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'lightup-lb-${uniqueString(resourceGroup().id)}'
    }
  }
}

// ── Load Balancer – distributes traffic across VMSS ──────────────────────────

resource lb 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: 'LightUP-LB'
  location: location
  tags: { project: 'LightUP-Energy', lab: 'Lab2-Networking' }
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LightUP-Frontend'
        properties: {
          publicIPAddress: { id: lbPip.id }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'VoltBill-BackendPool'
      }
    ]
    probes: [
      {
        name: 'HTTPS-Probe'
        properties: {
          protocol:          'Tcp'
          port:              443
          intervalInSeconds: 15
          numberOfProbes:    2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'HTTPS-Rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'LightUP-LB', 'LightUP-Frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'LightUP-LB', 'VoltBill-BackendPool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'LightUP-LB', 'HTTPS-Probe')
          }
          protocol:             'Tcp'
          frontendPort:         443
          backendPort:          443
          enableFloatingIP:     false
          idleTimeoutInMinutes: 4
          loadDistribution:     'Default'
        }
      }
    ]
  }
}

// ── Azure DNS Zone: lightupenergy.com ────────────────────────────────────────

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: 'lightupenergy.com'
  location: 'global'
  tags: { project: 'LightUP-Energy', lab: 'Lab2-DNS' }
}

resource dnsARecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: dnsZone
  name: 'www'
  properties: {
    TTL: 3600
    ARecords: [
      {
        // Points to the LB public IP; update if IP changes
        ipv4Address: lbPip.properties.ipAddress
      }
    ]
  }
}

// ── Outputs (consumed by main.bicep → compute module) ────────────────────────

output vnetId          string = vnet.id
output vnetName        string = vnet.name
output appSubnetId     string = vnet.properties.subnets[0].id
output dbSubnetId      string = vnet.properties.subnets[1].id
output bastionSubnetId string = vnet.properties.subnets[2].id
output lbBackendPoolId string = lb.properties.backendAddressPools[0].id
output lbPublicIp      string = lbPip.properties.ipAddress
