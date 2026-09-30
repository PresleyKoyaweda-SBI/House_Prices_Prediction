#!/bin/bash
set -euo pipefail

# Bootstrap projet - Déploiement de bout en bout en une commande
#
# Enchaîne toutes les étapes manuelles du Quick Start du README : infra
# Terraform, création du compute/environnement Azure ML, accès du compute à
# l'ACR (AcrPull, seulement si le compte admin de l'ACR est désactivé),
# enregistrement du data asset, et soumission du pipeline d'entraînement.
#
# Objectif : partir d'un `az login` et arriver à un run de pipeline visible
# dans Azure ML Studio, sans étape manuelle intermédiaire — le premier
# déploiement d'un nouveau projet client, une fois le repo cloné. Idempotent :
# peut être relancé sans échouer si une ressource existe déjà (chaque étape
# vérifie avant de créer).
#
# Usage :
#   ./scripts/bootstrap-project.sh [ENV]        (ENV = dev par défaut)
#   ./scripts/bootstrap-project.sh dev --skip-infra   (réutilise l'infra existante)

# Git Bash (Windows) réécrit tout argument commençant par "/" en chemin
# Windows : "--scope /subscriptions/..." deviendrait "C:/Program Files/Git/
# subscriptions/..." et az échouerait (MissingSubscription). Sans effet
# ailleurs (Linux, macOS, CI).
export MSYS_NO_PATHCONV=1

ENV="dev"
SKIP_INFRA="false"
for arg in "$@"; do
  case "$arg" in
    --skip-infra) SKIP_INFRA="true" ;;
    dev|staging|prod) ENV="$arg" ;;
  esac
done

TF_DIR="infrastructure/terraform"
COMPUTE_NAME="cpu-cluster"
ENV_NAME="ml-project-training-env"
DATA_NAME="house-prices-raw-data"

step() { echo ""; echo "▶ $1"; echo "----------------------------------------"; }

step "0/7 — Vérification az login"
az account show >/dev/null 2>&1 || {
  echo "❌ Non connecté. Lancer 'az login' puis 'az account set --subscription <id>' d'abord."
  exit 1
}
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "✅ Connecté — subscription $SUBSCRIPTION_ID"

if [[ "$SKIP_INFRA" == "false" ]]; then
  step "1/7 — Infrastructure Terraform (env: $ENV)"
  if [[ ! -f "environments/backend-${ENV}.hcl" ]]; then
    echo "❌ environments/backend-${ENV}.hcl introuvable — lancer d'abord :"
    echo "   make bootstrap-tfstate"
    echo "   cp environments/backend-${ENV}.hcl.example environments/backend-${ENV}.hcl  # puis éditer"
    exit 1
  fi
  (cd "$TF_DIR" && terraform init -input=false -backend-config="../../environments/backend-${ENV}.hcl" >/dev/null)
  (cd "$TF_DIR" && terraform apply -auto-approve -input=false -var-file="../../environments/${ENV}.tfvars")
else
  step "1/7 — Infrastructure Terraform (--skip-infra, réutilisation)"
fi

RG=$(cd "$TF_DIR" && terraform output -raw resource_group_name)
WORKSPACE=$(cd "$TF_DIR" && terraform output -raw workspace_name)
ACR=$(cd "$TF_DIR" && terraform output -raw container_registry_name)
echo "✅ RG=$RG  Workspace=$WORKSPACE  ACR=$ACR"

step "2/7 — Extension Azure CLI 'ml'"
az extension add -n ml -y --only-show-errors >/dev/null 2>&1 || true
echo "✅ Extension ml prête"

step "3/7 — Compute cluster ($COMPUTE_NAME)"
if az ml compute show --name "$COMPUTE_NAME" --resource-group "$RG" --workspace-name "$WORKSPACE" >/dev/null 2>&1; then
  echo "✅ Déjà existant"
else
  az ml compute create --file ml/compute/compute-cluster.yml \
    --resource-group "$RG" --workspace-name "$WORKSPACE"
fi

step "4/7 — Environnement d'entraînement ($ENV_NAME)"
az ml environment create --file ml/environments/training-environment.yml \
  --resource-group "$RG" --workspace-name "$WORKSPACE" >/dev/null
echo "✅ Environnement enregistré (nouvelle version si conda.yml a changé)"

step "5/7 — Accès du compute à l'ACR (images Docker)"
# Le seul rôle dont le compute peut avoir besoin : register_model n'appelle
# plus le SDK (l'enregistrement est fait par Azure ML via la sortie nommée du
# pipeline), donc plus besoin de "AzureML Data Scientist".
if [[ "$(az acr show --name "$ACR" --resource-group "$RG" --query adminUserEnabled -o tsv)" == "true" ]]; then
  # Mode sans RBAC (enable_rbac_assignments = false dans les tfvars) : Azure ML
  # récupère les images avec le compte admin de l'ACR, aucun rôle à attribuer.
  # Ce mode permet de déployer avec le seul rôle Contributor sur le RG.
  echo "✅ Compte admin de l'ACR activé : aucun rôle à attribuer"
else
  COMPUTE_PRINCIPAL_ID=$(az ml compute show --name "$COMPUTE_NAME" \
    --resource-group "$RG" --workspace-name "$WORKSPACE" \
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

step "6/7 — Data asset ($DATA_NAME)"
az ml data create --file ml/data/sample-data-asset.yml \
  --resource-group "$RG" --workspace-name "$WORKSPACE" >/dev/null 2>&1 || \
  echo "ℹ️  Déjà enregistré (une version existe déjà)"

step "7/7 — Soumission du pipeline d'entraînement"
JOB_NAME=$(az ml job create --file ml/pipelines/training-pipeline.yml \
  --resource-group "$RG" --workspace-name "$WORKSPACE" \
  --query name -o tsv)

STUDIO_URL="https://ml.azure.com/runs/${JOB_NAME}?wsid=/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RG}/workspaces/${WORKSPACE}"
echo ""
echo "🎉 Pipeline soumis : $JOB_NAME"
echo "🔗 Suivre le run dans Azure ML Studio : $STUDIO_URL"
echo ""
echo "Streamer les logs en direct :"
echo "  az ml job stream --name $JOB_NAME --resource-group $RG --workspace-name $WORKSPACE"
