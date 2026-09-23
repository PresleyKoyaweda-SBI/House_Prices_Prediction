"""SAMPLE — logique de préparation des données.

Lit un dossier de données brutes (CSV), effectue une séparation train/test
et écrit les deux jeux résultants. Remplacer entièrement cette logique par
celle du client (voir docs/CUSTOMIZATION_GUIDE.md).
"""

import argparse
from pathlib import Path

import pandas as pd
from sklearn.model_selection import train_test_split


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw_data", type=str, required=True)
    parser.add_argument("--test_size", type=float, default=0.2)
    parser.add_argument("--train_data", type=str, required=True)
    parser.add_argument("--test_data", type=str, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    raw_dir = Path(args.raw_data)
    csv_files = list(raw_dir.glob("*.csv"))
    if not csv_files:
        raise FileNotFoundError(f"Aucun fichier CSV trouvé dans {raw_dir}")

    df = pd.read_csv(csv_files[0])

    train_df, test_df = train_test_split(df, test_size=args.test_size, random_state=42)

    train_out = Path(args.train_data)
    test_out = Path(args.test_data)
    train_out.mkdir(parents=True, exist_ok=True)
    test_out.mkdir(parents=True, exist_ok=True)

    train_df.to_csv(train_out / "train.csv", index=False)
    test_df.to_csv(test_out / "test.csv", index=False)

    print(f"Train: {len(train_df)} lignes — Test: {len(test_df)} lignes")


if __name__ == "__main__":
    main()
