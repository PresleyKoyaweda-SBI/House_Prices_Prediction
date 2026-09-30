#!/bin/bash
set -euo pipefail

# Bootstrap du storage account de state Terraform.
#
# Pattern documenté par Microsoft pour stocker le state Terraform dans Azure
# Storage (https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage) :
# un storage account dédié, provisionné hors Terraform (problème de l'œuf et
# de la poule — le state ne peut pas se stocker lui-même), un seul par
# client/tenant, partagé par les 3 environnements (dev/staging/prod), chacun
# avec son propre blob (`key`) dans le même conteneur.
#
# À exécuter UNE SEULE FOIS par client/tenant, avant le tout premier
# `make tf-init`. Idempotent : peut être relancé sans échouer.
#
# Usage :
#   ./scripts/bootstrap-tfstate.sh [project_name]   (défaut : lu depuis
#                                                      environments/dev.tfvars)

PROJECT_NAME="${1:-$(grep -m1 '^project_name' environments/dev.tfvars | sed -E 's/.*"(.*)".*/\1/')}"
PROJECT_SHORT=$(echo "$PROJECT_NAME" | tr -d '-')
SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$RANDOM")

RG="rg-tfstate-${PROJECT_NAME}"
SA="sttfstate${PROJECT_SHORT}${SUFFIX}"
CONTAINER="tfstate"
LOCATION="${LOCATION:-canadacentral}"

step() { echo ""; echo "▶ $1"; echo "----------------------------------------"; }

step "0/4 — Vérification az login"
az account show >/dev/null 2>&1 || {
  echo "❌ Non connecté. Lancer 'az login' d'abord."
  exit 1
}

step "1/4 — Resource group ($RG)"
if az group show --name "$RG" >/dev/null 2>&1; then
  echo "✅ Déjà existant"
else
  az group create --name "$RG" --location "$LOCATION" >/dev/null
  echo "✅ Créé"
fi

step "2/4 — Storage account ($SA)"
if az storage account show --name "$SA" --resource-group "$RG" >/dev/null 2>&1; then
  echo "✅ Déjà existant"
else
  # Best practice Microsoft : TLS 1.2 minimum, pas d'accès blob public,
  # réplication LRS suffisante pour un state (le versioning ci-dessous
  # protège déjà contre une corruption/suppression accidentelle).
  az storage account create \
    --name "$SA" --resource-group "$RG" --location "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --allow-blob-public-access false >/dev/null
  echo "✅ Créé"
fi

step "3/4 — Versioning + soft delete sur les blobs"
az storage account blob-service-properties update \
  --account-name "$SA" --resource-group "$RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30 >/dev/null
echo "✅ Activés (protège le state contre une corruption/suppression accidentelle)"

step "4/4 — Container ($CONTAINER)"
if az storage container show --name "$CONTAINER" --account-name "$SA" --auth-mode login >/dev/null 2>&1; then
  echo "✅ Déjà existant"
else
  az storage container create --name "$CONTAINER" --account-name "$SA" --auth-mode login >/dev/null
  echo "✅ Créé"
fi

echo ""
echo "🎉 Storage de state prêt : $SA / $CONTAINER (resource group $RG)"
echo ""
echo "Prochaine étape — pour CHAQUE environnement (dev/staging/prod) :"
echo "  1. cp environments/backend-<env>.hcl.example environments/backend-<env>.hcl"
echo "  2. Remplacer resource_group_name/storage_account_name par :"
echo "       resource_group_name  = \"$RG\""
echo "       storage_account_name = \"$SA\""
echo "  3. Accorder le rôle 'Storage Blob Data Contributor' sur ce storage account"
echo "     à chaque identité qui exécutera terraform (votre compte az login,"
echo "     et l'identité fédérée OIDC utilisée en CI/CD — voir docs/SECURITY.md) :"
echo "       az role assignment create --assignee-object-id <object-id> \\"
echo "         --assignee-principal-type <User|ServicePrincipal> \\"
echo "         --role \"Storage Blob Data Contributor\" \\"
echo "         --scope \$(az storage account show --name $SA --resource-group $RG --query id -o tsv)"
echo "  4. make tf-init ENV=<env>"
