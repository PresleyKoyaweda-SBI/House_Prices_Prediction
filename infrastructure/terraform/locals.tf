# ============================================================================
# Random Suffix - Unicité des noms
# ============================================================================
# Génère un suffix aléatoire (6 caractères) pour assurer l'unicité des noms.
# Les noms Azure doivent être globalement uniques.

resource "random_string" "suffix" {
  length  = 6
  upper   = false # Minuscules uniquement
  numeric = true  # Inclure les chiffres
  special = false # Pas de caractères spéciaux
}

# ============================================================================
# Local Values - Valeurs calculées réutilisables
# ============================================================================
# Définit des valeurs utilisées dans tous les fichiers de ressources.

locals {
  # Nom court du projet (sans tirets) - utilisé pour les noms Azure
  # Exemple: "fraud-detection" → "frauddetection"
  project_name_short = replace(var.project_name, "-", "")

  # Préfixe pour la plupart des ressources
  # Format: aml-{project}-{environment}
  # Exemple: aml-fraud-detection-dev
  resource_prefix = "aml-${var.project_name}-${var.environment}"

  # Suffix aléatoire pour unicité (6 caractères)
  # Exemple: x7p2k9
  suffix = random_string.suffix.result

  # Tags communs appliqués à TOUTES les ressources
  # Permet un suivi centralisé et une gestion des coûts
  #
  # Pourquoi pas de tag "CreatedAt" ici : timestamp() se réévalue à CHAQUE
  # plan/apply et provoquerait un diff Terraform permanent sur toutes les
  # ressources (non-idempotent). La date de création réelle reste consultable
  # nativement dans Azure Portal / Activity Log si besoin.
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  )
}
