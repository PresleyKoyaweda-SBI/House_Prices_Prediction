# Scripts

La plupart des opérations courantes (init/plan/apply Terraform, déploiement
par environnement, lint/tests) passent par le `Makefile` à la racine du
dépôt — voir `make help`.

Ce dossier ne contient que les scripts dont la logique ne se réduit pas à
une cible Makefile.

## `bootstrap-tfstate.sh` / `bootstrap-tfstate.ps1`

Provisionne le storage account dédié au state Terraform (versioning +
soft delete des blobs activés), hors Terraform — à exécuter **une seule
fois par client/tenant**, avant le tout premier `make tf-init`. Affiche en
fin d'exécution les valeurs à reporter dans
`environments/backend-{dev,staging,prod}.hcl` et la commande de role
assignment à exécuter. Détails : `infrastructure/terraform/README.md`,
`docs/SECURITY.md`.

```bash
make bootstrap-tfstate
# ou directement :
./scripts/bootstrap-tfstate.sh
./scripts/bootstrap-tfstate.ps1   # Windows
```

## `run-pipeline-local.sh` / `run-pipeline-local.ps1`

Dry-run 100% local du pipeline (`data_prep → train → evaluate`), sans
aucune ressource Azure — utile pendant la personnalisation d'un composant
pour valider vite sur les données du client, avant même que l'infra soit
prête. `register_model` n'est pas inclus (nécessite un vrai workspace).

```bash
make run-local
# ou directement, avec un CSV différent du sample par défaut :
./scripts/run-pipeline-local.sh chemin/vers/mes_donnees.csv
./scripts/run-pipeline-local.ps1 -RawCsv chemin/vers/mes_donnees.csv   # Windows
```

## `bootstrap-project.sh` / `bootstrap-project.ps1`

Déploiement de bout en bout en une commande — infra Terraform, compute et
environnement Azure ML, role assignments requis, data asset, et soumission
du pipeline d'entraînement (sample tant qu'il n'a pas encore été
personnalisé). Le premier déploiement d'un nouveau projet client, une fois
le repo cloné : `az login` → run visible dans Azure ML Studio, sans étape
manuelle intermédiaire. Idempotent (chaque étape vérifie avant de créer) —
peut être relancé sans échouer si une ressource existe déjà.

```bash
make bootstrap-project ENV=dev
# ou directement :
./scripts/bootstrap-project.sh dev
./scripts/bootstrap-project.sh dev --skip-infra   # réutilise l'infra déjà déployée

# Windows (PowerShell) :
./scripts/bootstrap-project.ps1 -Env dev
./scripts/bootstrap-project.ps1 -Env dev -SkipInfra
```

## `destroy.sh`

Destruction sécurisée de l'infrastructure : sauvegarde des outputs Terraform,
affichage du plan de destruction, puis **double confirmation explicite**
avant `terraform destroy`.

```bash
./scripts/destroy.sh
```

# TEMPLATE: do not modify unless architecture requires it — la double
confirmation est une garde-fou volontaire contre une destruction accidentelle
en production ; ne pas la retirer ni l'automatiser.
