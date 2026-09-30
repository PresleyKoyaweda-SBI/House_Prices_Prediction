# Composant `data_prep`

Lit le CSV California Housing (un district par ligne), vérifie qu'il respecte le schéma attendu
(8 variables + `MedHouseVal`), retire les lignes sans cible et les doublons, puis sépare un jeu
d'entraînement et un jeu de test (graine fixe, donc découpage identique d'un run à l'autre).

Le feature engineering n'est **pas** fait ici : il fait partie du pipeline scikit-learn du
composant `train`, pour être appliqué à l'identique à l'entraînement et à l'inférence.

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `raw_data` | entrée | `uri_folder` | Dossier contenant **un seul** CSV (data asset `house-prices-raw-data`) |
| `test_size` | entrée | `number` | Proportion réservée au test (défaut : 0.2) |
| `train_data` | sortie | `uri_folder` | `train.csv` |
| `test_data` | sortie | `uri_folder` | `test.csv` |

Le composant échoue explicitement si le dossier contient zéro ou plusieurs CSV, ou si une
colonne attendue manque : mieux vaut un échec clair qu'un modèle entraîné sur de mauvaises données.

## Test local

```bash
pytest components/data_prep/tests/
```
