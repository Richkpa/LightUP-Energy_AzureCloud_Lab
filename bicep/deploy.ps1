# =============================================================================
#  deploy.ps1 – LightUP Energy Azure Cloud Lab
#  Deploys the full lab environment from a single command.
#
#  Prerequisites:
#    - Azure CLI installed  (https://aka.ms/installazurecli)
#    - Bicep CLI installed: az bicep install
#    - Run: az login
#    - Update the variables in the CONFIG section below
# =============================================================================

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── CONFIG – edit these before running ───────────────────────────────────────

$SUBSCRIPTION_ID       = "SUBSCRIPTION_ID"        # az account show --query id
$LOCATION              = "eastus"
$DEPLOYMENT_NAME       = "lightup-energy-$(Get-Date -Format 'yyyyMMdd-HHmm')"
$ADMIN_USERNAME        = "Your_User_name"
$ALERT_EMAIL           = "Your_Email_Address"
$STORAGE_ACCOUNT_NAME  = "lightupstoragelogs"          # Must be globally unique
$ENGINEERING_GROUP_OID = ""                             # Optional: AAD group object ID
$VMSS_SIZE             = "Standard_DC1s_v3"
$DB_VM_SIZE            = "Standard_DC1s_v3"
$VMSS_INSTANCE_COUNT   = 1

# ── Prompt for password securely (never store in scripts) ────────────────────

$securePassword = Read-Host "Enter VM admin password" -AsSecureString
$adminPassword  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))

# ── Validate password complexity ─────────────────────────────────────────────

if ($adminPassword.Length -lt 12) {
    Write-Error "Password must be at least 12 characters."
    exit 1
}

# ── Set active subscription ───────────────────────────────────────────────────

Write-Host "`n[1/5] Setting subscription to $SUBSCRIPTION_ID..." -ForegroundColor Cyan
az account set --subscription $SUBSCRIPTION_ID
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set subscription."; exit 1 }

# ── Register required providers (safe to re-run) ─────────────────────────────

Write-Host "`n[2/5] Registering Azure resource providers..." -ForegroundColor Cyan
$providers = @(
    "Microsoft.Compute",
    "Microsoft.Network",
    "Microsoft.Storage",
    "Microsoft.RecoveryServices",
    "Microsoft.OperationalInsights",
    "Microsoft.Insights",
    "Microsoft.Authorization"
)
foreach ($p in $providers) {
    az provider register --namespace $p --wait | Out-Null
    Write-Host "  ✓ $p"
}

# ── Lint and validate the Bicep template ─────────────────────────────────────

Write-Host "`n[3/5] Validating Bicep template..." -ForegroundColor Cyan
az bicep build --file main.bicep
if ($LASTEXITCODE -ne 0) { Write-Error "Bicep build failed. Fix errors above."; exit 1 }

az deployment sub validate `
    --location          $LOCATION `
    --template-file     main.bicep `
    --parameters        location=$LOCATION `
                        adminUsername=$ADMIN_USERNAME `
                        adminPassword=$adminPassword `
                        alertEmailAddress=$ALERT_EMAIL `
                        storageAccountName=$STORAGE_ACCOUNT_NAME `
                        vmssVmSize=$VMSS_SIZE `
                        dbVmSize=$DB_VM_SIZE `
                        vmssInstanceCount=$VMSS_INSTANCE_COUNT `
                        engineeringGroupObjectId=$ENGINEERING_GROUP_OID

if ($LASTEXITCODE -ne 0) { Write-Error "Validation failed. Fix errors above."; exit 1 }
Write-Host "  ✓ Template is valid"

# ── What-if preview ───────────────────────────────────────────────────────────

Write-Host "`n[4/5] Running what-if (preview of changes)..." -ForegroundColor Cyan
az deployment sub what-if `
    --location          $LOCATION `
    --template-file     main.bicep `
    --parameters        location=$LOCATION `
                        adminUsername=$ADMIN_USERNAME `
                        adminPassword=$adminPassword `
                        alertEmailAddress=$ALERT_EMAIL `
                        storageAccountName=$STORAGE_ACCOUNT_NAME `
                        vmssVmSize=$VMSS_SIZE `
                        dbVmSize=$DB_VM_SIZE `
                        vmssInstanceCount=$VMSS_INSTANCE_COUNT `
                        engineeringGroupObjectId=$ENGINEERING_GROUP_OID

# ── Confirm before deploying ──────────────────────────────────────────────────

Write-Host ""
$confirm = Read-Host "Proceed with deployment? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
}

# ── Deploy ────────────────────────────────────────────────────────────────────

Write-Host "`n[5/5] Deploying LightUP Energy lab environment..." -ForegroundColor Green
$startTime = Get-Date

az deployment sub create `
    --name              $DEPLOYMENT_NAME `
    --location          $LOCATION `
    --template-file     main.bicep `
    --parameters        location=$LOCATION `
                        adminUsername=$ADMIN_USERNAME `
                        adminPassword=$adminPassword `
                        alertEmailAddress=$ALERT_EMAIL `
                        storageAccountName=$STORAGE_ACCOUNT_NAME `
                        vmssVmSize=$VMSS_SIZE `
                        dbVmSize=$DB_VM_SIZE `
                        vmssInstanceCount=$VMSS_INSTANCE_COUNT `
                        engineeringGroupObjectId=$ENGINEERING_GROUP_OID `
    --output            table

if ($LASTEXITCODE -ne 0) { Write-Error "Deployment failed. Check the Azure portal for details."; exit 1 }

$elapsed = (Get-Date) - $startTime
Write-Host "`n Deployment complete in $([math]::Round($elapsed.TotalMinutes, 1)) minutes!" -ForegroundColor Green

# ── Post-deployment: Mount the grid-configs file share ───────────────────────

Write-Host "`n To mount the grid-configs file share on a VM:" -ForegroundColor Yellow
Write-Host @"

  # Run this inside the VM (via Bastion) after deployment:
  `$accountKey = (az storage account keys list ``
      --account-name $STORAGE_ACCOUNT_NAME ``
      --query '[0].value' -o tsv)

  net use Z: \\$STORAGE_ACCOUNT_NAME.file.core.windows.net\grid-configs ``
      /user:Azure\$STORAGE_ACCOUNT_NAME `$accountKey /persistent:yes

"@

# ── Post-deployment: KQL query for failed logins (Lab 5 Task 3) ──────────────

Write-Host " KQL query for failed login attempts (Log Analytics):" -ForegroundColor Yellow
Write-Host @"

  SecurityEvent
  | where EventID == 4625                        // Failed logon
  | where TimeGenerated > ago(24h)
  | summarize FailedAttempts = count() by
      Account, Computer, IpAddress,
      bin(TimeGenerated, 1h)
  | where FailedAttempts > 5
  | order by FailedAttempts desc

"@

# ── Outputs ───────────────────────────────────────────────────────────────────

Write-Host " Deployment outputs:" -ForegroundColor Cyan
az deployment sub show `
    --name   $DEPLOYMENT_NAME `
    --query  "properties.outputs" `
    --output table

Write-Host "`n COST TIP: Deallocate VMs and delete Azure Bastion when not in use." -ForegroundColor Magenta
Write-Host "   az vm deallocate -g Grid-Prod-RG -n vm-volt-db"
Write-Host "   az vmss deallocate -g Grid-Prod-RG -n VoltBill-VMSS"
Write-Host "   az network bastion delete -g Grid-Prod-RG -n LightUP-Bastion`n"
