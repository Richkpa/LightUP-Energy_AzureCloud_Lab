// =============================================================================
//  modules/monitoring.bicep
//  Lab 5 – Log Analytics workspace, Recovery Services Vault + VM backup,
//           Azure Monitor CPU alert, and Action Group (email notification).
//  Deployed to: Grid-Prod-RG
// =============================================================================

@description('Azure region.')
param location string

@description('Email address to receive Azure Monitor alerts.')
param alertEmailAddress string

@description('Resource ID of the VoltBill DB VM (for backup enrollment).')
param dbVmId string

@description('Name of the VoltBill DB VM.')
param dbVmName string

@description('Resource ID of the VoltBill VMSS (for CPU alert scope).')
param vmssId string

// ── Log Analytics Workspace ───────────────────────────────────────────────────
// Lab 5 Task 3 – used for KQL queries (e.g., failed login attempts).

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'LightUP-LogAnalytics'
  location: location
  tags: { project: 'LightUP-Energy', lab: 'Lab5-Monitoring' }
  properties: {
    sku: {
      name: 'PerGB2018'   // Pay-as-you-go – cheapest for a lab
    }
    retentionInDays:              30    // Minimum; increase for compliance
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery:     'Enabled'
  }
}

// ── Action Group: Email Notification ─────────────────────────────────────────
// Receives alerts triggered by Monitor rules below.

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'LightUP-AlertGroup'
  location: 'global'
  tags: { project: 'LightUP-Energy' }
  properties: {
    groupShortName: 'LightUPAlrt'
    enabled:        true
    emailReceivers: [
      {
        name:                 'Admin-Email'
        emailAddress:         alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── Monitor Alert: GridFlow VMSS CPU > 80% for 5 minutes ─────────────────────
// Lab 5 Task 2

resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'GridFlow-HighCPU-Alert'
  location: 'global'
  tags: { project: 'LightUP-Energy', lab: 'Lab5-Monitoring' }
  properties: {
    description: 'Alert when GridFlow VMSS CPU exceeds 80% for 5 minutes – potential grid monitoring failure.'
    severity:             2     // Warning
    enabled:              true
    scopes:               [vmssId]
    evaluationFrequency:  'PT1M'   // Check every 1 minute
    windowSize:           'PT5M'   // Over a 5-minute window
    targetResourceType:   'Microsoft.Compute/virtualMachineScaleSets'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name:            'HighCPUCriteria'
          metricName:      'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
          operator:        'GreaterThan'
          threshold:       80
          timeAggregation: 'Average'
          criterionType:   'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// ── Recovery Services Vault ───────────────────────────────────────────────────
// Lab 5 Task 1 – backs up the VoltBill DB VM.
// Soft Delete is enabled by default – protects against ransomware/accidental deletion.

resource recoveryVault 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: 'LightUP-RecoveryVault'
  location: location
  tags: { project: 'LightUP-Energy', lab: 'Lab5-Backup' }
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// Enable soft delete on the vault (protects backup data for 14 days after deletion)
resource vaultSecurity 'Microsoft.RecoveryServices/vaults/backupconfig@2023-06-01' = {
  parent: recoveryVault
  name: 'vaultconfig'
  properties: {
    enhancedSecurityState: 'Enabled'
    softDeleteFeatureState: 'Enabled'
  }
}

// ── Backup Policy: Daily at 2 AM, retain 30 days ─────────────────────────────

resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-06-01' = {
  parent: recoveryVault
  name: 'VoltBill-DB-DailyBackup'
  properties: {
    backupManagementType: 'AzureIaasVM'
    instantRpRetentionRangeInDays: 2
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: ['2023-01-01T02:00:00Z']   // 2:00 AM UTC daily
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: ['2023-01-01T02:00:00Z']
        retentionDuration: {
          count:        30
          durationType: 'Days'
        }
      }
    }
    instantRPDetails: {}
  }
}

// ── Backup Protection: Enroll DB VM ──────────────────────────────────────────
// The container/item names follow Azure's IaasVM naming convention.
// Format: IaasVMContainer;iaasvmcontainerv2;{resourceGroupName};{vmName}

var rgName            = resourceGroup().name
var containerName     = 'IaasVMContainer;iaasvmcontainerv2;${rgName};${dbVmName}'
var protectedItemName = 'VM;iaasvmcontainerv2;${rgName};${dbVmName}'

resource backupProtection 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-06-01' = {
  name: '${recoveryVault.name}/Azure/${containerName}/${protectedItemName}'
  location: location
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId:          backupPolicy.id
    sourceResourceId:  dbVmId
  }
}

// ── Diagnostic Settings: Stream VM logs to Log Analytics ─────────────────────
// Sends activity logs to the workspace so KQL queries (Lab 5 Task 3) work.

resource activityLogDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'LightUP-ActivityLogs'
  scope: recoveryVault
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'AzureBackupReport'
        enabled:  true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled:  true
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output logAnalyticsId        string = logAnalytics.id
output logAnalyticsWorkspaceId string = logAnalytics.properties.customerId
output recoveryVaultName     string = recoveryVault.name
output recoveryVaultId       string = recoveryVault.id
output actionGroupId         string = actionGroup.id
