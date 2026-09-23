# Terraform

Infrastructure Azure de base : Resource Group, Storage Account, Key Vault,
Container Registry, Application Insights, ML Workspace — voir
[docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) pour le détail des
ressources et des permissions RBAC.

## State distant (obligatoire avant le premier `terraform init`)

Le state Terraform est stocké dans Azure Storage, pas en local — sans ça,
chaque exécution en CI partirait d'un state vide et recréerait des
ressources en doublon au lieu de mettre à jour l'existant (pattern
[documenté par Microsoft](https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage)).
Une seule fois par client/tenant :

```bash
make bootstrap-tfstate
```

Provisionne un storage account dédié (versioning + soft delete des blobs
activés, hors Terraform — problème de l'œuf et de la poule) et affiche les
prochaines étapes : créer `environments/backend-<env>.hcl` à partir du
`.hcl.example` correspondant, accorder le rôle `Storage Blob Data
Contributor` sur ce storage account à chaque identité qui exécutera
Terraform (utilisateur local + identité OIDC en CI/CD — voir
[docs/SECURITY.md](../../docs/SECURITY.md)).

## Commandes

```bash
make tf-init ENV=dev
make tf-plan ENV=dev
make tf-apply ENV=dev     # ou ENV=staging / ENV=prod
make tf-output
```

Équivalent direct (sans Makefile) :
```bash
terraform init -backend-config=../../environments/backend-dev.hcl
terraform plan -var-file=../../environments/dev.tfvars
terraform apply -var-file=../../environments/dev.tfvars
```

## Personnalisation

Voir [docs/CUSTOMIZATION_GUIDE.md](../../docs/CUSTOMIZATION_GUIDE.md),
sections 1 à 6 et 16 à 18 (nom du projet, région, nommage, tags,
environnements, RBAC, monitoring).

## Destruction

```bash
./scripts/destroy.sh
```
Sauvegarde les outputs, affiche le plan de destruction, puis demande une
double confirmation avant `terraform destroy`.
