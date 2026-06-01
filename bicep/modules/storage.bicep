// =============================================================================
//  modules/storage.bicep
//  Lab 3 – Storage account, lifecycle management, and grid-configs file share.
//  Deployed to: Grid-Prod-RG
// =============================================================================

@description('Azure region.')
param location string

@description('Storage account name (globally unique, 3–24 lowercase alphanumeric).')
param storageAccountName string

// ── Storage Account: lightupstoragelogs ───────────────────────────────────────
// Standard LRS is the cheapest tier and fine for a lab.
// In production, use GRS for redundancy.

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: { project: 'LightUP-Energy', lab: 'Lab3-Storage', purpose: 'grid-sensor-telemetry' }
  sku: {
    name: 'Standard_LRS'   // Cost-saving: change to Standard_GRS for production
  }
  kind: 'StorageV2'
  properties: {
    accessTier:              'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion:       'TLS1_2'
    allowBlobPublicAccess:    false  // No anonymous blob access
    networkAcls: {
      defaultAction: 'Allow'       // Change to 'Deny' + add VNet rules for production
      bypass:        'AzureServices'
    }
  }
}

// ── Blob Service (required parent for lifecycle policy) ───────────────────────

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days:    7   // Soft-delete protection for blobs
    }
  }
}

// ── Lifecycle Management: archive blobs older than 30 days ───────────────────
// Implements Lab 3 Task 2 – prevents storage cost overruns on cold log data.

resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  dependsOn: [blobService]
  properties: {
    policy: {
      rules: [
        {
          name:    'archive-sensor-logs-after-30-days'
          enabled: true
          type:    'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              // Optionally scope to a prefix: prefixMatch: ['sensor-telemetry/']
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 7   // Cool after 7 days
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 30  // Archive after 30 days
                }
                delete: {
                  daysAfterModificationGreaterThan: 365 // Delete after 1 year
                }
              }
              snapshot: {
                delete: {
                  daysAfterCreationGreaterThan: 90
                }
              }
            }
          }
        }
      ]
    }
  }
}

// ── Sensor telemetry blob container ───────────────────────────────────────────

resource sensorContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'sensor-telemetry'
  properties: {
    publicAccess: 'None'
  }
}

// ── File Service (required parent for file shares) ────────────────────────────

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days:    7
    }
  }
}

// ── Azure File Share: grid-configs ────────────────────────────────────────────
// Lab 3 Task 3 – mounted to the DB/test VM via a drive letter using the
// storage account key (see deploy.ps1 for mount script).

resource gridConfigsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: 'grid-configs'
  properties: {
    shareQuota:      100    // GB – adjust as needed
    accessTier:      'TransactionOptimized'
    enabledProtocols: 'SMB'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output storageAccountName string = storageAccount.name
output storageAccountId   string = storageAccount.id
output blobEndpoint       string = storageAccount.properties.primaryEndpoints.blob
output fileEndpoint       string = storageAccount.properties.primaryEndpoints.file
output fileShareName      string = gridConfigsShare.name
