# ============================================================================
# Azure Resource Group
# ============================================================================
# Conteneur logique pour toutes les ressources du projet.
# 
# Convention de nommage : rg-{project}-{environment}-{suffix}
# Exemple : rg-aml-fraud-detection-dev-x7p2k9

resource "azurerm_resource_group" "rg" {
  # Nom unique du Resource Group
  name = "rg-${local.resource_prefix}-${local.suffix}"

  # Région Azure
  location = var.location

  # Tags pour suivi et gestion
  tags = local.common_tags
}
