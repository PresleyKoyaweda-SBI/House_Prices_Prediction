# Guide de personnalisation

**« Je démarre un nouveau projet client demain — qu'est-ce que je change ? »**

Ce guide répond précisément à cette question, point par point. Chaque
section indique le(s) fichier(s) à modifier et ce qu'il faut y mettre.

## Vue d'ensemble rapide

| # | Élément | Fichier(s) |
|---|---|---|
| 1 | Nom du projet | `infrastructure/terraform/variables.tf`, `environments/*.tfvars` |
| 2 | Région Azure | `environments/*.tfvars` |
| 3 | Souscription Azure | Variable d'environnement / `az account set` |
| 4 | Nommage des ressources | `infrastructure/terraform/locals.tf` |
| 5 | Tags | `infrastructure/terraform/locals.tf` |
| 6 | Environnements (dev/staging/prod) | `environments/*.tfvars` |
| 7 | Source de données | `ml/data/sample-data-asset.yml` |
| 8 | Features | `components/data_prep/src/main.py` |
| 9 | Cible (target) | `components/train/src/main.py`, `components/evaluate/src/main.py` |
| 10 | Algorithme | `components/train/src/main.py` |
| 11 | Métriques | `components/evaluate/src/main.py` |
| 12 | Compute | `ml/compute/compute-cluster.yml`, `ml/pipelines/training-pipeline.yml` |
| 13 | Environnement conda/Docker | `ml/environments/conda.yml`, `ml/environments/training-environment.yml` |
| 14 | Endpoint (batch) | `ml/endpoints/batch/` |
| 15 | Sécurité (auth endpoint) | `ml/endpoints/batch/batch-endpoint.yml` |
| 16 | RBAC | `infrastructure/terraform/machine_learning_workspace.tf` |
| 17 | Réseau (optionnel) | `docs/SECURITY.md` |
| 18 | Monitoring | `infrastructure/terraform/application_insights.tf` |
| 19 | CI/CD (secrets, environnements GitHub) | `.github/workflows/`, Settings GitHub |
| 20 | Stratégie de promotion dev→prod | `docs/MLOPS_LIFECYCLE.md`, `environments/` |
| 21 | State Terraform distant | `make bootstrap-tfstate`, `environments/backend-*.hcl` |

---

## 1. Nom du projet

`infrastructure/terraform/variables.tf` :
```hcl
variable "project_name" {
  default = "mon-projet-ml"  # TEMPLATE: customize for client
}
```
Répercuter dans `environments/{dev,staging,prod}.tfvars` (`project_name = "..."`)
et dans `ml/pipelines/training-pipeline.yml` / `ml/model/model.yml`
(`model_name`, noms des assets) si un nom plus spécifique que
`ml-project-model` est souhaité.

## 2. Région Azure

`environments/*.tfvars` :
```hcl
location = "canadacentral"  # ou "eastus", "westeurope", etc.
```
Vérifier la disponibilité d'Azure ML dans la région choisie
([liste des régions](https://azure.microsoft.com/global-infrastructure/services/?products=machine-learning-service)).

## 3. Souscription Azure

Non stocké dans le code (évite le verrouillage sur une souscription).
Définie via :
```bash
az account set --subscription "<subscription-id>"
```
et, en CI/CD, via le secret GitHub `AZURE_SUBSCRIPTION_ID` (voir §19).

## 4. Nommage des ressources

`infrastructure/terraform/locals.tf` — le pattern de nommage
(`resource_prefix`, `common_tags`) est calculé à partir de `project_name` et
`environment`. Adapter le pattern si la convention de nommage du client
diffère (ex : préfixe d'entreprise imposé).

## 5. Tags

`infrastructure/terraform/locals.tf`, bloc `common_tags` — ajouter les tags
obligatoires du client (centre de coûts, propriétaire, classification des
données, etc.).

## 6. Environnements (dev/staging/prod)

Un fichier par environnement dans `environments/` : `dev.tfvars`,
`staging.tfvars`, `prod.tfvars`. Ajuster les tailles de SKU/compute par
environnement (ex : SKU Premium en `prod` uniquement, déjà marqué
`# TEMPLATE: optional` dans `prod.tfvars`). Voir `environments/README.md`
pour la distinction avec les environnements Azure ML runtime (`ml/environments/`).

## 7. Source de données

`ml/data/sample-data-asset.yml` — remplacer `path:` par la source réelle
(chemin Blob Storage `azureml://...`, dossier local, ou HTTP(S)) et
supprimer `sample_data/` une fois branché. Voir
[how-to-create-data-assets](https://learn.microsoft.com/azure/machine-learning/how-to-create-data-assets).

## 8. Features

`components/data_prep/src/main.py` — remplacer la logique de lecture/
nettoyage par celle adaptée au schéma réel des données client (colonnes,
types, valeurs manquantes, encodage).

## 9. Cible (target)

`components/train/src/main.py` et `components/evaluate/src/main.py` —
remplacer `target_col = "target"` par le nom réel de la colonne cible, et
adapter le type de tâche (classification/régression) si différent de
l'exemple.

## 10. Algorithme

`components/train/src/main.py` — remplacer `RandomForestClassifier` par
l'algorithme retenu (autre modèle scikit-learn, XGBoost, LightGBM, réseau de
neurones, etc.) et ses hyperparamètres. Conserver le format de sortie
`mlflow_model` (`mlflow.<flavor>.save_model`) pour rester compatible avec
`evaluate` et `register_model`.

## 11. Métriques

`components/evaluate/src/main.py` — RMSE, MAE, MAPE et R² (traduits en
dollars), erreur séparée sur les districts plafonnés et importance par
permutation. Les seuils de gating (`rmse_threshold`, `mape_threshold_pct`)
se règlent dans `ml/pipelines/training-pipeline.yml` et sont appliqués par
`components/register_model`.

## 12. Compute

`ml/compute/compute-cluster.yml` — ajuster `size` (SKU de VM) et
`max_instances` selon la charge réelle. `ml/pipelines/training-pipeline.yml`
(`settings.default_compute`) référence ce cluster ; supprimer cette clé pour
utiliser un compute serverless si un cluster dédié n'est pas nécessaire.

## 13. Environnement conda/Docker

Par défaut, les composants référencent l'environnement personnalisé
enregistré `azureml:ml-project-training-env@latest` (`environment:` dans
chaque `component.yml`) — pas un environnement curated Microsoft, dont le
catalogue exact (versions disponibles, SDK inclus) varie selon
l'abonnement/la région/le tenant et n'est pas garanti d'un client à
l'autre. Pour ajouter des dépendances, éditer `ml/environments/conda.yml`
puis réenregistrer (une nouvelle version n'est créée que si le contenu
change) :

```bash
az ml environment create --file ml/environments/training-environment.yml \
  --resource-group <rg> --workspace-name <workspace>
```

À faire une fois par workspace avant le premier job (voir README —
Quick Start).

Un environnement curated reste utilisable comme alternative si son
contenu exact est vérifié disponible dans le workspace cible
(`az ml environment list --resource-group <rg> --workspace-name <ws>`) —
remplacer alors `environment: azureml:ml-project-training-env@latest` par
`environment: azureml:<nom-curated>@latest` dans le(s) `component.yml`
concerné(s).

## 14. Endpoint (batch)

Le modèle est déployé sur un endpoint **batch** (`ml/endpoints/batch/`) :
il note tous les districts d'un coup, périodiquement, ce qui correspond au
cas d'usage (comparer et prioriser des zones). L'exemple d'endpoint en ligne
a été supprimé — voir `ml/endpoints/README.md` pour la justification et
pour le recréer si un besoin temps réel apparaît.

`ml/endpoints/batch/batch-deployment.yml` — adapter
`max_concurrency_per_instance`/`mini_batch_size` à la charge attendue. Pour
un modèle MLflow, `mini_batch_size` compte des fichiers, pas des lignes.

## 15. Sécurité (authentification endpoint)

`ml/endpoints/batch/batch-endpoint.yml` — `auth_mode: aad_token`
(Microsoft Entra ID), seul mode accepté par les endpoints batch. Détails :
[docs/SECURITY.md](SECURITY.md).

## 16. RBAC

`infrastructure/terraform/machine_learning_workspace.tf` — les
`azurerm_role_assignment` définissent les permissions minimales de la
Managed Identity du workspace. Ajouter un rôle supplémentaire uniquement si
un besoin précis l'exige (ex : accès à une ressource externe au projet).

## 17. Réseau (optionnel)

Non configuré par défaut (voir §17 de [docs/SECURITY.md](SECURITY.md)).
Private Endpoints/VNet uniquement sur exigence explicite du client.

## 18. Monitoring

`infrastructure/terraform/application_insights.tf` — provisionné par
défaut, alimente automatiquement les métriques des endpoints managés Azure
ML et les logs d'exécution des pipelines. Aucune configuration
supplémentaire requise pour un monitoring de base.

## 19. CI/CD

- Secrets GitHub à configurer (Settings > Secrets and variables > Actions) :
  `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (fédération
  OIDC — voir [docs/SECURITY.md](SECURITY.md)).
- Variables de repo GitHub (même emplacement, onglet "Variables" — ce ne
  sont pas des secrets) : `TF_STATE_RESOURCE_GROUP`,
  `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER` — valeurs affichées par
  `make bootstrap-tfstate` (voir §21) ; et optionnellement
  `DEV_AZURE_RESOURCE_GROUP`/`DEV_AZUREML_WORKSPACE_NAME` pour les tests
  smoke de l'endpoint batch (ignorés tant qu'elles ne sont pas définies).
  L'identité OIDC doit pouvoir invoquer l'endpoint (rôle
  AzureML Data Scientist sur le workspace dev).
- Environnements GitHub à créer (Settings > Environments) : `dev` et
  `production` (règle d'approbation **requise**). Pas de staging.

## 20. Stratégie de promotion dev → prod

Décrite dans [docs/MLOPS_LIFECYCLE.md](MLOPS_LIFECYCLE.md). Points à valider
avec le client : fréquence de réentraînement, critère de promotion d'un
modèle (seuil de métrique, validation manuelle), fenêtre de déploiement en
production.

## 21. State Terraform distant

Une seule fois par client/tenant, **avant** le tout premier
`make tf-init` : `make bootstrap-tfstate` provisionne un storage account
dédié au state (hors Terraform — problème de l'œuf et de la poule), puis
créer `environments/backend-{dev,staging,prod}.hcl` à partir des
`.hcl.example` correspondants avec les valeurs affichées. Détails :
[infrastructure/terraform/README.md](../infrastructure/terraform/README.md).
Sans ce state distant, une CI recréerait des ressources en doublon à
chaque run au lieu de mettre à jour l'existant — ne jamais déployer en
staging/prod avec un state local.

---

## Checklist de démarrage

- [ ] §1–6 : identité du projet et de ses environnements
- [ ] §7 : source de données réelle branchée, `sample_data/` supprimé
- [ ] §8–11 : logique ML (features, cible, algorithme, métriques)
- [ ] §12–13 : compute et environnement d'exécution dimensionnés
- [ ] §14–15 : endpoint choisi et sécurisé
- [ ] §16–17 : RBAC et réseau validés avec le client
- [ ] §18 : monitoring vérifié en Studio Azure ML / Application Insights
- [ ] §19–20 : secrets et environnements GitHub configurés, stratégie de
      promotion validée avec le client
- [ ] §21 : storage account de state Terraform provisionné
      (`make bootstrap-tfstate`), `backend-*.hcl` créés, rôle `Storage Blob
      Data Contributor` accordé aux identités local + CI/CD
