# ============================================================================
# Azure Provider Configuration
# ============================================================================
# Configure l'accès à Azure et les comportements par défaut.

provider "azurerm" {
  features {
    # Configuration Key Vault : soft delete + purge
    key_vault {
      purge_soft_delete_on_destroy = var.environment == "dev" ? true : false
    }
  }
}

# ============================================================================
# Current Azure Context
# ============================================================================
# Récupère les informations de l'utilisateur/subscription actuelle.

data "azurerm_client_config" "current" {}
