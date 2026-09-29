#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap projet - Déploiement de bout en bout en une commande (équivalent
    PowerShell de bootstrap-project.sh, pour poste Windows).

.DESCRIPTION
    Enchaîne toutes les étapes manuelles du Quick Start du README : infra
    Terraform, création du compute/environnement Azure ML, role assignments
    requis (AcrPull, AzureML Data Scientist), enregistrement du data asset,
    et soumission du pipeline d'entraînement (sample tant qu'il n'a pas
    encore été personnalisé, voir docs/CUSTOMIZATION_GUIDE.md) — le premier
    déploiement d'un nouveau projet client, une fois le repo cloné.
    Idempotent : peut être relancé sans échouer si une ressource existe déjà.

.PARAMETER Env
    Environnement Terraform à déployer (dev|staging|prod). Défaut : dev.

.PARAMETER SkipInfra
    Réutilise l'infrastructure Terraform déjà déployée (pas de terraform apply).

.EXAMPLE
    ./scripts/bootstrap-project.ps1
    ./scripts/bootstrap-project.ps1 -Env dev -SkipInfra
#>
param(
    [ValidateSet("dev", "staging", "prod")]
    [string]$Env = "dev",
    [switch]$SkipInfra
)

$ErrorActionPreference = "Stop"

$TfDir = "infrastructure/terraform"
$ComputeName = "cpu-cluster"
$EnvName = "ml-project-training-env"
$DataName = "house-prices-raw-data"

function Step($msg) {
    Write-Host ""
    Write-Host "▶ $msg"
    Write-Host "----------------------------------------"
}

function Assign-Role($principalId, $role, $scope) {
    $existing = az role assignment list --assignee-object-id $principalId `
        --scope $scope --query "[?roleDefinitionName=='$role']" -o tsv
    if ($existing) {
        Write-Host "✅ Rôle '$role' déjà assigné"
    }
    else {
        az role assignment create --assignee-object-id $principalId `
            --assignee-principal-type ServicePrincipal --role $role --scope $scope | Out-Null
        Write-Host "✅ Rôle '$role' assigné"
    }
}

Step "0/7 — Vérification az login"
try { az account show | Out-Null } catch {
    Write-Host "❌ Non connecté. Lancer 'az login' puis 'az account set --subscription <id>' d'abord."
    exit 1
}
$SubscriptionId = az account show --query id -o tsv
Write-Host "✅ Connecté — subscription $SubscriptionId"

if (-not $SkipInfra) {
    Step "1/7 — Infrastructure Terraform (env: $Env)"
    if (-not (Test-Path "environments/backend-$Env.hcl")) {
        Write-Host "❌ environments/backend-$Env.hcl introuvable — lancer d'abord :"
        Write-Host "   make bootstrap-tfstate"
        Write-Host "   Copier environments/backend-$Env.hcl.example vers environments/backend-$Env.hcl (puis éditer)"
        exit 1
    }
    Push-Location $TfDir
    terraform init -input=false -backend-config="../../environments/backend-$Env.hcl" | Out-Null
    terraform apply -auto-approve -input=false -var-file="../../environments/$Env.tfvars"
    Pop-Location
}
else {
    Step "1/7 — Infrastructure Terraform (-SkipInfra, réutilisation)"
}

Push-Location $TfDir
$Rg = terraform output -raw resource_group_name
$Workspace = terraform output -raw workspace_name
$Acr = terraform output -raw container_registry_name
Pop-Location
Write-Host "✅ RG=$Rg  Workspace=$Workspace  ACR=$Acr"

Step "2/7 — Extension Azure CLI 'ml'"
try { az extension add -n ml -y --only-show-errors 2>$null | Out-Null } catch {}
Write-Host "✅ Extension ml prête"

Step "3/7 — Compute cluster ($ComputeName)"
$computeExists = $true
try { az ml compute show --name $ComputeName --resource-group $Rg --workspace-name $Workspace | Out-Null }
catch { $computeExists = $false }
if ($computeExists) {
    Write-Host "✅ Déjà existant"
}
else {
    az ml compute create --file ml/compute/compute-cluster.yml `
        --resource-group $Rg --workspace-name $Workspace
}

Step "4/7 — Environnement d'entraînement ($EnvName)"
az ml environment create --file ml/environments/training-environment.yml `
    --resource-group $Rg --workspace-name $Workspace | Out-Null
Write-Host "✅ Environnement enregistré (nouvelle version si conda.yml a changé)"

Step "5/7 — Role assignments du compute (AcrPull, AzureML Data Scientist)"
$ComputePrincipalId = az ml compute show --name $ComputeName `
    --resource-group $Rg --workspace-name $Workspace `
    --query identity.principal_id -o tsv
$AcrId = az acr show --name $Acr --resource-group $Rg --query id -o tsv
$WsId = az ml workspace show --name $Workspace --resource-group $Rg --query id -o tsv

Assign-Role $ComputePrincipalId "AcrPull" $AcrId
Assign-Role $ComputePrincipalId "AzureML Data Scientist" $WsId

Step "6/7 — Data asset ($DataName)"
try {
    az ml data create --file ml/data/sample-data-asset.yml `
        --resource-group $Rg --workspace-name $Workspace 2>$null | Out-Null
}
catch { Write-Host "ℹ️  Déjà enregistré (une version existe déjà)" }

Step "7/7 — Soumission du pipeline d'entraînement"
$JobName = az ml job create --file ml/pipelines/training-pipeline.yml `
    --resource-group $Rg --workspace-name $Workspace `
    --query name -o tsv

$StudioUrl = "https://ml.azure.com/runs/$JobName`?wsid=/subscriptions/$SubscriptionId/resourcegroups/$Rg/workspaces/$Workspace"
Write-Host ""
Write-Host "🎉 Pipeline soumis : $JobName"
Write-Host "🔗 Suivre le run dans Azure ML Studio : $StudioUrl"
Write-Host ""
Write-Host "Streamer les logs en direct :"
Write-Host "  az ml job stream --name $JobName --resource-group $Rg --workspace-name $Workspace"
