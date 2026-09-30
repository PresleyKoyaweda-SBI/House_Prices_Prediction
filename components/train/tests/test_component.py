"""Tests unitaires du composant train (exécution locale, hors Azure ML)."""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import mlflow
import numpy as np
import pandas as pd

SRC = Path(__file__).parent.parent / "src"
MAIN = SRC / "main.py"
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


def _districts(n: int = 200) -> pd.DataFrame:
    rng = np.random.default_rng(0)
    df = pd.DataFrame(
        {
            "MedInc": rng.uniform(0.5, 15, n),
            "HouseAge": rng.integers(1, 53, n).astype(float),
            "AveRooms": rng.uniform(2, 9, n),
            "AveBedrms": rng.uniform(0.8, 1.5, n),
            "Population": rng.uniform(100, 5000, n),
            "AveOccup": rng.uniform(1.5, 5, n),
            "Latitude": rng.uniform(32.5, 42, n),
            "Longitude": rng.uniform(-124.3, -114.3, n),
        }
    )
    df["MedHouseVal"] = np.clip(0.4 * df["MedInc"] + rng.normal(0, 0.3, n), 0.15, 5.0)
    return df


def _small_config(tmp_path: Path, members: dict) -> Path:
    config = {
        "model": "test",
        "members": members,
        "features": FEATURES,
        "target": "MedHouseVal",
        "use_log_target": True,
        "clip_predictions": True,
        "target_bounds": [0.14999, 5.00001],
        "drop_extreme_districts": False,
    }
    path = tmp_path / "config.json"
    path.write_text(json.dumps(config))
    return path


def _train(tmp_path: Path, config_path: Path | None = None) -> subprocess.CompletedProcess:
    train_dir = tmp_path / "train"
    train_dir.mkdir(exist_ok=True)
    _districts().to_csv(train_dir / "train.csv", index=False)
    cmd = [
        sys.executable,
        str(MAIN),
        "--train_data",
        str(train_dir),
        "--model_output",
        str(tmp_path / "model"),
    ]
    if config_path is not None:
        cmd += ["--model_config", str(config_path)]
    return subprocess.run(cmd, capture_output=True, text=True, cwd=tmp_path)


def test_train_produces_mlflow_model_that_predicts_from_raw_columns(tmp_path: Path) -> None:
    config = _small_config(
        tmp_path,
        {"XGBoost": {"n_estimators": 20, "max_depth": 3}},
    )

    result = _train(tmp_path, config)

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "model" / "MLmodel").exists()
    # Le modèle rechargé accepte les 8 colonnes brutes (feature engineering intégré) et
    # respecte le bornage des prédictions.
    model = mlflow.sklearn.load_model(str(tmp_path / "model"))
    predictions = model.predict(_districts(10)[FEATURES])
    assert predictions.shape == (10,)
    assert np.all((predictions >= 0.14999) & (predictions <= 5.00001))


def test_default_model_config_is_valid() -> None:
    # Le model_config.json versionné (exporté par le notebook) doit être lisible par train.
    spec = importlib.util.spec_from_file_location("train_main", MAIN)
    assert spec is not None and spec.loader is not None
    train_main = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(train_main)

    config = train_main.load_config(SRC / "model_config.json")
    assert set(config["features"]) == set(FEATURES)

    estimator = train_main.build_estimator(config)
    assert hasattr(estimator, "fit")


def test_train_rejects_config_for_another_model(tmp_path: Path) -> None:
    # Si le notebook retient un autre modèle, le composant doit l'annoncer clairement.
    config = _small_config(tmp_path, {"LightGBM": {"n_estimators": 20}})

    result = _train(tmp_path, config)

    assert result.returncode != 0
    # Sans accent : l'encodage de stderr varie selon la console (cp1252 sous Windows).
    assert "que XGBoost" in result.stderr
