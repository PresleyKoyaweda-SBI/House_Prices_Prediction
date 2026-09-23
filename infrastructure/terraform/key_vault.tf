# ============================================================================
# Azure Key Vault - Gestion sécurisée des secrets
# ============================================================================
# Stocke les clés API, mots de passe, certificats et secrets.
# Convention de nommage : kv{project}{suffix}
# Exemple : kvfrauddetectionx7p2k9

resource "azurerm_key_vault" "kv" {
  # Nom unique (3-24 caractères, alphanumériques + tirets)
  name = "kv${local.project_name_short}${local.suffix}"

  # Localisation
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Tenant ID Azure (propriétaire du Key Vault)
  tenant_id = data.azurerm_client_config.current.tenant_id

  # SKU (Standard ou Premium)
  # Standard : fonctionnalités de base
  # Premium : protection matérielle HSM
  sku_name = "standard"

  # RBAC authorization (recommandé, sécurisé)
  # Alternative : access policies (ancien modèle)
  rbac_authorization_enabled = true

  # Protection contra la suppression accidentelle
  # dev : false (suppression facile)
  # prod : true (suppression nécessite 7 jours minimum)
  purge_protection_enabled = var.environment == "prod" ? true : false

  # Récupération douce : 7 jours avant suppression complète
  soft_delete_retention_days = 7

  # Tags pour suivi
  tags = local.common_tags
}

# ============================================================================
# RBAC Role Assignment - Administrateur Key Vault
# ============================================================================
# Assigne le rôle "Key Vault Administrator" à l'utilisateur actuel.
# Permet de gérer les secrets dans le portail Azure.

resource "azurerm_role_assignment" "kv_admin" {
  # Portée : le Key Vault complet
  scope = azurerm_key_vault.kv.id

  # Rôle administrateur du Key Vault
  role_definition_name = "Key Vault Administrator"

  # Principal : utilisateur actuel qui exécute terraform
  principal_id = data.azurerm_client_config.current.object_id
}
