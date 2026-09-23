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
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

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
  public_network_access_enabled = var.environment != "prod" ? true : false

  # Tags pour suivi
  tags = local.common_tags
}
