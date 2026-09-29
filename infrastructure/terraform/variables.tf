# ============================================================================
# Input Variables - Variables d'entrée du projet
# ============================================================================
# À configurer dans terraform.tfvars ou via -var en ligne de commande.

# ============================================================================
# VARIABLES PRINCIPALES
# ============================================================================

variable "location" {
  description = "Région Azure pour le déploiement (ex: canadacentral, eastus, westeurope)"
  type        = string
  default     = "canadacentral"

  validation {
    condition     = contains(["canadacentral", "eastus", "westeurope", "southcentralus", "ukwest", "australiaeast"], var.location)
    error_message = "Région non valide. Régions supportées : canadacentral, eastus, westeurope, southcentralus, ukwest, australiaeast."
  }
}

variable "project_name" {
  # TEMPLATE: customize for client — remplacer par le nom kebab-case du projet client
  description = "Nom du projet (utilisé pour nommer les ressources). Format: kebab-case (ex: mon-projet-ml)"
  type        = string
  default     = "house-price"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.project_name))
    error_message = "Le nom doit être en kebab-case (minuscules, chiffres, tirets uniquement)."
  }
  # Les limites de longueur des noms Azure (storage account et Key Vault : 24,
  # workspace ML : 33) sont vérifiées nom par nom, voir local.name_length_checks.
}

variable "environment" {
  description = "Environnement de déploiement : dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environnement invalide. Doit être : dev, staging ou prod."
  }
}

variable "existing_resource_group_name" {
  description = "Nom du Resource Group existant (provisionné hors Terraform) à utiliser au lieu d'en créer un nouveau."
  type        = string
  default     = "AZ_RSG_CAN_AZURE-ML-PLATFORM-TEMPLATE"
}

variable "enable_rbac_assignments" {
  # TEMPLATE: customize for client
  description = <<-EOT
    true (défaut du starter kit) : Terraform crée les attributions de rôles Azure (RBAC) pour le
    workspace ML (Storage Blob Data Contributor, AcrPull, Key Vault Secrets User) et pour
    l'utilisateur (Key Vault Administrator). Nécessite Owner, User Access Administrator ou
    Role Based Access Control Administrator sur le resource group.
    false : aucune attribution de rôle n'est créée, pour un déploiement avec le seul rôle
    Contributor. Le Key Vault passe en access policies, et l'ACR doit alors avoir admin_enabled = true
    (voir container_registry_config) pour que les clusters Azure ML puissent récupérer leurs images.
  EOT
  type        = bool
  default     = true
}

# ============================================================================
# TAGS - Balises appliquées à TOUTES les ressources
# ============================================================================

variable "tags" {
  description = "Tags Azure appliqués à toutes les ressources pour suivi et facturation"
  type        = map(string)
  default = {
    ManagedBy  = "Terraform"
    CostCenter = "AI"
    Department = "DataScience"
  }
}

# ============================================================================
# STORAGE ACCOUNT - Configuration personnalisée (optionnel)
# ============================================================================

variable "storage_account_config" {
  description = "Configuration du Storage Account (tier, replication, access tier)"
  type = object({
    account_tier             = string # Standard ou Premium
    account_replication_type = string # LRS, GRS, RA-GRS, etc
    access_tier              = string # Hot ou Cool
  })
  default = {
    account_tier             = "Standard"
    account_replication_type = "LRS"
    access_tier              = "Hot"
  }
}

# ============================================================================
# CONTAINER REGISTRY - Configuration personnalisée (optionnel)
# ============================================================================

variable "container_registry_config" {
  description = "Configuration de l'Azure Container Registry (SKU et accès admin)"
  type = object({
    sku           = string # Basic, Standard ou Premium
    admin_enabled = bool   # Activer accès admin (username/password)
  })
  default = {
    sku = "Basic"
    # false par défaut : le workspace ML accède déjà à l'ACR via son
    # Managed Identity (rôle AcrPull, voir machine_learning_workspace.tf).
    # TEMPLATE: optional — passer à true seulement si un outil tiers a besoin
    # d'un `docker login` avec identifiants admin (déconseillé, surtout en prod).
    admin_enabled = false
  }

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_config.sku)
    error_message = "SKU invalide. Doit être : Basic, Standard ou Premium."
  }
}
