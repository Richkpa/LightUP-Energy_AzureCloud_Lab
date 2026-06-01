// =============================================================================
//  LightUP Energy – Azure Cloud Lab  |  main.bicep
//  Deploys all 5 labs
//  Scope: subscription  (creates its own Resource Groups)
// =============================================================================

targetScope = 'subscription'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region. Must be East US for LightUP Energy compliance.')
@allowed(['eastus'])
param location string = 'eastus'

@description('Admin username for all VMs.')
param adminUsername string

@description('Admin password for all VMs (min 12 chars, upper/lower/number/symbol).')
@secure()
param adminPassword string

@description('Email address for Azure Monitor CPU alerts.')
param alertEmailAddress string

@description('(Optional) Object ID of the Engineering team AAD group for RBAC. Leave blank to skip.')
param engineeringGroupObjectId string = ''

@description('Storage account name – must be globally unique, 3–24 lowercase chars.')
param storageAccountName string = 'lightupstoragelogs'

@description('VM size for the VoltBill VMSS. Use Standard_B2s to save cost.')
param vmssVmSize string = 'Standard_DC1s_v3'

@description('VM size for the VoltBill DB VM. Use Standard_B2ms for Windows (4 GB RAM min).')
param dbVmSize string = 'Standard_DC1s_v3'

@description('Number of initial VMSS instances')
@minValue(1)
@maxValue(5)
param vmssInstanceCount int = 1

// ── Resource Groups (Lab 1) ───────────────────────────────────────────────────

resource gridProdRG 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'Grid-Prod-RG'
  location: location
  tags: {
    project:     'LightUP-Energy'
    environment: 'Production'
    lab:         'AzureCloudLab'
  }
}

resource billingRG 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'Billing-RG'
  location: location
  tags: {
    project:     'LightUP-Energy'
    environment: 'Production'
    lab:         'AzureCloudLab'
  }
}

// ── Lab 1: RBAC – VM Contributor for Engineering Team on Grid-Prod-RG ────────
// NOTE: Management Groups (LightUP-Root / Production / NonProduction) must be
//       created manually in the portal or via:
//         az account management-group create --name "LightUP-Root"
//       Role assignment below scopes to Grid-Prod-RG automatically.

module rbacEngineering 'modules/rbac.bicep' = if (!empty(engineeringGroupObjectId)) {
  name: 'rbac-engineering'
  scope: gridProdRG
  params: {
    principalId: engineeringGroupObjectId
  }
}

// ── Lab 2: Grid Networking (LightUP-VNet) ────────────────────────────────────

module gridNet 'modules/networking.bicep' = {
  name: 'grid-networking'
  scope: gridProdRG
  params: {
    location: location
  }
}

// ── Lab 2: Billing Networking (Billing-VNet) ──────────────────────────────────

module billingNet 'modules/billing-networking.bicep' = {
  name: 'billing-networking'
  scope: billingRG
  params: {
    location:    location
    gridVnetId:  gridNet.outputs.vnetId
  }
}

// ── Lab 2: VNet Peering – Grid → Billing ─────────────────────────────────────

module gridToBillingPeering 'modules/vnet-peering.bicep' = {
  name: 'grid-to-billing-peering'
  scope: gridProdRG
  params: {
    localVnetName:  'LightUP-VNet'
    peeringName:    'Grid-to-Billing'
    remoteVnetId:   billingNet.outputs.vnetId
  }
}

// ── Lab 3: Storage ────────────────────────────────────────────────────────────

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: gridProdRG
  params: {
    location:           location
    storageAccountName: storageAccountName
  }
}

// ── Lab 4: Compute (VMSS + DB VM + Azure Bastion) ────────────────────────────

module compute 'modules/compute.bicep' = {
  name: 'compute'
  scope: gridProdRG
  params: {
    location:          location
    adminUsername:     adminUsername
    adminPassword:     adminPassword
    appSubnetId:       gridNet.outputs.appSubnetId
    dbSubnetId:        gridNet.outputs.dbSubnetId
    bastionSubnetId:   gridNet.outputs.bastionSubnetId
    lbBackendPoolId:   gridNet.outputs.lbBackendPoolId
    vmssVmSize:        vmssVmSize
    dbVmSize:          dbVmSize
    vmssInstanceCount: vmssInstanceCount
  }
}

// ── Lab 5: Monitoring & Backup ────────────────────────────────────────────────

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: gridProdRG
  params: {
    location:          location
    alertEmailAddress: alertEmailAddress
    dbVmId:            compute.outputs.dbVmId
    dbVmName:          compute.outputs.dbVmName
    vmssId:            compute.outputs.vmssId
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output gridProdRGName    string = gridProdRG.name
output billingRGName     string = billingRG.name
output gridVnetId        string = gridNet.outputs.vnetId
output billingVnetId     string = billingNet.outputs.vnetId
output storageAccount    string = storage.outputs.storageAccountName
output dbVmName          string = compute.outputs.dbVmName
output vmssName          string = compute.outputs.vmssName
output bastionName       string = compute.outputs.bastionName
output logAnalyticsId    string = monitoring.outputs.logAnalyticsId
output recoveryVaultName string = monitoring.outputs.recoveryVaultName
