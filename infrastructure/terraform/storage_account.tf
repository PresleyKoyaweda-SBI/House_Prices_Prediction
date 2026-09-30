# ============================================================================
# Azure Storage Account - Stockage principal du projet
# ============================================================================
# Stocke les datasets, modèles et artefacts ML.
# Convention de nommage : st{project}{suffix}
# Exemple : stfrauddetectionx7p2k9

resource "azurerm_storage_account" "storage" {
  # Nom unique (minuscules, chiffres uniquement, max 24 caractères)
  name = "st${local.project_name_short}${local.suffix}"

  # Localisation dans le Resource Group
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  # Tier de performance (Standard ou Premium)
  account_tier = var.storage_account_config.account_tier

  # Type de réplication (LRS, GRS, RA-GRS, GZRS, RA-GZRS)
  # LRS : réplication locale (moins cher, recommandé pour dev)
  # GRS : réplication géographique (recommandé pour prod)
  account_replication_type = var.storage_account_config.account_replication_type

  # Forcer HTTPS uniquement (recommandé pour sécurité)
  https_traffic_only_enabled = true

  # TLS 1.2 minimum — recommandation Microsoft Well-Architected Framework /
  # Azure Security Benchmark (Data Protection DP-3).
  min_tls_version = "TLS1_2"

  # Versioning + soft delete des blobs — protège les datasets/modèles contre
  # une suppression ou un écrasement accidentel (recommandation Microsoft
  # pour les storage accounts contenant des données de production).
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  # Tags pour suivi et gestion
  tags = local.common_tags
}

# ============================================================================
# Storage Containers - Conteneurs logiques dans le Storage Account
# ============================================================================

# Conteneur 1 : Datasets
# Stocke les données d'entraînement et de test
resource "azurerm_storage_container" "datasets" {
  name = "datasets"

  # Référence au Storage Account parent
  storage_account_id = azurerm_storage_account.storage.id

  # Accès privé (pas d'accès public)
  container_access_type = "private"
}

# Conteneur 2 : Models
# Stocke les modèles ML entraînés et versionnés
resource "azurerm_storage_container" "models" {
  name = "models"

  storage_account_id = azurerm_storage_account.storage.id

  container_access_type = "private"
}

# Conteneur 3 : Artifacts
# Stocke les artefacts de pipeline (logs, métriques, états)
resource "azurerm_storage_container" "artifacts" {
  name = "artifacts"

  storage_account_id = azurerm_storage_account.storage.id

  container_access_type = "private"
}
