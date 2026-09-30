#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap projet - Déploiement de bout en bout en une commande (équivalent
    PowerShell de bootstrap-project.sh, pour poste Windows).

.DESCRIPTION
    Enchaîne toutes les étapes du Quick Start du README : infra Terraform,
    compute et environnement Azure ML, accès du compute à l'ACR (AcrPull,
    seulement si le compte admin de l'ACR est désactivé), data asset,
    entraînement (pipeline), enregistrement du modèle en MLFLOW et
    déploiement sur l'endpoint batch. Idempotent : peut être relancé sans
    échouer si une ressource existe déjà.

    Aucune étape n'attribue de rôle Azure dans la configuration actuelle
    (mode sans RBAC) : le script fonctionne avec le seul rôle Contributor.

.PARAMETER Env
    Environnement Terraform à déployer (dev|staging|prod). Défaut : dev.

.PARAMETER SkipInfra
    Réutilise l'infrastructure Terraform déjà déployée (pas de terraform apply).

.PARAMETER NoWait
    Soumet le pipeline et rend la main, sans enregistrer ni déployer le modèle.

.EXAMPLE
    ./scripts/bootstrap-project.ps1
    ./scripts/bootstrap-project.ps1 -Env dev -SkipInfra
    ./scripts/bootstrap-project.ps1 -Env dev -SkipInfra -NoWait
#>
param(
    [ValidateSet("dev", "staging", "prod")]
    [string]$Env = "dev",
    [switch]$SkipInfra,
    [switch]$NoWait
)

$ErrorActionPreference = "Stop"

$TfDir = "infrastructure/terraform"
$ComputeName = "cpu-cluster"
$EnvName = "ml-project-training-env"
$DataFile = "ml/data/sample-data-asset.yml"
$EndpointFile = "ml/endpoints/batch/batch-endpoint.yml"
$DeploymentFile = "ml/endpoints/batch/batch-deployment.yml"

function Step($msg) {
    Write-Host ""
    Write-Host "▶ $msg"
    Write-Host "----------------------------------------"
}

# Valeur d'une clé de premier niveau d'un YAML (nom et version lus dans les
# fichiers du repo, pour ne jamais diverger d'eux).
function Get-YamlValue($key, $file) {
    $line = Select-String -Path $file -Pattern "^${key}:\s*(.+)$" | Select-Object -First 1
    if (-not $line) { throw "Clé '$key' introuvable dans $file" }
    return $line.Matches[0].Groups[1].Value.Trim()
}

# Échoue explicitement si la dernière commande az a échoué (PowerShell ne le
# fait pas seul pour les exécutables externes).
function Assert-LastCommand($what) {
    if ($LASTEXITCODE -ne 0) { throw "Échec : $what" }
}

$DataName = Get-YamlValue "name" $DataFile
$DataVersion = Get-YamlValue "version" $DataFile
$EndpointName = Get-YamlValue "name" $EndpointFile
# Le modèle déployé est "azureml:<nom>@latest" dans batch-deployment.yml.
$ModelName = (Get-YamlValue "model" $DeploymentFile) -replace '^azureml:', '' -replace '[@:].*$', ''

Step "0/9 — Vérification az login"
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Non connecté. Lancer 'az login' puis 'az account set --subscription <id>' d'abord."
    exit 1
}
$SubscriptionId = az account show --query id -o tsv
Write-Host "✅ Connecté — subscription $SubscriptionId"

if (-not $SkipInfra) {
    Step "1/9 — Infrastructure Terraform (env: $Env)"
    if (-not (Test-Path "environments/backend-$Env.hcl")) {
        Write-Host "❌ environments/backend-$Env.hcl introuvable — lancer d'abord :"
        Write-Host "   make bootstrap-tfstate"
        Write-Host "   Copier environments/backend-$Env.hcl.example vers environments/backend-$Env.hcl (puis éditer)"
        exit 1
    }
    Push-Location $TfDir
    # -reconfigure : dev et prod partagent le même dossier Terraform, il faut
    # basculer explicitement sur le backend de l'environnement demandé.
    terraform init -reconfigure -input=false -backend-config="../../environments/backend-$Env.hcl" | Out-Null
    Assert-LastCommand "terraform init"
    terraform apply -auto-approve -input=false -var-file="../../environments/$Env.tfvars"
    Assert-LastCommand "terraform apply"
    Pop-Location
}
else {
    Step "1/9 — Infrastructure Terraform (-SkipInfra, réutilisation)"
}

Push-Location $TfDir
$Rg = terraform output -raw resource_group_name
$Workspace = terraform output -raw workspace_name
$Acr = terraform output -raw container_registry_name
Pop-Location
Write-Host "✅ RG=$Rg  Workspace=$Workspace  ACR=$Acr"
# Garde-fou : le backend Terraform initialisé doit être celui de l'environnement
# demandé (sinon on déploierait dans le workspace d'un autre environnement).
if ($Workspace -notlike "*-$Env-*") {
    Write-Host "❌ Le workspace '$Workspace' ne correspond pas à l'environnement '$Env'."
    Write-Host "   Lancer : terraform init -reconfigure -backend-config=../../environments/backend-$Env.hcl (dans $TfDir)"
    exit 1
}
$AzWs = @("--resource-group", $Rg, "--workspace-name", $Workspace)

Step "2/9 — Extension Azure CLI 'ml'"
az extension add -n ml -y --only-show-errors 2>$null | Out-Null
Write-Host "✅ Extension ml prête"

Step "3/9 — Compute cluster ($ComputeName)"
az ml compute show --name $ComputeName @AzWs 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Déjà existant"
}
else {
    az ml compute create --file ml/compute/compute-cluster.yml @AzWs | Out-Null
    Assert-LastCommand "création du compute"
    Write-Host "✅ Créé"
}

Step "4/9 — Environnement d'entraînement ($EnvName)"
az ml environment create --file ml/environments/training-environment.yml @AzWs | Out-Null
Assert-LastCommand "enregistrement de l'environnement"
Write-Host "✅ Environnement enregistré (nouvelle version si conda.yml a changé)"

Step "5/9 — Accès du compute à l'ACR (images Docker)"
# Le seul rôle dont le compute peut avoir besoin : aucun composant n'appelle
# le SDK Azure ML (l'enregistrement du modèle est fait à l'étape 8, avec
# l'identité de celui qui lance ce script).
$AdminEnabled = az acr show --name $Acr --resource-group $Rg --query adminUserEnabled -o tsv
if ($AdminEnabled -eq "true") {
    # Mode sans RBAC (enable_rbac_assignments = false dans les tfvars) : Azure ML
    # récupère les images avec le compte admin de l'ACR, aucun rôle à attribuer.
    Write-Host "✅ Compte admin de l'ACR activé : aucun rôle à attribuer"
}
else {
    $ComputePrincipalId = az ml compute show --name $ComputeName @AzWs --query identity.principal_id -o tsv
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

Step "6/9 — Data asset (${DataName}:$DataVersion)"
# Je vérifie l'existence d'abord, pour qu'une vraie erreur d'envoi ne soit pas
# masquée par un faux "déjà enregistré".
az ml data show --name $DataName --version $DataVersion @AzWs 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Déjà enregistré (incrémenter 'version:' dans $DataFile pour de nouvelles données)"
}
else {
    az ml data create --file $DataFile @AzWs | Out-Null
    Assert-LastCommand "enregistrement du data asset"
    Write-Host "✅ Enregistré"
}

Step "7/9 — Soumission du pipeline d'entraînement"
$JobName = az ml job create --file ml/pipelines/training-pipeline.yml @AzWs --query name -o tsv
Assert-LastCommand "soumission du pipeline"
$StudioUrl = "https://ml.azure.com/runs/$JobName`?wsid=/subscriptions/$SubscriptionId/resourcegroups/$Rg/workspaces/$Workspace"
Write-Host "✅ Pipeline soumis : $JobName"
Write-Host "🔗 $StudioUrl"

if ($NoWait) {
    Write-Host ""
    Write-Host "ℹ️  -NoWait : le modèle ne sera ni enregistré ni déployé par ce script."
    Write-Host "   Streamer les logs : az ml job stream --name $JobName --resource-group $Rg --workspace-name $Workspace"
    exit 0
}

Step "8/9 — Attente du pipeline et enregistrement du modèle ($ModelName)"
Write-Host "⏳ Attente de la fin du pipeline (20 à 30 min si l'image d'entraînement doit être construite)…"
# `stream` échoue si le pipeline échoue : je lis le statut juste après pour
# afficher un message clair plutôt que la trace de la CLI.
az ml job stream --name $JobName @AzWs 2>$null | Out-Null
$Status = az ml job show --name $JobName @AzWs --query status -o tsv
if ($Status -ne "Completed") {
    Write-Host "❌ Pipeline terminé avec le statut '$Status' : aucun modèle enregistré ni déployé."
    Write-Host "   Cause la plus fréquente : modèle refusé par le contrôle qualité (voir le log de register_model_job)."
    Write-Host "   🔗 $StudioUrl"
    exit 1
}
# Le modèle accepté est la sortie model_output de l'étape register_model_job.
# Je l'enregistre explicitement en MLFLOW : l'enregistrement automatique par
# sortie nommée produirait un modèle CUSTOM, que le batch sans code refuse.
$GateJob = az ml job list --parent-job-name $JobName @AzWs `
    --query "[?display_name=='register_model_job'].name | [0]" -o tsv
$LastVersion = az ml model list --name $ModelName @AzWs --query "max([].to_number(version))" -o tsv 2>$null
if ($LastVersion -notmatch '^\d+$') { $LastVersion = 0 }
$ModelVersion = [int]$LastVersion + 1
az ml model create --name $ModelName --version $ModelVersion --type mlflow_model `
    --path "azureml://jobs/$GateJob/outputs/model_output" `
    --description "Valeur médiane des logements par district (California Housing). Pipeline $JobName." `
    @AzWs | Out-Null
Assert-LastCommand "enregistrement du modèle"
Write-Host "✅ Modèle enregistré : $ModelName version $ModelVersion (MLFLOW)"

Step "9/9 — Déploiement sur l'endpoint batch ($EndpointName)"
az ml batch-endpoint show --name $EndpointName @AzWs 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Endpoint déjà existant"
}
else {
    az ml batch-endpoint create --file $EndpointFile @AzWs | Out-Null
    Assert-LastCommand "création de l'endpoint batch"
    Write-Host "✅ Endpoint créé"
}
# Le déploiement référence "@latest" : il prend la version enregistrée à
# l'étape 8. Relancer create met à jour le déploiement existant.
az ml batch-deployment create --file $DeploymentFile @AzWs --set-default | Out-Null
Assert-LastCommand "déploiement batch"
Write-Host "✅ Déploiement à jour : $ModelName version $ModelVersion"

Write-Host ""
Write-Host "🎉 Terminé : modèle ${ModelName}:$ModelVersion entraîné, enregistré et déployé ($Env)."
Write-Host "   Vérifier l'endpoint : définir AZURE_SUBSCRIPTION_ID=$SubscriptionId, AZURE_RESOURCE_GROUP=$Rg,"
Write-Host "   AZUREML_WORKSPACE_NAME=$Workspace, BATCH_ENDPOINT_NAME=$EndpointName, puis : python -m pytest tests/smoke/ -v"
