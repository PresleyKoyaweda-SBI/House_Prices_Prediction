# Composant `register_model`

Lit le rapport produit par `evaluate` et n'enregistre le modèle dans le Model Registry Azure ML
que si sa **RMSE** (*Root Mean Squared Error*) est **inférieure ou égale** à `rmse_threshold`.
Pour une erreur, plus bas = meilleur : le seuil est un maximum, pas un minimum.

Le seuil par défaut, **0,5**, correspond à une erreur typique de **50 000 $** sur la valeur
médiane d'un district : au-delà, l'estimation n'est plus assez fiable pour comparer et prioriser
des zones. Toutes les métriques du rapport sont copiées dans les propriétés du modèle enregistré.

Utilise l'identité managée du compute — aucun secret n'est requis.

## Entrées

| Nom | Type | Description |
|---|---|---|
| `model_input` | `mlflow_model` | Modèle entraîné |
| `evaluation_report` | `uri_folder` | Rapport d'évaluation (`metrics.json`) |
| `model_name` | `string` | Nom du modèle dans le registre (défaut : `house-price-model`) |
| `rmse_threshold` | `number` | RMSE maximale acceptée, en centaines de milliers de $ (défaut : 0.5) |

## Test local

```bash
pytest components/register_model/tests/
```
