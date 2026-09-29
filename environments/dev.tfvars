# =============================================================================
# Environnement DEV — coûts bas, itération rapide
# =============================================================================
# Usage : terraform plan -var-file=../../environments/dev.tfvars
# (depuis infrastructure/terraform/), ou via `make tf-plan ENV=dev`

# TEMPLATE: customize for client
location     = "canadacentral"
project_name = "house-price"
environment  = "dev"

# Resource group existant, fourni par l'équipe IT (Terraform ne le crée pas).
existing_resource_group_name = "AZ_RSG_CAN_AZURE-ML-PLATFORM-TEMPLATE"

# Droits limités au rôle Contributor sur ce RG : pas d'attribution de rôles
# Azure (RBAC). Key Vault en access policies, ACR en compte admin (ci-dessous).
# Repasser à true dès qu'un rôle permettant les attributions est accordé.
enable_rbac_assignments = false

tags = {
  ManagedBy  = "Terraform"
  CostCenter = "AI"
  Department = "DataScience"
  Stage      = "experimental"
}

storage_account_config = {
  account_tier             = "Standard"
  account_replication_type = "LRS" # réplication locale : suffisant en dev
  access_tier              = "Hot"
}

container_registry_config = {
  sku = "Basic"
  # true car enable_rbac_assignments = false : sans rôle AcrPull, Azure ML ne peut
  # récupérer les images d'environnement qu'avec le compte admin de l'ACR.
  admin_enabled = true
}
