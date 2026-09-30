"""Évaluation du modèle California Housing sur le jeu de test.

Calcule les métriques de régression retenues dans notebooks/01_Exploration.ipynb et les traduit
en dollars, pour qu'elles soient lisibles côté métier :
- RMSE : écart typique entre valeur estimée et valeur réelle d'un district (métrique principale,
  qui pénalise fortement les grosses erreurs, les plus coûteuses pour une décision) ;
- MAE : erreur moyenne en valeur absolue ;
- MAPE : erreur moyenne en % de la valeur réelle ;
- R² : part des écarts de valeur entre districts expliquée par le modèle.

L'erreur est aussi mesurée à part sur les districts plafonnés (section 12), et l'importance par
permutation des 8 variables d'origine (section 12.1) vérifie que le modèle raisonne comme au
notebook : l'emplacement d'abord, le niveau de vie ensuite, puis le type de logements.

Le rapport metrics.json est lu par `register_model` pour décider de l'enregistrement ;
feature_importance.json sert au suivi, d'un réentraînement à l'autre.
"""

import argparse
import json
from pathlib import Path

import mlflow
import numpy as np
import pandas as pd
from sklearn.inspection import permutation_importance
from sklearn.metrics import (
    mean_absolute_error,
    mean_absolute_percentage_error,
    r2_score,
    root_mean_squared_error,
)

TARGET = "MedHouseVal"
TARGET_UNIT_USD = 100_000  # la cible est exprimée en centaines de milliers de dollars
# Plafond de collecte de la cible (notebook, section 2.3) : 500 000 $ « ou plus ».
TARGET_CAP = 5.00001
RANDOM_STATE = 42


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_input", type=str, required=True)
    parser.add_argument("--test_data", type=str, required=True)
    parser.add_argument("--evaluation_report", type=str, required=True)
    return parser.parse_args()


def rmse_of(y_true, y_pred) -> float:
    return float(root_mean_squared_error(y_true, y_pred))


def compute_metrics(y_true: pd.Series, y_pred: np.ndarray) -> dict:
    rmse = rmse_of(y_true, y_pred)
    mae = float(mean_absolute_error(y_true, y_pred))
    metrics = {
        "rmse": rmse,
        "mae": mae,
        "mape_pct": float(mean_absolute_percentage_error(y_true, y_pred) * 100),
        "r2": float(r2_score(y_true, y_pred)),
        "rmse_usd": rmse * TARGET_UNIT_USD,
        "mae_usd": mae * TARGET_UNIT_USD,
    }
    # La cible est plafonnée à 500 000 $ : je sépare l'erreur sur les districts plafonnés, où le
    # modèle ne peut pas connaître la vraie valeur, du reste. Je compare au plafond fixe, et non
    # au maximum du jeu de test : sans district plafonné, le plus cher serait pris pour tel.
    capped = (y_true >= TARGET_CAP).to_numpy()
    metrics["n_capped"] = int(capped.sum())
    if capped.any() and (~capped).any():
        for name, mask in [("non_capped", ~capped), ("capped", capped)]:
            metrics[f"rmse_{name}"] = rmse_of(y_true[mask], y_pred[mask])
            metrics[f"rmse_{name}_usd"] = metrics[f"rmse_{name}"] * TARGET_UNIT_USD
    return metrics


def compute_feature_importance(model, X: pd.DataFrame, y: pd.Series) -> pd.DataFrame:
    # Hausse de la RMSE quand une variable d'origine est mélangée (notebook, section 12.1). Le
    # feature engineering étant dans le modèle, mélanger Latitude brouille aussi les distances
    # et les coordonnées tournées : j'obtiens la contribution totale de chaque variable brute.
    perm = permutation_importance(
        model,
        X,
        y,
        scoring="neg_root_mean_squared_error",
        n_repeats=5,
        random_state=RANDOM_STATE,
    )
    return pd.DataFrame(
        {
            "feature": X.columns,
            "rmse_increase": perm.importances_mean,
            "rmse_increase_std": perm.importances_std,
            "rmse_increase_usd": perm.importances_mean * TARGET_UNIT_USD,
        }
    ).sort_values("rmse_increase", ascending=False, ignore_index=True)


def main() -> None:
    args = parse_args()

    model = mlflow.sklearn.load_model(args.model_input)
    test_df = pd.read_csv(Path(args.test_data) / "test.csv")
    if TARGET not in test_df.columns:
        raise ValueError(f"Colonne cible '{TARGET}' absente de test.csv")
    X_test = test_df.drop(columns=[TARGET])
    y_test = test_df[TARGET]

    metrics = compute_metrics(y_test, model.predict(X_test))
    importance = compute_feature_importance(model, X_test, y_test)

    with mlflow.start_run():
        mlflow.log_metrics(metrics)
        mlflow.log_table(importance, "feature_importance.json")

    report_dir = Path(args.evaluation_report)
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "metrics.json").write_text(json.dumps(metrics, indent=2))
    (report_dir / "feature_importance.json").write_text(
        importance.to_json(orient="records", indent=2)
    )

    print(
        f"RMSE = {metrics['rmse']:.4f} (environ {metrics['rmse_usd']:,.0f} $ d'écart typique) | "
        f"MAE = {metrics['mae_usd']:,.0f} $ | MAPE = {metrics['mape_pct']:.1f} % | "
        f"R² = {metrics['r2']:.3f}"
    )
    if "rmse_capped" in metrics:
        print(
            f"Districts plafonnés ({metrics['n_capped']}) : {metrics['rmse_capped_usd']:,.0f} $ "
            f"d'écart typique, contre {metrics['rmse_non_capped_usd']:,.0f} $ pour les autres"
        )
    print("Importance par permutation (hausse de la RMSE) :")
    for row in importance.itertuples():
        print(f"  - {row.feature} : {row.rmse_increase_usd:,.0f} $")


if __name__ == "__main__":
    main()
