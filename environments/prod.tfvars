# =============================================================================
# Environnement PROD — haute disponibilité, sécurité renforcée
# =============================================================================
# Usage : terraform plan -var-file=../../environments/prod.tfvars
# Rappel : la promotion vers prod doit passer par une approbation manuelle
# (voir .github/workflows/cd.yml et docs/MLOPS_LIFECYCLE.md).

# TEMPLATE: customize for client
location     = "eastus"
project_name = "mon-projet-ml"
environment  = "prod"

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
  access_tier              = "Hot"
}

container_registry_config = {
  sku           = "Standard" # TEMPLATE: optional — Premium si geo-replication ACR requise
  admin_enabled = false      # jamais d'identifiants admin en prod
}
