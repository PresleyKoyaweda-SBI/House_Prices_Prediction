# =============================================================================
# Environnement STAGING — pré-production, proche de prod mais modéré
# =============================================================================
# Usage : terraform plan -var-file=../../environments/staging.tfvars

# TEMPLATE: customize for client
location     = "canadacentral"
project_name = "house-price"
environment  = "staging"

tags = {
  ManagedBy  = "Terraform"
  CostCenter = "AI"
  Department = "DataScience"
  Stage      = "pre-production"
}

storage_account_config = {
  account_tier             = "Standard"
  account_replication_type = "GRS" # réplication géographique
  access_tier              = "Hot"
}

container_registry_config = {
  sku           = "Standard"
  admin_enabled = false
}
