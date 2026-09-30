# ============================================================================
# Azure Resource Group — existant, provisionné hors Terraform
# ============================================================================
# Référence en lecture seule : ce RG a été créé par l'équipe IT (voir ticket
# d'accès). Terraform ne le crée ni ne le détruit — seulement les ressources
# à l'intérieur.

data "azurerm_resource_group" "rg" {
  name = var.existing_resource_group_name
}