# Composant `data_prep`

**SAMPLE — logique métier à remplacer.**

Lit un dossier de données brutes (`uri_folder`, CSV), effectue une séparation
train/test et écrit deux jeux en sortie (`train_data`, `test_data`).

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `raw_data` | entrée | `uri_folder` | Données brutes |
| `test_size` | entrée | `number` | Proportion réservée au test (défaut : 0.2) |
| `train_data` | sortie | `uri_folder` | Jeu d'entraînement |
| `test_data` | sortie | `uri_folder` | Jeu de test |

## Test local

```bash
pytest components/data_prep/tests/
```

## Personnalisation

Remplacez `src/main.py` par la logique réelle de nettoyage/préparation du
client. Conservez la signature des entrées/sorties (ou mettez à jour
`component.yml` et `ml/pipelines/training-pipeline.yml` en conséquence).
