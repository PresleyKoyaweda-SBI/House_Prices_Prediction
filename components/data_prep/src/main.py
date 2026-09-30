"""Préparation des données California Housing.

Lit le CSV brut (un district par ligne), vérifie qu'il respecte le schéma attendu, retire les
lignes inexploitables, puis sépare un jeu d'entraînement et un jeu de test.

Le nettoyage reste volontairement minimal, en suivant les décisions de
notebooks/01_Exploration.ipynb :
- les données de référence n'ont ni valeur manquante ni doublon (section 2.1) ;
- les valeurs plafonnées (cible à 5,00001, HouseAge à 52) sont une limite des données, pas une
  erreur : je les garde (section 2.3) ;
- les districts atypiques (ratios extrêmes des petits districts) sont conservés : les retirer de
  l'entraînement dégrade légèrement la RMSE en validation croisée, et le modèle devra les prédire
  en production (sections 6 et 9.4).
Ces constats sont recalculés à chaque exécution et affichés dans les logs du job, pour repérer
une dérive des données sans rien modifier automatiquement.

Le feature engineering n'est PAS fait ici mais dans le pipeline scikit-learn du composant
`train`, pour qu'il soit appliqué à l'identique à l'entraînement et à l'inférence.
"""

import argparse
from pathlib import Path

import pandas as pd
from sklearn.model_selection import train_test_split

FEATURES = [
    "MedInc",
    "HouseAge",
    "AveRooms",
    "AveBedrms",
    "Population",
    "AveOccup",
    "Latitude",
    "Longitude",
]
TARGET = "MedHouseVal"
# Même graine que le notebook : sur sample_data/california_housing.csv, le jeu de test produit ici
# est exactement le hold-out du notebook (section 9.1), donc les métriques d'evaluate sont
# directement comparables aux siennes.
RANDOM_STATE = 42
# Plafonds de collecte du recensement (notebook, section 2.3).
TARGET_CAP = 5.00001
HOUSE_AGE_CAP = 52


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw_data", type=str, required=True)
    parser.add_argument("--test_size", type=float, default=0.2)
    parser.add_argument("--train_data", type=str, required=True)
    parser.add_argument("--test_data", type=str, required=True)
    return parser.parse_args()


def load_raw(raw_dir: Path) -> pd.DataFrame:
    # Le data asset est un dossier : je prends le seul CSV qu'il doit contenir, et j'échoue
    # clairement s'il y en a zéro ou plusieurs (plutôt que d'en choisir un au hasard).
    csv_files = sorted(raw_dir.glob("*.csv"))
    if len(csv_files) != 1:
        raise FileNotFoundError(
            f"Un seul fichier CSV attendu dans {raw_dir}, trouvé : {[f.name for f in csv_files]}"
        )
    return pd.read_csv(csv_files[0])


def validate_and_clean(df: pd.DataFrame) -> pd.DataFrame:
    # Contrat de données : toutes les colonnes attendues doivent être présentes et numériques.
    missing = [c for c in [*FEATURES, TARGET] if c not in df.columns]
    if missing:
        raise ValueError(f"Colonnes manquantes dans les données brutes : {missing}")
    df = df[[*FEATURES, TARGET]].apply(pd.to_numeric, errors="coerce")

    n_before = len(df)
    # Sans cible, une ligne ne sert ni à entraîner ni à évaluer. Une valeur de logement nulle ou
    # négative est impossible, et elle casserait la cible en log et la MAPE retenues au notebook.
    df = df[df[TARGET] > 0]
    # Un doublon pourrait se retrouver à la fois dans le train et dans le test.
    df = df.drop_duplicates()
    n_dropped = n_before - len(df)
    if n_dropped:
        print(f"{n_dropped} ligne(s) retirée(s) (cible manquante ou invalide, ou doublon)")
    # Les valeurs manquantes éventuelles dans les variables sont conservées : elles sont
    # imputées dans le pipeline d'entraînement.
    return df


def report_data_quality(df: pd.DataFrame) -> None:
    # Règles métier du notebook (sections 2.3 et 6.1). Elles ne retirent aucune ligne : elles
    # servent à comparer chaque nouveau jeu de données aux constats de l'analyse.
    households = df["Population"] / df["AveOccup"]
    rules = {
        # Incohérences : absentes des données de référence, leur apparition signale un problème
        # de collecte ou d'export.
        "AveBedrms > AveRooms (incohérent)": df["AveBedrms"] > df["AveRooms"],
        # Atypiques mais possibles (logements vacants, studios, foyers, résidences secondaires).
        "AveRooms < 1": df["AveRooms"] < 1,
        "AveOccup < 1": df["AveOccup"] < 1,
        "Très petit district (< 10 ménages)": households < 10,
        "Ratios extrêmes (AveOccup > 10 ou AveRooms > 20)": (df["AveOccup"] > 10)
        | (df["AveRooms"] > 20),
        # Plafonds : la vraie valeur est « au moins » ce plafond.
        f"Cible plafonnée ({TARGET} >= {TARGET_CAP})": df[TARGET] >= TARGET_CAP,
        f"Âge plafonné (HouseAge >= {HOUSE_AGE_CAP})": df["HouseAge"] >= HOUSE_AGE_CAP,
    }
    print(f"Contrôle qualité sur {len(df)} districts (aucune ligne retirée) :")
    for name, mask in rules.items():
        print(f"  - {name} : {int(mask.sum())} ({mask.mean():.1%})")
    n_missing = int(df[FEATURES].isna().sum().sum())
    if n_missing:
        print(f"  - Valeurs manquantes dans les variables (imputées par train) : {n_missing}")
    if (df[TARGET] > TARGET_CAP).any():
        # Au-delà du plafond, le bornage des prédictions de train (target_bounds) serait à revoir.
        print(f"  ATTENTION : cible au-delà du plafond {TARGET_CAP}, la source a changé")


def main() -> None:
    args = parse_args()

    df = validate_and_clean(load_raw(Path(args.raw_data)))
    report_data_quality(df)
    # Découpage aléatoire simple, comme au notebook : le cas d'usage est d'estimer des districts
    # situés dans des zones déjà couvertes par les données (section 12.2).
    train_df, test_df = train_test_split(df, test_size=args.test_size, random_state=RANDOM_STATE)

    train_out = Path(args.train_data)
    test_out = Path(args.test_data)
    train_out.mkdir(parents=True, exist_ok=True)
    test_out.mkdir(parents=True, exist_ok=True)
    train_df.to_csv(train_out / "train.csv", index=False)
    test_df.to_csv(test_out / "test.csv", index=False)

    print(f"Train : {len(train_df)} districts — Test : {len(test_df)} districts")


if __name__ == "__main__":
    main()
