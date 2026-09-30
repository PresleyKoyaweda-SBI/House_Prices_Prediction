# Composant `register_model`

Contrôle de qualité avant enregistrement. Lit le rapport produit par `evaluate` et laisse passer le
modèle seulement s'il respecte les deux seuils d'acceptabilité du notebook :

| Métrique | Seuil par défaut | Ce que ça veut dire |
|---|---|---|
| **RMSE** (*Root Mean Squared Error*) | ≤ 0,5 | Erreur typique d'au plus **50 000 $** sur la valeur médiane d'un district |
| **MAPE** (*Mean Absolute Percentage Error*) | ≤ 20 % | Estimation en moyenne à moins de **20 %** de la valeur réelle |

Pour une erreur, plus bas = meilleur : chaque seuil est un maximum. Une métrique absente du rapport
compte comme un échec.

- **Modèle accepté** : il est recopié vers la sortie `model_output`. Une fois le pipeline
  terminé, `scripts/bootstrap-project.sh` (étape 8) l'enregistre dans le registre sous
  `house-price-model`, **en type MLFLOW**, puis le déploie sur l'endpoint batch. L'enregistrement
  automatique d'une sortie nommée n'est pas utilisé : il produit un modèle CUSTOM, que le
  déploiement batch sans code refuse.
- **Modèle refusé** : le composant échoue avec la raison du refus. Le pipeline apparaît en échec
  dans le studio, et rien n'est enregistré.

Le composant n'appelle pas le SDK Azure ML. L'enregistrement utilise l'identité de celui qui
lance le script (ton compte, ou l'identité GitHub en CD) : l'identité du compute n'a besoin
d'**aucun rôle Azure**, et le projet se déploie sans Owner sur le resource group. Les métriques
restent consultables dans le run `evaluate` du pipeline qui a produit le modèle.

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `model_input` | entrée | `mlflow_model` | Modèle entraîné |
| `evaluation_report` | entrée | `uri_folder` | Rapport d'évaluation (`metrics.json`) |
| `rmse_threshold` | entrée | `number` | RMSE maximale, en centaines de milliers de $ (défaut : 0.5) |
| `mape_threshold_pct` | entrée | `number` | MAPE maximale, en % (défaut : 20) |
| `model_output` | sortie | `mlflow_model` | Modèle accepté, enregistré en MLFLOW par le script de bootstrap |

## Test local

```bash
pytest components/register_model/tests/
```
