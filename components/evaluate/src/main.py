"""SAMPLE — logique d'évaluation du modèle.

Calcule l'accuracy et le F1-score sur le jeu de test et écrit un rapport
JSON. Remplacer les métriques par celles pertinentes pour le cas d'usage
client (voir docs/CUSTOMIZATION_GUIDE.md).
"""

import argparse
import json
from pathlib import Path

import mlflow
import pandas as pd
from sklearn.metrics import accuracy_score, f1_score


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_input", type=str, required=True)
    parser.add_argument("--test_data", type=str, required=True)
    parser.add_argument("--evaluation_report", type=str, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    model = mlflow.sklearn.load_model(args.model_input)
    test_df = pd.read_csv(Path(args.test_data) / "test.csv")
    target_col = "target"
    X_test = test_df.drop(columns=[target_col])
    y_test = test_df[target_col]

    predictions = model.predict(X_test)
    metrics = {
        "accuracy": accuracy_score(y_test, predictions),
        "f1_score": f1_score(y_test, predictions, average="weighted"),
    }

    with mlflow.start_run():
        mlflow.log_metrics(metrics)

    report_dir = Path(args.evaluation_report)
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "metrics.json").write_text(json.dumps(metrics, indent=2))

    print(f"Métriques : {metrics}")


if __name__ == "__main__":
    main()
