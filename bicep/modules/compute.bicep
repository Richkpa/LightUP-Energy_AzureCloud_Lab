// =============================================================================
//  modules/compute.bicep
//  Lab 4 – Azure Bastion, VoltBill VMSS, VoltBill DB VM (Windows Server 2022)
//  Deployed to: Grid-Prod-RG
//
//  COST NOTE: Azure Bastion Basic ~$140/mo. Stop or delete between lab sessions
//             to save money.  VMs can be deallocated when not in use (~$0/hr).
// =============================================================================

@description('Azure region.')
param location string

@description('Administrator username for all VMs.')
param adminUsername string

@description('Administrator password for all VMs.')
@secure()
param adminPassword string

@description('Resource ID of AppSubnet (VMSS NICs).')
param appSubnetId string

@description('Resource ID of DBSubnet (DB VM NIC).')
param dbSubnetId string

@description('Resource ID of AzureBastionSubnet.')
param bastionSubnetId string

@description('Resource ID of the LB backend pool (VMSS association).')
param lbBackendPoolId string

@description('VM size for VMSS instances.')
param vmssVmSize string

@description('VM size for the DB VM.')
param dbVmSize string

@description('Initial number of VMSS instances.')
param vmssInstanceCount int

// ── Public IP for Azure Bastion ───────────────────────────────────────────────
// Bastion requires a Standard static public IP – this is the ONLY public IP
// in the environment (all VMs stay private, accessed via Bastion only).

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'LightUP-Bastion-PIP'
  location: location
  tags: { project: 'LightUP-Energy', purpose: 'bastion-only' }
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ── Azure Bastion – Basic SKU (cheapest) ──────────────────────────────────────
// Eliminates RDP/SSH (3389/22) exposure to the public internet.
// Basic SKU supports RDP and SSH tunneling. Upgrade to Standard for
// file copy, shareable links, etc.

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: 'LightUP-Bastion'
  location: location
  tags: { project: 'LightUP-Energy', lab: 'Lab4-Compute' }
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'BastionIpConfig'
        properties: {
          subnet:                 { id: bastionSubnetId }
          publicIPAddress:        { id: bastionPip.id }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// ── VMSS: VoltBill Portal ─────────────────────────────────────────────────────
// Windows Server 2022, no public IP, associated with the LB backend pool.
// Autoscale rule: scale out when CPU > 70%, scale in when CPU < 30%.

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: 'VoltBill-VMSS'
  location: location
  tags: { project: 'LightUP-Energy', app: 'VoltBill-Portal', lab: 'Lab4-Compute' }
  sku: {
    name:     vmssVmSize
    tier:     'Standard'
    capacity: vmssInstanceCount
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer:     'WindowsServer'
          sku:       '2022-datacenter-azure-edition'
          version:   'latest'
        }
        osDisk: {
          createOption:        'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'   // StandardSSD_LRS for better perf
          }
          caching: 'ReadWrite'
        }
      }
      osProfile: {
        computerNamePrefix: 'voltbill'
        adminUsername:      adminUsername
        adminPassword:      adminPassword
        windowsConfiguration: {
          enableAutomaticUpdates: true
          provisionVMAgent:       true
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'VoltBill-NIC-Config'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'VoltBill-IPConfig'
                  properties: {
                    subnet: { id: appSubnetId }
                    // NO publicIPAddressConfiguration – private only
                    loadBalancerBackendAddressPools: [
                      { id: lbBackendPoolId }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// ── Autoscale Settings for VMSS ───────────────────────────────────────────────

resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'VoltBill-Autoscale'
  location: location
  tags: { project: 'LightUP-Energy' }
  properties: {
    enabled:         true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'DefaultProfile'
        capacity: {
          minimum: '1'
          maximum: '5'
          default: string(vmssInstanceCount)
        }
        rules: [
          {
            // Scale OUT when average CPU > 70% for 5 minutes
            metricTrigger: {
              metricName:        'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain:         'PT1M'
              statistic:         'Average'
              timeWindow:        'PT5M'
              timeAggregation:   'Average'
              operator:          'GreaterThan'
              threshold:         70
            }
            scaleAction: {
              direction:  'Increase'
              type:       'ChangeCount'
              value:      '1'
              cooldown:   'PT5M'
            }
          }
          {
            // Scale IN when average CPU < 30% for 10 minutes
            metricTrigger: {
              metricName:        'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain:         'PT1M'
              statistic:         'Average'
              timeWindow:        'PT10M'
              timeAggregation:   'Average'
              operator:          'LessThan'
              threshold:         30
            }
            scaleAction: {
              direction:  'Decrease'
              type:       'ChangeCount'
              value:      '1'
              cooldown:   'PT10M'
            }
          }
        ]
      }
    ]
  }
}

// ── NIC for DB VM ─────────────────────────────────────────────────────────────

resource dbNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'vm-volt-db-nic'
  location: location
  tags: { project: 'LightUP-Energy' }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet:                     { id: dbSubnetId }
          privateIPAllocationMethod:   'Dynamic'
          // NO publicIPAddress – access via Azure Bastion only
        }
      }
    ]
  }
}

// ── DB VM: VoltBill Database (Windows Server 2022) ───────────────────────────

resource dbVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'vm-volt-db'
  location: location
  tags: { project: 'LightUP-Energy', app: 'VoltBill-DB', lab: 'Lab4-Compute' }
  properties: {
    hardwareProfile: {
      vmSize: dbVmSize
    }
    osProfile: {
      computerName:  'vm-volt-db'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent:       true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer:     'WindowsServer'
        sku:       '2022-datacenter-azure-edition'
        version:   'latest'
      }
      osDisk: {
        name:         'vm-volt-db-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        caching: 'ReadWrite'
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: dbNic.id }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true  // Captures serial console for troubleshooting
      }
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output dbVmId      string = dbVm.id
output dbVmName    string = dbVm.name
output vmssId      string = vmss.id
output vmssName    string = vmss.name
output bastionName string = bastion.name
output bastionPip  string = bastionPip.properties.ipAddress
