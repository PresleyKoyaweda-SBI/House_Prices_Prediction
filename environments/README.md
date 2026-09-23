# Environnements

Un seul fichier `.tfvars` par environnement de déploiement. Le code Terraform
(dans `infrastructure/terraform/`) reste identique entre environnements — seules
ces valeurs changent.

Ce dossier contient aussi `backend-{dev,staging,prod}.hcl.example` — la
configuration du **backend distant** (state Terraform, pas les ressources
applicatives). Ne pas confondre : un `.tfvars` décrit *ce que Terraform
déploie*, un `backend-*.hcl` décrit *où Terraform stocke son state*. Voir
`infrastructure/terraform/README.md` pour le détail (`make
bootstrap-tfstate`). Les fichiers `backend-*.hcl` réels (sans `.example`,
avec les vraies valeurs client) ne sont jamais versionnés (`.gitignore`).

| Fichier | Environnement | Différences clés |
|---|---|---|
| `dev.tfvars` | Développement | LRS, ACR Basic, itération rapide |
| `staging.tfvars` | Pré-production | GRS, ACR Standard |
| `prod.tfvars` | Production | GRS, tags renforcés, admin ACR désactivé |

## Utilisation

```bash
cd infrastructure/terraform
terraform plan  -var-file=../../environments/dev.tfvars
terraform apply -var-file=../../environments/dev.tfvars
```

Ou via le Makefile : `make deploy-dev`, `make deploy-staging`, `make deploy-prod`.

## Ne pas confondre avec `ml/environments/`

- **`environments/*.tfvars`** (ce dossier) : paramètres d'infrastructure par
  étape de déploiement (dev/staging/prod).
- **`ml/environments/*.yml`** : définitions d'environnement d'exécution Azure ML
  CLI v2 (dépendances conda + image Docker) pour les jobs et composants.

Ce sont deux notions distinctes qui portent le même mot « environnement ».
