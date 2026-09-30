# ============================================================================
# Azure Container Registry (ACR) - Stockage d'images Docker
# ============================================================================
# Stocke les images Docker utilisées par les pipelines ML et les endpoints.
# Convention de nommage : acr{project}{suffix}
# Exemple : acrfrauddetectionx7p2k9

resource "azurerm_container_registry" "acr" {
  # Nom unique (5-50 caractères, alphanumériques uniquement)
  name = "acr${local.project_name_short}${local.suffix}"

  # Localisation
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  # SKU (Basic, Standard, Premium)
  # Basic   : dev/test, compression minimale
  # Standard: production, performances correctes
  # Premium : très haute disponibilité, geo-replication
  sku = var.container_registry_config.sku

  # Accès admin (username/password)
  # À décommenter SEULEMENT si nécessaire (moins sécurisé)
  # Recommandation : utiliser Managed Identity
  admin_enabled = var.container_registry_config.admin_enabled

  # Accès réseau public
  # dev/staging : true (accès depuis n'importe où)
  # prod       : false + connexion via Private Link
  # public_network_access_enabled = var.environment != "prod" ? true : false
  public_network_access_enabled = var.container_registry_config.sku == "Premium" ? false : true

  # Tags pour suivi
  tags = local.common_tags

  lifecycle {
    # Sans attribution de rôle AcrPull (var.enable_rbac_assignments = false), le
    # workspace et ses clusters ne peuvent récupérer les images d'environnement
    # qu'avec le compte admin de l'ACR.
    precondition {
      condition     = var.enable_rbac_assignments || var.container_registry_config.admin_enabled
      error_message = "enable_rbac_assignments = false exige container_registry_config.admin_enabled = true (sinon Azure ML ne peut pas récupérer ses images)."
    }
  }
}
