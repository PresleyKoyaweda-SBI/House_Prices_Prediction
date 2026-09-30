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
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  # Tenant ID Azure (propriétaire du Key Vault)
  tenant_id = data.azurerm_client_config.current.tenant_id

  # SKU (Standard ou Premium)
  # Standard : fonctionnalités de base
  # Premium : protection matérielle HSM
  sku_name = "standard"

  # RBAC authorization (recommandé, sécurisé) si les attributions de rôles sont
  # autorisées ; sinon access policies (ancien modèle), gérables avec le seul
  # rôle Contributor (voir var.enable_rbac_assignments).
  rbac_authorization_enabled = var.enable_rbac_assignments

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
  count = var.enable_rbac_assignments ? 1 : 0

  # Portée : le Key Vault complet
  scope = azurerm_key_vault.kv.id

  # Rôle administrateur du Key Vault
  role_definition_name = "Key Vault Administrator"

  # Principal : utilisateur actuel qui exécute terraform
  principal_id = data.azurerm_client_config.current.object_id
}

# ============================================================================
# Access policy - Utilisateur courant (mode sans RBAC)
# ============================================================================
# Équivalent de "Key Vault Administrator" quand var.enable_rbac_assignments = false :
# permet à l'identité qui exécute terraform de gérer les secrets.
#
# Ressource séparée (et non bloc access_policy dans azurerm_key_vault) : Azure ML
# ajoute lui-même une access policy pour l'identité du workspace à sa création.
# Un bloc inline ferait considérer cette policy comme une dérive à supprimer au
# prochain apply, ce qui couperait l'accès du workspace à ses secrets.

resource "azurerm_key_vault_access_policy" "current_user" {
  count = var.enable_rbac_assignments ? 0 : 1

  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge",
  ]
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Backup", "Restore", "Purge",
  ]
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Backup", "Restore", "Purge",
  ]
}
