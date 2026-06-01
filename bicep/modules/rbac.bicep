// =============================================================================
//  modules/rbac.bicep
//  Lab 1 – Assigns "Virtual Machine Contributor" to the Engineering AAD group
//  scoped to Grid-Prod-RG (called only when engineeringGroupObjectId is set).
// =============================================================================

@description('Object ID of the Engineering team AAD group.')
param principalId string

// Built-in role: Virtual Machine Contributor
// https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

resource vmContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Deterministic GUID based on scope + group + role so re-runs are idempotent
  name: guid(resourceGroup().id, principalId, vmContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId:      principalId
    principalType:    'Group'
    description:      'LightUP Energy – Engineering team VM management on Grid-Prod-RG'
  }
}
