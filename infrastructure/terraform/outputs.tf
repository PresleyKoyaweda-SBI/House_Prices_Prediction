# ============================================================================
# Terraform Outputs - Informations de sortie après déploiement
# ============================================================================
# Affichés après terraform apply
# Utilisés pour configuration des applications et documentation

# ============================================================================
# RESOURCE GROUP
# ============================================================================

output "resource_group_name" {
  description = "Nom du Resource Group"
  value       = azurerm_resource_group.rg.name
}

output "resource_group_id" {
  description = "ID complet du Resource Group"
  value       = azurerm_resource_group.rg.id
}

# ============================================================================
# STORAGE ACCOUNT
# ============================================================================

output "storage_account_name" {
  description = "Nom du Storage Account (à utiliser pour les connexions)"
  value       = azurerm_storage_account.storage.name
}

output "storage_account_id" {
  description = "ID complet du Storage Account"
  value       = azurerm_storage_account.storage.id
}

output "storage_primary_blob_endpoint" {
  description = "URL d'accès principal aux blobs (pour SDK Azure)"
  value       = azurerm_storage_account.storage.primary_blob_endpoint
}

# ============================================================================
# CONTAINER REGISTRY
# ============================================================================

output "container_registry_name" {
  description = "Nom du Container Registry (pour docker login)"
  value       = azurerm_container_registry.acr.name
}

output "container_registry_id" {
  description = "ID complet du Container Registry"
  value       = azurerm_container_registry.acr.id
}

output "container_registry_login_server" {
  description = "URL du serveur login ACR (ex: acrxxxx.azurecr.io)"
  value       = azurerm_container_registry.acr.login_server
}

output "container_registry_admin_username" {
  description = "Nom d'utilisateur admin du Container Registry (si admin_enabled=true)"
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Mot de passe admin du Container Registry (si admin_enabled=true)"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

# ============================================================================
# KEY VAULT
# ============================================================================

output "key_vault_name" {
  description = "Nom du Key Vault (pour accès par API)"
  value       = azurerm_key_vault.kv.name
}

output "key_vault_id" {
  description = "ID complet du Key Vault"
  value       = azurerm_key_vault.kv.id
}

output "key_vault_uri" {
  description = "URI du Key Vault (pour SDK Azure)"
  value       = azurerm_key_vault.kv.vault_uri
}

# ============================================================================
# APPLICATION INSIGHTS
# ============================================================================

output "application_insights_name" {
  description = "Nom d'Application Insights"
  value       = azurerm_application_insights.appi.name
}

output "application_insights_id" {
  description = "ID complet d'Application Insights"
  value       = azurerm_application_insights.appi.id
}

output "application_insights_instrumentation_key" {
  description = "Clé d'instrumentation pour envoyer les logs (sensible)"
  value       = azurerm_application_insights.appi.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Chaîne de connexion pour SDK (sensible)"
  value       = azurerm_application_insights.appi.connection_string
  sensitive   = true
}

# ============================================================================
# ML WORKSPACE
# ============================================================================

output "workspace_name" {
  description = "Nom du Workspace Azure ML"
  value       = azurerm_machine_learning_workspace.aml.name
}

output "workspace_id" {
  description = "ID complet du Workspace Azure ML"
  value       = azurerm_machine_learning_workspace.aml.id
}

output "workspace_managed_identity_id" {
  description = "ID de la Managed Identity du Workspace (pour RBAC)"
  value       = azurerm_machine_learning_workspace.aml.identity[0].principal_id
}

# ============================================================================
# INFORMATIONS UTILES & RÉSUMÉS
# ============================================================================

output "deployment_summary" {
  description = "Résumé du déploiement (projet, environnement, etc)"
  value = {
    project             = var.project_name
    environment         = var.environment
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
    workspace_name      = azurerm_machine_learning_workspace.aml.name
    random_suffix       = local.suffix
  }
}

output "connection_strings" {
  description = "Informations de connexion pour les applications (sensible)"
  value = {
    storage_blob_endpoint     = azurerm_storage_account.storage.primary_blob_endpoint
    container_registry_server = azurerm_container_registry.acr.login_server
    key_vault_url             = azurerm_key_vault.kv.vault_uri
  }
  sensitive = false
}
