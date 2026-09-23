# =============================================================================
# Environnement DEV — coûts bas, itération rapide
# =============================================================================
# Usage : terraform plan -var-file=../../environments/dev.tfvars
# (depuis infrastructure/terraform/), ou via `make tf-plan ENV=dev`

# TEMPLATE: customize for client
location     = "canadacentral"
project_name = "mon-projet-ml"
environment  = "dev"

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
  sku           = "Basic"
  admin_enabled = false
}
