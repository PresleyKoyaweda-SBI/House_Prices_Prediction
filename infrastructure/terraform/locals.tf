# ============================================================================
# Random Suffix - Unicité des noms
# ============================================================================
# Génère un suffix aléatoire (local.suffix_length caractères) pour assurer l'unicité des noms.
# Les noms Azure doivent être globalement uniques.

resource "random_string" "suffix" {
  length  = local.suffix_length
  upper   = false # Minuscules uniquement
  numeric = true  # Inclure les chiffres
  special = false # Pas de caractères spéciaux

  lifecycle {
    # Contrôle des longueurs de noms : évalué dès `terraform plan`, sur la première
    # ressource créée. Échoue avec un message qui dit quoi raccourcir, plutôt
    # qu'un refus d'Azure au milieu de l'apply, une fois une partie des
    # ressources déjà créée.
    precondition {
      condition = alltrue([for c in values(local.name_length_checks) : c.length <= c.max])
      error_message = format(
        "Nom(s) trop long(s) pour Azure avec project_name = \"%s\" et environment = \"%s\" : %s. Raccourcir project_name.",
        var.project_name,
        var.environment,
        join(", ", [for k, c in local.name_length_checks : "${k} = ${c.length} caractères (max ${c.max})" if c.length > c.max])
      )
    }
  }
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

  # Suffix aléatoire pour unicité. 4 caractères (36^4 ≈ 1,7 million de
  # combinaisons) suffisent à éviter les collisions de noms et laissent de la
  # place au nom du projet dans les limites de longueur Azure.
  # Exemple: x7p2
  suffix_length = 4
  suffix        = random_string.suffix.result

  # Longueur des noms générés, comparée aux limites Azure. Calculée avec la
  # longueur du suffixe plutôt qu'avec sa valeur : elle est ainsi connue dès le
  # plan, avant toute création de ressource (voir la precondition de
  # random_string.suffix).
  name_length_checks = {
    storage_account    = { length = length("st${local.project_name_short}") + local.suffix_length, max = 24 }
    key_vault          = { length = length("kv${local.project_name_short}") + local.suffix_length, max = 24 }
    container_registry = { length = length("acr${local.project_name_short}") + local.suffix_length, max = 50 }
    ml_workspace       = { length = length("mlw-${local.resource_prefix}-") + local.suffix_length, max = 33 }
  }

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
