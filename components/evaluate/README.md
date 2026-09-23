# Composant `evaluate`

**SAMPLE — métriques à remplacer par celles du cas d'usage client.**

Calcule des métriques de classification (accuracy, F1-score) sur le jeu de
test et écrit un rapport JSON (`evaluation_report/metrics.json`).

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `model_input` | entrée | `mlflow_model` | Modèle entraîné |
| `test_data` | entrée | `uri_folder` | Jeu de test |
| `evaluation_report` | sortie | `uri_folder` | Rapport `metrics.json` |

## Test local

```bash
pytest components/evaluate/tests/
```

## Personnalisation

Remplacez les métriques calculées par celles pertinentes pour le cas
d'usage client (ex : AUC, précision/rappel par classe, RMSE pour une
régression). Conservez la structure de sortie `metrics.json` pour rester
compatible avec `register_model`.
