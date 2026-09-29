# Données : California Housing

`california_housing.csv` contient le jeu de données **California Housing** (recensement américain
de 1990), exporté depuis scikit-learn (`sklearn.datasets.fetch_california_housing`) par
`notebooks/02_Data_Generation.ipynb`.

- **20 640 lignes**, une par district (*block group* du recensement), pas une par maison ;
- **8 variables** : `MedInc`, `HouseAge`, `AveRooms`, `AveBedrms`, `Population`, `AveOccup`,
  `Latitude`, `Longitude` ;
- **cible** : `MedHouseVal`, valeur médiane des logements du district, en centaines de milliers
  de dollars, plafonnée à 5,00001 (500 000 $).

Ce dossier est enregistré comme data asset Azure ML `house-prices-raw-data`
(`ml/data/sample-data-asset.yml`) et lu par le composant `data_prep`, qui attend **un seul**
fichier CSV dans le dossier.

Pour régénérer le fichier :

```python
from sklearn.datasets import fetch_california_housing

fetch_california_housing(as_frame=True).frame.to_csv(
    "sample_data/california_housing.csv", index=False
)
```
