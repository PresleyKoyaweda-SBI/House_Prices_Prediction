# Cycle de vie MLOps

Ce document décrit comment les données, le code, les modèles et les
déploiements circulent dans ce starter kit, du développement à la
production.

## Vue d'ensemble

```
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌──────────────────┐
│  data_prep  │ → │    train    │ → │  evaluate   │ → │  register_model  │
└─────────────┘   └─────────────┘   └─────────────┘   └──────────────────┘
     uri_folder      mlflow_model      metrics.json      Model Registry
                                                          (conditionnel)
```

Orchestré par `ml/pipelines/training-pipeline.yml`. Chaque composant est un
processus indépendant (`components/<nom>/src/main.py`) exécuté dans son
propre environnement Azure ML — voir `components/<nom>/README.md` pour le
détail des entrées/sorties.

## Séparation des préoccupations

Le pipeline distingue volontairement quatre responsabilités qui **ne
doivent pas être fusionnées** dans un composant unique :

| Composant | Responsabilité | Ne fait PAS |
|---|---|---|
| `data_prep` | Nettoyage, feature eng, split train/test | N'entraîne pas de modèle |
| `train` | Entraînement + log MLflow | Ne décide pas si le modèle est "bon" |
| `evaluate` | Calcul des métriques | N'enregistre pas le modèle |
| `register_model` | Enregistrement conditionnel (gating) | Ne réentraîne pas |

## Gestion des modèles (Model Registry / MLflow)

Le modèle est journalisé au format **MLflow** dès l'entraînement
(`mlflow.sklearn.save_model` dans `components/train/src/main.py`), puis
enregistré dans le **Model Registry Azure ML** par `register_model`
**uniquement si** sa métrique dépasse un seuil configurable — c'est le
mécanisme recommandé par Microsoft (voir
[how-to-manage-models](https://learn.microsoft.com/azure/machine-learning/how-to-manage-models)).

Chaque version de modèle enregistrée doit rester traçable jusqu'à :

- la version du run et ses métriques (MLflow, automatique) ;
- la version du jeu de données utilisé (`ml/data/*.yml`, versionné) ;
- l'environnement d'exécution (`environment:` du composant `train`) ;
- le commit Git du code (à ajouter en `properties` du modèle — voir
  `components/register_model/src/main.py`, `TEMPLATE: customize for client`).

**Aucun binaire de modèle n'est commité dans Git.** Le Model Registry Azure
ML est la seule source de vérité pour les artefacts de modèle.

## Environnements dev → staging → prod

Un déploiement d'application (ex: nouvelle version d'un composant, correctif
de pipeline) **ne force jamais un réentraînement**. Ce sont deux cycles
indépendants :

- **Cycle infrastructure/code** : `environments/{dev,staging,prod}.tfvars` +
  `.github/workflows/cd.yml` — promeut le code et l'infrastructure.
- **Cycle modèle** : soumission de `ml/pipelines/training-pipeline.yml` —
  déclenchée manuellement, sur planification, ou sur dérive de données/
  performance (selon la stratégie retenue avec le client).

La promotion d'un modèle entre environnements se fait par **référence de
version** dans le Model Registry (`azureml:ml-project-model:3`), jamais par
ré-enregistrement ou copie manuelle de fichiers.

## Cycle de déploiement (CD)

```
PR → CI (lint, tests, validation YAML/Terraform, scan secrets)
   → merge main
   → déploiement DEV (automatique)
   → validation (tests smoke)
   → promotion STAGING (approbation manuelle requise)
   → promotion PROD (approbation manuelle requise)
```

Voir `.github/workflows/cd.yml`. La CI (`.github/workflows/ci.yml`) ne
déploie jamais — elle valide uniquement.

## Tests

| Dossier | Portée | Dépendances externes |
|---|---|---|
| `components/*/tests/` | Logique de chaque composant, en isolation | Aucune |
| `tests/unit/` | Outils (`tools/`) | Aucune |
| `tests/integration/` | Chargement des YAML par le SDK Azure ML v2 | `azure-ai-ml` (hors ligne) |
| `tests/smoke/` | Endpoint réellement déployé | Workspace Azure ML déployé |

## Observabilité

- **Infrastructure** : Azure Monitor / Application Insights (déjà
  provisionné par Terraform, `application_insights.tf`).
- **Entraînement** : métriques et runs via MLflow (natif Azure ML Studio) ;
  dérive de données/modèle — activer les
  [Data Drift Monitors Azure ML](https://learn.microsoft.com/azure/machine-learning/how-to-monitor-datasets)
  si le cas d'usage l'exige (non activé par défaut).
- **Endpoints** : latence, taux d'erreur et disponibilité exposés
  nativement par les endpoints managés Azure ML dans Application Insights —
  aucune infrastructure de monitoring supplémentaire à construire.
