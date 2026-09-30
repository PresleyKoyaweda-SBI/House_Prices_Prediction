#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap projet - Déploiement de bout en bout en une commande (équivalent
    PowerShell de bootstrap-project.sh, pour poste Windows).

.DESCRIPTION
    Enchaîne toutes les étapes manuelles du Quick Start du README : infra
    Terraform, création du compute/environnement Azure ML, accès du compute
    à l'ACR (AcrPull, seulement si le compte admin de l'ACR est désactivé),
    enregistrement du data asset, et soumission du pipeline d'entraînement —
    le premier déploiement d'un nouveau projet client, une fois le repo cloné.
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

Step "5/7 — Accès du compute à l'ACR (images Docker)"
# Le seul rôle dont le compute peut avoir besoin : register_model n'appelle
# plus le SDK (l'enregistrement est fait par Azure ML via la sortie nommée du
# pipeline), donc plus besoin de "AzureML Data Scientist".
$AdminEnabled = az acr show --name $Acr --resource-group $Rg --query adminUserEnabled -o tsv
if ($AdminEnabled -eq "true") {
    # Mode sans RBAC (enable_rbac_assignments = false dans les tfvars) : Azure ML
    # récupère les images avec le compte admin de l'ACR, aucun rôle à attribuer.
    # Ce mode permet de déployer avec le seul rôle Contributor sur le RG.
    Write-Host "✅ Compte admin de l'ACR activé : aucun rôle à attribuer"
}
else {
    $ComputePrincipalId = az ml compute show --name $ComputeName `
        --resource-group $Rg --workspace-name $Workspace `
        --query identity.principal_id -o tsv
    $AcrId = az acr show --name $Acr --resource-group $Rg --query id -o tsv
    $existing = az role assignment list --assignee-object-id $ComputePrincipalId `
        --scope $AcrId --query "[?roleDefinitionName=='AcrPull']" -o tsv
    if ($existing) {
        Write-Host "✅ Rôle 'AcrPull' déjà assigné"
    }
    else {
        az role assignment create --assignee-object-id $ComputePrincipalId `
            --assignee-principal-type ServicePrincipal --role AcrPull --scope $AcrId | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # Attribuer un rôle exige Owner, User Access Administrator ou RBAC
            # Administrator : sans ce droit, un administrateur doit le faire.
            Write-Host "❌ Impossible d'attribuer AcrPull (droit Microsoft.Authorization/roleAssignments/write requis)."
            Write-Host "   Faire lancer par un Owner du resource group :"
            Write-Host "   az role assignment create --assignee-object-id $ComputePrincipalId ``"
            Write-Host "     --assignee-principal-type ServicePrincipal --role AcrPull --scope $AcrId"
            Write-Host "   Ou passer en mode sans RBAC : admin_enabled = true dans environments/$Env.tfvars."
            exit 1
        }
        Write-Host "✅ Rôle 'AcrPull' assigné"
    }
}

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
