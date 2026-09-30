# =============================================================================
# Environnement PROD — haute disponibilité, sécurité renforcée
# =============================================================================
# Usage : terraform plan -var-file=../../environments/prod.tfvars
# Rappel : la promotion vers prod doit passer par une approbation manuelle
# (voir .github/workflows/cd.yml et docs/MLOPS_LIFECYCLE.md).

# TEMPLATE: customize for client
location     = "canadacentral"
project_name = "house-price"
environment  = "prod"

# Droits limités au rôle Contributor sur ce RG : pas d'attribution de rôles
# Azure (RBAC). Key Vault en access policies, ACR en compte admin (ci-dessous).
# Repasser à true dès qu'un rôle permettant les attributions est accordé.
enable_rbac_assignments = false

tags = {
  ManagedBy       = "Terraform"
  CostCenter      = "AI"
  Department      = "DataScience"
  Stage           = "production"
  CriticalService = "true"
}

storage_account_config = {
  account_tier             = "Standard" # TEMPLATE: optional — Premium si latence/débit critiques
  account_replication_type = "GRS"      # toujours GRS en prod
  access_tier               = "Hot"
}

container_registry_config = {
  sku = "Standard" # TEMPLATE: optional — Premium si geo-replication ACR requise
  # true car enable_rbac_assignments = false : sans rôle AcrPull, Azure ML ne peut
  # récupérer les images d'environnement qu'avec le compte admin de l'ACR.
  admin_enabled = true
}