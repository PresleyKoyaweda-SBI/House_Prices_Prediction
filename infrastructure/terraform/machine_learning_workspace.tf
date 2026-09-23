# ============================================================================
# Azure Machine Learning Workspace - Cœur du projet ML
# ============================================================================
# Ressource principale pour entraîner, déployer et gérer les modèles ML.
# Contient : datasets, models, experiments, pipelines, endpoints.
# Convention de nommage : mlw-{project}-{environment}-{suffix}
# Exemple : mlw-aml-fraud-detection-dev-x7p2k9

resource "azurerm_machine_learning_workspace" "aml" {
  # Nom du workspace
  name = "mlw-${local.resource_prefix}-${local.suffix}"

  # Localisation
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Services associés (lien avec ressources de support)

  # Application Insights : logs et monitoring
  application_insights_id = azurerm_application_insights.appi.id

  # Key Vault : gestion sécurisée des secrets
  key_vault_id = azurerm_key_vault.kv.id

  # Storage Account : stockage des données et modèles
  storage_account_id = azurerm_storage_account.storage.id

  # Container Registry : stockage des images Docker
  container_registry_id = azurerm_container_registry.acr.id

  # =========================================================================
  # Managed Identity - Authentification sécurisée sans secrets
  # =========================================================================
  # SystemAssigned : une identité unique par workspace
  # Permet à ML Workspace d'accéder aux autres services sans username/password
  identity {
    type = "SystemAssigned"
  }

  # Tags pour suivi
  tags = local.common_tags

  # Dépendances explicites pour ordre de création correct
  depends_on = [
    azurerm_resource_group.rg,
    azurerm_storage_account.storage,
    azurerm_key_vault.kv,
    azurerm_container_registry.acr,
    azurerm_application_insights.appi
  ]
}

# ============================================================================
# RBAC Role Assignments - Permissions pour Managed Identity
# ============================================================================
# Assigne les rôles nécessaires à la Managed Identity du workspace
# pour accéder aux autres services Azure.

# =========================================================================
# Rôle 1 : Storage Blob Data Contributor
# =========================================================================
# Permet au workspace d'accéder aux données dans Storage Account
# (read/write sur les conteneurs datasets, models, artifacts)

resource "azurerm_role_assignment" "aml_storage" {
  # Portée : le Storage Account complet
  scope = azurerm_storage_account.storage.id

  # Rôle : collaborateur données blob
  role_definition_name = "Storage Blob Data Contributor"

  # Principal : la Managed Identity du workspace
  principal_id = azurerm_machine_learning_workspace.aml.identity[0].principal_id
}

# =========================================================================
# Rôle 2 : AcrPull
# =========================================================================
# Permet au workspace de pull les images Docker du Container Registry
# Nécessaire pour utiliser des images Docker dans les pipelines

resource "azurerm_role_assignment" "aml_acr" {
  # Portée : le Container Registry complet
  scope = azurerm_container_registry.acr.id

  # Rôle : pull images ACR
  role_definition_name = "AcrPull"

  # Principal : la Managed Identity du workspace
  principal_id = azurerm_machine_learning_workspace.aml.identity[0].principal_id
}

# =========================================================================
# Rôle 3 : Key Vault Secrets User
# =========================================================================
# Permet au workspace de lire les secrets du Key Vault
# Nécessaire pour accéder aux clés API et autres secrets

resource "azurerm_role_assignment" "aml_keyvault" {
  # Portée : le Key Vault complet
  scope = azurerm_key_vault.kv.id

  # Rôle : accès aux secrets du Key Vault
  role_definition_name = "Key Vault Secrets User"

  # Principal : la Managed Identity du workspace
  principal_id = azurerm_machine_learning_workspace.aml.identity[0].principal_id
}
