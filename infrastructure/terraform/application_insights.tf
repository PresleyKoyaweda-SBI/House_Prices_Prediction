# ============================================================================
# Azure Application Insights - Monitoring et observabilité
# ============================================================================
# Collecte les logs, métriques et traces des applications/pipelines.
# Permet le diagnostic et l'analyse des performances.
# Convention de nommage : appi-{project}-{environment}-{suffix}
# Exemple : appi-aml-fraud-detection-dev-x7p2k9

resource "azurerm_application_insights" "appi" {
  # Nom de la ressource Application Insights
  name = "appi-${local.resource_prefix}-${local.suffix}"

  # Localisation
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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
