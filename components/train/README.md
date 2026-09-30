# Composant `train`

Entraîne le modèle retenu dans `notebooks/01_Exploration.ipynb` et l'écrit au format MLflow
(`outputs.model_output`, type `mlflow_model`).

Le pipeline entraîné est **complet** : feature engineering (distances aux grandes villes, ratios,
coordonnées tournées) → imputation → transformation (modèles linéaires) → modèle, avec
transformation de la cible (log) et bornage des prédictions à l'intervalle observé. Le modèle
prend donc en entrée les **8 colonnes brutes** : ni `evaluate` ni un endpoint n'ont de
prétraitement à faire.

## Choix du modèle : `src/model_config.json`

La comparaison des modèles est de l'exploration : elle reste dans le notebook. Le composant
n'entraîne que le modèle retenu, **XGBoost optimisé** (section 11.2 du notebook).

Ses hyperparamètres sont décrits dans `src/model_config.json`, copie de
`outputs/best_model_config.json` produit par la section 12.3 du notebook. Pour les mettre à jour :
relancer le notebook, puis copier le nouveau fichier.

Si le notebook retient un autre modèle, le composant échoue avec un message explicite :
`src/main.py` est alors à adapter. C'est un changement de code, relu comme tel.

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `train_data` | entrée | `uri_folder` | Jeu d'entraînement (`train.csv`) |
| `model_output` | sortie | `mlflow_model` | Modèle entraîné |

## Sérialisation

MLflow 3.15 enregistre par défaut au format `skops`, qui refuse les types internes de
scikit-learn et XGBoost (échec constaté même sur un simple `RandomForest`). Le composant
utilise donc `cloudpickle`. Un modèle pickle ne doit être chargé que depuis une source de confiance
(le workspace Azure ML du projet).

## Test local

```bash
pytest components/train/tests/
```
