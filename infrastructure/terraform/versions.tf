# ============================================================================
# Terraform Configuration & Required Providers
# ============================================================================
# Ce fichier définit la version de Terraform et les providers utilisés.
# Ne pas modifier sauf si vous connaissez les implications.

terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State distant (recommandé Microsoft/HashiCorp dès qu'il y a plus d'un
  # poste ou une CI impliqués — sans ça, chaque `terraform init` en CI part
  # d'un state vide sur un runner éphémère et recrée des ressources en
  # doublon au lieu de mettre à jour l'existant). Configuration partielle
  # (obligatoire : les blocs `backend` n'acceptent pas de variables) —
  # valeurs réelles injectées via `-backend-config=<fichier>.hcl`, voir
  # `make tf-init ENV=dev` et environments/backend-<env>.hcl.example.
  # Storage account de state à provisionner une seule fois via
  # `make bootstrap-tfstate` (infrastructure/terraform/README.md).
  backend "azurerm" {}
}
