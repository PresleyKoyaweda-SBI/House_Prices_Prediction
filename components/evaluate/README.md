# Composant `evaluate`

Évalue le modèle sur le jeu de test et écrit un rapport `evaluation_report/metrics.json`, lu par
`register_model`. Chaque erreur est aussi exprimée en dollars, pour être lisible côté métier
(la cible est en centaines de milliers de dollars).

| Métrique | Définition | Lecture métier |
|---|---|---|
| `rmse` / `rmse_usd` | RMSE (*Root Mean Squared Error*, racine de l'erreur quadratique moyenne) | Écart typique entre valeur estimée et valeur réelle d'un district ; pénalise fortement les grosses erreurs |
| `mae` / `mae_usd` | MAE (*Mean Absolute Error*, erreur absolue moyenne) | Erreur moyenne par district, en valeur absolue |
| `mape_pct` | MAPE (*Mean Absolute Percentage Error*) | Erreur moyenne en % de la valeur réelle |
| `r2` | R² (coefficient de détermination) | Part des écarts de valeur entre districts expliquée par le modèle |
| `rmse_capped` / `rmse_non_capped` | RMSE sur les districts plafonnés à 500 000 $ / sur les autres | Isole l'erreur due au plafond des données, que le modèle ne peut pas corriger |

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `model_input` | entrée | `mlflow_model` | Modèle entraîné |
| `test_data` | entrée | `uri_folder` | Jeu de test (`test.csv`) |
| `evaluation_report` | sortie | `uri_folder` | Rapport `metrics.json` |

## Test local

```bash
pytest components/evaluate/tests/
```
