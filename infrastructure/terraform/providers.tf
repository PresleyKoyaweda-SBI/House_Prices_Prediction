# ============================================================================
# Azure Provider Configuration
# ============================================================================
# Configure l'accès à Azure et les comportements par défaut.

provider "azurerm" {
  # Par défaut, le provider tente d'enregistrer une liste de resource providers au
  # niveau de la SOUSCRIPTION, ce qui échoue quand les droits sont limités à un
  # resource group. Les providers utilisés ici (MachineLearningServices, Storage,
  # KeyVault, ContainerRegistry, Insights, OperationalInsights) doivent donc être
  # déjà enregistrés — vérifier avec :
  #   az provider show -n Microsoft.MachineLearningServices --query registrationState
  resource_provider_registrations = "none"

  features {
    # Configuration Key Vault : soft delete + purge
    #
    # La purge automatique à la destruction exige le droit
    # Microsoft.KeyVault/locations/deletedVaults/purge/action au niveau de
    # l'ABONNEMENT — hors de portée du rôle Contributor limité à ce RG (voir
    # l'erreur 403 rencontrée). Désactivée pour les deux environnements : un
    # `terraform destroy` supprime le Key Vault (suppression douce), et Azure
    # le purge tout seul après soft_delete_retention_days (voir key_vault.tf).
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# ============================================================================
# Current Azure Context
# ============================================================================
# Récupère les informations de l'utilisateur/subscription actuelle.

data "azurerm_client_config" "current" {}