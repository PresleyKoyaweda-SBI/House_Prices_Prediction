"""Tests unitaires du composant evaluate (exécution locale, hors Azure ML)."""

import json
import subprocess
import sys
from pathlib import Path

import mlflow
import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

MAIN = Path(__file__).parent.parent / "src" / "main.py"


def _evaluate(tmp_path: Path, df: pd.DataFrame) -> subprocess.CompletedProcess:
    model = LinearRegression().fit(df[["MedInc", "HouseAge"]], df["MedHouseVal"])

    model_dir = tmp_path / "model"
    mlflow.sklearn.save_model(
        model, model_dir, serialization_format=mlflow.sklearn.SERIALIZATION_FORMAT_CLOUDPICKLE
    )
    test_dir = tmp_path / "test"
    test_dir.mkdir()
    df.to_csv(test_dir / "test.csv", index=False)
    report_dir = tmp_path / "report"

    return subprocess.run(
        [
            sys.executable,
            str(MAIN),
            "--model_input",
            str(model_dir),
            "--test_data",
            str(test_dir),
            "--evaluation_report",
            str(report_dir),
        ],
        capture_output=True,
        text=True,
        cwd=tmp_path,
    )


def _districts(n: int = 50) -> pd.DataFrame:
    rng = np.random.default_rng(0)
    df = pd.DataFrame({"MedInc": rng.uniform(1, 10, n), "HouseAge": rng.uniform(1, 52, n)})
    df["MedHouseVal"] = 0.4 * df["MedInc"] + rng.normal(0, 0.2, n)
    return df


def test_evaluate_writes_regression_metrics(tmp_path: Path) -> None:
    result = _evaluate(tmp_path, _districts())

    assert result.returncode == 0, result.stderr
    metrics = json.loads((tmp_path / "report" / "metrics.json").read_text())
    assert {"rmse", "mae", "mape_pct", "r2", "rmse_usd", "mae_usd"} <= metrics.keys()
    # La traduction en dollars est cohérente avec l'unité de la cible (100 000 $).
    assert metrics["rmse_usd"] == metrics["rmse"] * 100_000
    assert metrics["r2"] > 0.8
    # Aucun district au plafond : le plus cher ne doit pas être pris pour un district plafonné.
    assert metrics["n_capped"] == 0
    assert "rmse_capped" not in metrics
    # MedInc porte toute l'information : c'est la variable la plus importante.
    importance = json.loads((tmp_path / "report" / "feature_importance.json").read_text())
    assert importance[0]["feature"] == "MedInc"


def test_evaluate_separates_capped_districts(tmp_path: Path) -> None:
    df = _districts()
    df.loc[:4, "MedHouseVal"] = 5.00001  # 5 districts au plafond de la cible

    result = _evaluate(tmp_path, df)

    assert result.returncode == 0, result.stderr
    metrics = json.loads((tmp_path / "report" / "metrics.json").read_text())
    assert metrics["n_capped"] == 5
    assert {"rmse_capped", "rmse_non_capped", "rmse_capped_usd"} <= metrics.keys()
