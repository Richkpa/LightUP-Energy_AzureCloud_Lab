// =============================================================================
//  lightup.bicepparam
//  Parameter values for main.bicep – fill in before deploying.
//  Deploy with:  az deployment sub create -f main.bicep -p lightup.bicepparam
// =============================================================================

using './main.bicep'

// ── Required – fill these in ─────────────────────────────────────────────────

param adminUsername = 'Your_User_Name'

// Set via environment variable – never hardcode passwords in source control:
//   $env:ADMIN_PASSWORD = "Your_Secure_Password"
// Then reference it in the deploy.ps1 script (already handled there).
param adminPassword = ''   // Overridden in deploy.ps1

param alertEmailAddress = 'your-email@example.com'

// ── Optional ──────────────────────────────────────────────────────────────────

// Storage account name must be globally unique.
// If deployment fails with "name already taken", add a suffix (e.g. 'lightupstoragelogs2').
param storageAccountName = 'lightupstoragelogs'

// Object ID of your Engineering AAD group.
// Find it with: az ad group show --group "Engineering" --query id -o tsv
// Leave empty ('') to skip RBAC assignment.
param engineeringGroupObjectId = ''
