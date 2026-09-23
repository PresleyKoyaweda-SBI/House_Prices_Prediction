"""SAMPLE — logique d'entraînement du modèle.

Entraîne un RandomForestClassifier générique et journalise le modèle au
format MLflow. Remplacer entièrement l'algorithme/les features par ceux du
client (voir docs/CUSTOMIZATION_GUIDE.md).
"""

import argparse
from pathlib import Path

import mlflow
import pandas as pd
from sklearn.ensemble import RandomForestClassifier


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train_data", type=str, required=True)
    parser.add_argument("--n_estimators", type=int, default=100)
    parser.add_argument("--model_output", type=str, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    train_df = pd.read_csv(Path(args.train_data) / "train.csv")
    target_col = "target"
    X_train = train_df.drop(columns=[target_col])
    y_train = train_df[target_col]

    mlflow.autolog()

    with mlflow.start_run():
        model = RandomForestClassifier(n_estimators=args.n_estimators, random_state=42)
        model.fit(X_train, y_train)

        mlflow.sklearn.save_model(model, args.model_output)

    print(f"Modèle entraîné sur {len(train_df)} lignes, écrit dans {args.model_output}")


if __name__ == "__main__":
    main()
