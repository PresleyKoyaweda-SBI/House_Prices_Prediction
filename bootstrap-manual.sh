#!/bin/bash
set -euo pipefail

RG="AZ_RSG_CAN_AZURE-ML-PLATFORM-TEMPLATE"
SA="sttfstatehpp01"
CONTAINER="tfstate"
LOCATION="canadacentral"

echo "RG=$RG SA=$SA CONTAINER=$CONTAINER LOCATION=$LOCATION"

az storage account create \
  --name "$SA" --resource-group "$RG" --location "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false

az storage account blob-service-properties update \
  --account-name "$SA" --resource-group "$RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30

az storage container create --name "$CONTAINER" --account-name "$SA" --auth-mode login

MY_ID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$MY_ID" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope $(az storage account show --name "$SA" --resource-group "$RG" --query id -o tsv)

echo "Bootstrap terminé."