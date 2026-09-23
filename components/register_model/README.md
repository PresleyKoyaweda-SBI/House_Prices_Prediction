# Composant `register_model`

**SAMPLE — logique de gating (seuil d'accuracy) à adapter.**

Lit le rapport d'évaluation produit par `evaluate` et n'enregistre le
modèle dans le Model Registry Azure ML que si sa métrique dépasse
`accuracy_threshold`. Utilise l'identité managée du compute — aucun secret
n'est requis.

## Entrées

| Nom | Type | Description |
|---|---|---|
| `model_input` | `mlflow_model` | Modèle entraîné |
| `evaluation_report` | `uri_folder` | Rapport d'évaluation (`metrics.json`) |
| `model_name` | `string` | Nom du modèle dans le registre |
| `accuracy_threshold` | `number` | Seuil minimal d'accuracy (SAMPLE, défaut : 0.6) |

## Test local

```bash
pytest components/register_model/tests/
```

## Personnalisation

Remplacez la métrique de gating (accuracy) et le seuil par ceux définis
avec le client. Pour un cas d'usage sans gating, supprimez simplement la
condition dans `src/main.py`.
