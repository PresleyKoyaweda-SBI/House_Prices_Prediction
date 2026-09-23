#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap du storage account de state Terraform (équivalent PowerShell
    de bootstrap-tfstate.sh).

.DESCRIPTION
    Pattern documenté par Microsoft pour stocker le state Terraform dans
    Azure Storage (https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage) :
    un storage account dédié, provisionné hors Terraform, un seul par
    client/tenant, partagé par les 3 environnements (dev/staging/prod),
    chacun avec son propre blob (`key`) dans le même conteneur.

    À exécuter UNE SEULE FOIS par client/tenant, avant le tout premier
    `make tf-init`. Idempotent : peut être relancé sans échouer.

.PARAMETER ProjectName
    Nom du projet (défaut : lu depuis environments/dev.tfvars).

.PARAMETER Location
    Région Azure du storage account de state. Défaut : canadacentral.

.EXAMPLE
    ./scripts/bootstrap-tfstate.ps1
#>
param(
    [string]$ProjectName,
    [string]$Location = "canadacentral"
)

$ErrorActionPreference = "Stop"

if (-not $ProjectName) {
    $line = Select-String -Path "environments/dev.tfvars" -Pattern '^project_name' | Select-Object -First 1
    $ProjectName = ($line -replace '.*"(.*)".*', '$1')
}
$ProjectShort = $ProjectName -replace '-', ''
$Suffix = -join ((48..57 + 97..102) | Get-Random -Count 6 | ForEach-Object { [char]$_ })

$Rg = "rg-tfstate-$ProjectName"
$Sa = "sttfstate$ProjectShort$Suffix"
$Container = "tfstate"

function Step($msg) {
    Write-Host ""
    Write-Host "▶ $msg"
    Write-Host "----------------------------------------"
}

Step "0/4 — Vérification az login"
try { az account show | Out-Null } catch {
    Write-Host "❌ Non connecté. Lancer 'az login' d'abord."
    exit 1
}

Step "1/4 — Resource group ($Rg)"
$rgExists = $true
try { az group show --name $Rg | Out-Null } catch { $rgExists = $false }
if ($rgExists) {
    Write-Host "✅ Déjà existant"
}
else {
    az group create --name $Rg --location $Location | Out-Null
    Write-Host "✅ Créé"
}

Step "2/4 — Storage account ($Sa)"
$saExists = $true
try { az storage account show --name $Sa --resource-group $Rg | Out-Null } catch { $saExists = $false }
if ($saExists) {
    Write-Host "✅ Déjà existant"
}
else {
    # Best practice Microsoft : TLS 1.2 minimum, pas d'accès blob public,
    # réplication LRS suffisante pour un state (le versioning ci-dessous
    # protège déjà contre une corruption/suppression accidentelle).
    az storage account create `
        --name $Sa --resource-group $Rg --location $Location `
        --sku Standard_LRS --kind StorageV2 `
        --min-tls-version TLS1_2 --allow-blob-public-access false | Out-Null
    Write-Host "✅ Créé"
}

Step "3/4 — Versioning + soft delete sur les blobs"
az storage account blob-service-properties update `
    --account-name $Sa --resource-group $Rg `
    --enable-versioning true `
    --enable-delete-retention true --delete-retention-days 30 | Out-Null
Write-Host "✅ Activés (protège le state contre une corruption/suppression accidentelle)"

Step "4/4 — Container ($Container)"
$containerExists = $true
try { az storage container show --name $Container --account-name $Sa --auth-mode login | Out-Null }
catch { $containerExists = $false }
if ($containerExists) {
    Write-Host "✅ Déjà existant"
}
else {
    az storage container create --name $Container --account-name $Sa --auth-mode login | Out-Null
    Write-Host "✅ Créé"
}

Write-Host ""
Write-Host "🎉 Storage de state prêt : $Sa / $Container (resource group $Rg)"
Write-Host ""
Write-Host "Prochaine étape — pour CHAQUE environnement (dev/staging/prod) :"
Write-Host "  1. Copier environments/backend-<env>.hcl.example vers environments/backend-<env>.hcl"
Write-Host "  2. Remplacer resource_group_name/storage_account_name par :"
Write-Host "       resource_group_name  = `"$Rg`""
Write-Host "       storage_account_name = `"$Sa`""
Write-Host "  3. Accorder le rôle 'Storage Blob Data Contributor' sur ce storage account"
Write-Host "     à chaque identité qui exécutera terraform (voir docs/SECURITY.md)."
Write-Host "  4. make tf-init ENV=<env>"
