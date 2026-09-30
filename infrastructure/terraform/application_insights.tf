# ============================================================================
# Azure Application Insights - Monitoring et observabilité
# ============================================================================
# Collecte les logs, métriques et traces des applications/pipelines.
# Permet le diagnostic et l'analyse des performances.
# Convention de nommage : appi-{project}-{environment}-{suffix}
# Exemple : appi-aml-fraud-detection-dev-x7p2k9

# ============================================================================
# Log Analytics Workspace - Stockage des données d'Application Insights
# ============================================================================
# Application Insights « classique » (sans workspace) n'est plus supporté par
# Azure : sans workspace_id explicite, Azure en crée un automatiquement dans un
# resource group séparé (DefaultResourceGroup-<région>), ce qui échoue quand les
# droits sont limités à un seul resource group. Je le crée donc explicitement
# dans le resource group du projet.
# Convention de nommage : log-{project}-{environment}-{suffix}

resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-${local.resource_prefix}-${local.suffix}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  # PerGB2018 : facturation à l'usage (seul SKU proposé pour les nouveaux workspaces)
  sku = "PerGB2018"

  # 30 jours : rétention minimale, alignée sur celle d'Application Insights
  retention_in_days = 30

  tags = local.common_tags
}

resource "azurerm_application_insights" "appi" {
  # Nom de la ressource Application Insights
  name = "appi-${local.resource_prefix}-${local.suffix}"

  # Localisation
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  # Workspace Log Analytics où sont stockées les données (voir ci-dessus)
  workspace_id = azurerm_log_analytics_workspace.log.id

  # Type d'application surveillée
  # "web" : pour API, web apps, services
  # "other" : pour applications custom
  application_type = "web"

  # Rétention des données (jours)
  # 30  : rétention minimale (moins cher)
  # 90  : par défaut (recommandé)
  # 730 : conservation maximale (2 ans)
  retention_in_days = 30

  # Tags pour suivi et gestion
  tags = local.common_tags
}
