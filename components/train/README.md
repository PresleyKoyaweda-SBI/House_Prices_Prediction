# Composant `train`

**SAMPLE — algorithme/hyperparamètres à remplacer.**

Entraîne un `RandomForestClassifier` générique sur le jeu d'entraînement et
journalise le modèle au format MLflow (`outputs.model_output`, type
`mlflow_model`), directement consommable par `evaluate` et `register_model`.

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `train_data` | entrée | `uri_folder` | Jeu d'entraînement |
| `n_estimators` | entrée | `integer` | Hyperparamètre exemple (défaut : 100) |
| `model_output` | sortie | `mlflow_model` | Modèle entraîné |

## Test local

```bash
pytest components/train/tests/
```

## Personnalisation

Remplacez l'algorithme, les hyperparamètres et les features par ceux du
client. Conservez le format de sortie `mlflow_model` pour rester compatible
avec `register_model` et le Model Registry Azure ML.
