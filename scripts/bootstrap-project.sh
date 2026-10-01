#!/bin/bash
set -euo pipefail

# Bootstrap projet - Déploiement de bout en bout en une commande
#
# Enchaîne toutes les étapes du Quick Start du README : infra Terraform,
# compute et environnement Azure ML, accès du compute à l'ACR (AcrPull,
# seulement si le compte admin de l'ACR est désactivé), data asset,
# entraînement (pipeline), enregistrement du modèle en MLFLOW et déploiement
# sur l'endpoint batch.
#
# Objectif : partir d'un `az login` et arriver à un modèle entraîné,
# enregistré et déployé, sans étape manuelle intermédiaire. Idempotent : peut
# être relancé sans échouer si une ressource existe déjà (chaque étape
# vérifie avant de créer). Utilisé tel quel par la CD (.github/workflows/cd.yml).
#
# Aucune étape n'attribue de rôle Azure dans la configuration actuelle (mode
# sans RBAC) : le script fonctionne avec le seul rôle Contributor sur le RG.
#
# Usage :
#   ./scripts/bootstrap-project.sh [ENV]                  (ENV = dev par défaut)
#   ./scripts/bootstrap-project.sh dev --skip-infra       (réutilise l'infra existante)
#   ./scripts/bootstrap-project.sh dev --skip-infra --no-wait
#       (soumet le pipeline et rend la main, sans enregistrer ni déployer)

# Git Bash (Windows) réécrit tout argument commençant par "/" en chemin
# Windows : "--scope /subscriptions/..." deviendrait "C:/Program Files/Git/
# subscriptions/..." et az échouerait (MissingSubscription). Sans effet
# ailleurs (Linux, macOS, CI).
export MSYS_NO_PATHCONV=1

ENV="dev"
SKIP_INFRA="false"
NO_WAIT="false"
for arg in "$@"; do
  case "$arg" in
    --skip-infra) SKIP_INFRA="true" ;;
    --no-wait) NO_WAIT="true" ;;
    dev|staging|prod) ENV="$arg" ;;
  esac
done

TF_DIR="infrastructure/terraform"
COMPUTE_NAME="cpu-cluster"
ENV_NAME="ml-project-training-env"
DATA_FILE="ml/data/sample-data-asset.yml"
ENDPOINT_FILE="ml/endpoints/batch/batch-endpoint.yml"
DEPLOYMENT_FILE="ml/endpoints/batch/batch-deployment.yml"
# Nom et version lus dans les YAML, pour ne jamais diverger d'eux. `tr -d '\r'`
# retire le retour chariot des fichiers enregistrés avec des fins de ligne Windows.
yaml_value() { sed -n "s/^$1: *//p" "$2" | head -1 | tr -d '\r'; }
DATA_NAME=$(yaml_value name "$DATA_FILE")
DATA_VERSION=$(yaml_value version "$DATA_FILE")
# Un endpoint par environnement : son nom doit être unique dans toute la
# région Azure (il forme l'adresse d'appel), dev et prod ne peuvent pas le partager.
ENDPOINT_NAME="$(yaml_value name "$ENDPOINT_FILE")-${ENV}"
# Le modèle déployé est "azureml:<nom>@latest" dans batch-deployment.yml.
MODEL_NAME=$(yaml_value model "$DEPLOYMENT_FILE" | sed 's/^azureml://; s/[@:].*//')

step() { echo ""; echo "▶ $1"; echo "----------------------------------------"; }

step "0/9 — Vérification az login"
az account show >/dev/null 2>&1 || {
  echo "❌ Non connecté. Lancer 'az login' puis 'az account set --subscription <id>' d'abord."
  exit 1
}
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "✅ Connecté — subscription $SUBSCRIPTION_ID"

if [[ "$SKIP_INFRA" == "false" ]]; then
  step "1/9 — Infrastructure Terraform (env: $ENV)"
  if [[ ! -f "environments/backend-${ENV}.hcl" ]]; then
    echo "❌ environments/backend-${ENV}.hcl introuvable — lancer d'abord :"
    echo "   make bootstrap-tfstate"
    echo "   cp environments/backend-${ENV}.hcl.example environments/backend-${ENV}.hcl  # puis éditer"
    exit 1
  fi
  # -reconfigure : dev et prod partagent le même dossier Terraform, il faut
  # basculer explicitement sur le backend de l'environnement demandé.
  (cd "$TF_DIR" && terraform init -reconfigure -input=false -backend-config="../../environments/backend-${ENV}.hcl" >/dev/null)
  (cd "$TF_DIR" && terraform apply -auto-approve -input=false -var-file="../../environments/${ENV}.tfvars")
else
  step "1/9 — Infrastructure Terraform (--skip-infra, réutilisation)"
fi

RG=$(cd "$TF_DIR" && terraform output -raw resource_group_name)
WORKSPACE=$(cd "$TF_DIR" && terraform output -raw workspace_name)
ACR=$(cd "$TF_DIR" && terraform output -raw container_registry_name)
echo "✅ RG=$RG  Workspace=$WORKSPACE  ACR=$ACR"
# Garde-fou : le backend Terraform initialisé doit être celui de l'environnement
# demandé (sinon on déploierait dans le workspace d'un autre environnement).
if [[ "$WORKSPACE" != *"-${ENV}-"* ]]; then
  echo "❌ Le workspace '$WORKSPACE' ne correspond pas à l'environnement '$ENV'."
  echo "   Lancer : (cd $TF_DIR && terraform init -reconfigure -backend-config=../../environments/backend-${ENV}.hcl)"
  exit 1
fi
AZ_WS=(--resource-group "$RG" --workspace-name "$WORKSPACE")

step "2/9 — Extension Azure CLI 'ml'"
az extension add -n ml -y --only-show-errors >/dev/null 2>&1 || true
echo "✅ Extension ml prête"

step "3/9 — Compute cluster ($COMPUTE_NAME)"
if az ml compute show --name "$COMPUTE_NAME" "${AZ_WS[@]}" >/dev/null 2>&1; then
  echo "✅ Déjà existant"
else
  az ml compute create --file ml/compute/compute-cluster.yml "${AZ_WS[@]}" >/dev/null
  echo "✅ Créé"
fi

step "4/9 — Environnement d'entraînement ($ENV_NAME)"
az ml environment create --file ml/environments/training-environment.yml "${AZ_WS[@]}" >/dev/null
echo "✅ Environnement enregistré (nouvelle version si conda.yml a changé)"

step "5/9 — Accès du compute à l'ACR (images Docker)"
# Le seul rôle dont le compute peut avoir besoin : aucun composant n'appelle
# le SDK Azure ML (l'enregistrement du modèle est fait à l'étape 8, avec
# l'identité de celui qui lance ce script).
if [[ "$(az acr show --name "$ACR" --resource-group "$RG" --query adminUserEnabled -o tsv)" == "true" ]]; then
  # Mode sans RBAC (enable_rbac_assignments = false dans les tfvars) : Azure ML
  # récupère les images avec le compte admin de l'ACR, aucun rôle à attribuer.
  echo "✅ Compte admin de l'ACR activé : aucun rôle à attribuer"
else
  COMPUTE_PRINCIPAL_ID=$(az ml compute show --name "$COMPUTE_NAME" "${AZ_WS[@]}" \
    --query identity.principal_id -o tsv)
  ACR_ID=$(az acr show --name "$ACR" --resource-group "$RG" --query id -o tsv)
  if az role assignment list --assignee-object-id "$COMPUTE_PRINCIPAL_ID" \
      --scope "$ACR_ID" --query "[?roleDefinitionName=='AcrPull']" -o tsv | grep -q .; then
    echo "✅ Rôle 'AcrPull' déjà assigné"
  elif az role assignment create --assignee-object-id "$COMPUTE_PRINCIPAL_ID" \
      --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID" >/dev/null; then
    echo "✅ Rôle 'AcrPull' assigné"
  else
    # Attribuer un rôle exige Owner, User Access Administrator ou RBAC
    # Administrator : sans ce droit, un administrateur doit le faire.
    echo "❌ Impossible d'attribuer AcrPull (droit Microsoft.Authorization/roleAssignments/write requis)."
    echo "   Faire lancer par un Owner du resource group :"
    echo "   az role assignment create --assignee-object-id $COMPUTE_PRINCIPAL_ID \\"
    echo "     --assignee-principal-type ServicePrincipal --role AcrPull --scope $ACR_ID"
    echo "   Ou passer en mode sans RBAC : admin_enabled = true dans environments/${ENV}.tfvars."
    exit 1
  fi
fi

step "6/9 — Data asset ($DATA_NAME:$DATA_VERSION)"
# Je vérifie l'existence d'abord, pour qu'une vraie erreur d'envoi ne soit pas
# masquée par un faux "déjà enregistré".
if az ml data show --name "$DATA_NAME" --version "$DATA_VERSION" "${AZ_WS[@]}" >/dev/null 2>&1; then
  echo "✅ Déjà enregistré (incrémenter 'version:' dans $DATA_FILE pour de nouvelles données)"
else
  az ml data create --file "$DATA_FILE" "${AZ_WS[@]}" >/dev/null
  echo "✅ Enregistré"
fi

step "7/9 — Soumission du pipeline d'entraînement"
JOB_NAME=$(az ml job create --file ml/pipelines/training-pipeline.yml "${AZ_WS[@]}" \
  --query name -o tsv)
STUDIO_URL="https://ml.azure.com/runs/${JOB_NAME}?wsid=/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RG}/workspaces/${WORKSPACE}"
echo "✅ Pipeline soumis : $JOB_NAME"
echo "🔗 $STUDIO_URL"

if [[ "$NO_WAIT" == "true" ]]; then
  echo ""
  echo "ℹ️  --no-wait : le modèle ne sera ni enregistré ni déployé par ce script."
  echo "   Streamer les logs : az ml job stream --name $JOB_NAME --resource-group $RG --workspace-name $WORKSPACE"
  exit 0
fi

step "8/9 — Attente du pipeline et enregistrement du modèle ($MODEL_NAME)"
echo "⏳ Attente de la fin du pipeline (20 à 30 min si l'image d'entraînement doit être construite)…"
# `stream` échoue si le pipeline échoue : je lis le statut juste après pour
# afficher un message clair plutôt que la trace de la CLI.
az ml job stream --name "$JOB_NAME" "${AZ_WS[@]}" >/dev/null 2>&1 || true
STATUS=$(az ml job show --name "$JOB_NAME" "${AZ_WS[@]}" --query status -o tsv)
if [[ "$STATUS" != "Completed" ]]; then
  echo "❌ Pipeline terminé avec le statut '$STATUS' : aucun modèle enregistré ni déployé."
  echo "   Cause la plus fréquente : modèle refusé par le contrôle qualité (voir le log de register_model_job)."
  echo "   🔗 $STUDIO_URL"
  exit 1
fi
# Le modèle accepté est la sortie model_output de l'étape register_model_job.
# Je l'enregistre explicitement en MLFLOW : l'enregistrement automatique par
# sortie nommée produirait un modèle CUSTOM, que le batch sans code refuse.
GATE_JOB=$(az ml job list --parent-job-name "$JOB_NAME" "${AZ_WS[@]}" \
  --query "[?display_name=='register_model_job'].name | [0]" -o tsv)
LAST_VERSION=$(az ml model list --name "$MODEL_NAME" "${AZ_WS[@]}" \
  --query "max([].to_number(version))" -o tsv 2>/dev/null || true)
[[ "$LAST_VERSION" =~ ^[0-9]+$ ]] || LAST_VERSION=0
MODEL_VERSION=$((LAST_VERSION + 1))
az ml model create --name "$MODEL_NAME" --version "$MODEL_VERSION" --type mlflow_model \
  --path "azureml://jobs/${GATE_JOB}/outputs/model_output" \
  --description "Valeur médiane des logements par district (California Housing). Pipeline ${JOB_NAME}." \
  "${AZ_WS[@]}" >/dev/null
echo "✅ Modèle enregistré : $MODEL_NAME version $MODEL_VERSION (MLFLOW)"

step "9/9 — Déploiement sur l'endpoint batch ($ENDPOINT_NAME)"
if az ml batch-endpoint show --name "$ENDPOINT_NAME" "${AZ_WS[@]}" >/dev/null 2>&1; then
  echo "✅ Endpoint déjà existant"
else
  az ml batch-endpoint create --file "$ENDPOINT_FILE" --name "$ENDPOINT_NAME" "${AZ_WS[@]}" >/dev/null
  echo "✅ Endpoint créé"
fi
# Le déploiement référence "@latest" : il prend la version enregistrée à
# l'étape 8. Relancer create met à jour le déploiement existant.
az ml batch-deployment create --file "$DEPLOYMENT_FILE" --endpoint-name "$ENDPOINT_NAME" \
  "${AZ_WS[@]}" --set-default >/dev/null
echo "✅ Déploiement à jour : $MODEL_NAME version $MODEL_VERSION"

echo ""
echo "🎉 Terminé : modèle $MODEL_NAME:$MODEL_VERSION entraîné, enregistré et déployé ($ENV)."
echo "   Vérifier l'endpoint : BATCH_ENDPOINT_NAME=$ENDPOINT_NAME AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID \\"
echo "     AZURE_RESOURCE_GROUP=$RG AZUREML_WORKSPACE_NAME=$WORKSPACE python -m pytest tests/smoke/ -v"
