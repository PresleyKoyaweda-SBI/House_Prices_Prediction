"""Tests unitaires du composant data_prep (exécution locale, hors Azure ML)."""

import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd

MAIN = Path(__file__).parent.parent / "src" / "main.py"
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


def _districts(n: int = 40) -> pd.DataFrame:
    rng = np.random.default_rng(0)
    df = pd.DataFrame({c: rng.uniform(1, 10, n) for c in FEATURES})
    df["MedHouseVal"] = rng.uniform(0.15, 5.0, n)
    return df


def _run(raw_dir: Path, tmp_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(MAIN),
            "--raw_data",
            str(raw_dir),
            "--test_size",
            "0.25",
            "--train_data",
            str(tmp_path / "train"),
            "--test_data",
            str(tmp_path / "test"),
        ],
        capture_output=True,
        text=True,
    )


def test_data_prep_splits_train_test(tmp_path: Path) -> None:
    raw_dir = tmp_path / "raw"
    raw_dir.mkdir()
    _districts().to_csv(raw_dir / "california_housing.csv", index=False)

    result = _run(raw_dir, tmp_path)

    assert result.returncode == 0, result.stderr
    train = pd.read_csv(tmp_path / "train" / "train.csv")
    test = pd.read_csv(tmp_path / "test" / "test.csv")
    assert (len(train), len(test)) == (30, 10)
    assert list(train.columns) == [*FEATURES, "MedHouseVal"]


def test_data_prep_drops_rows_without_target_and_duplicates(tmp_path: Path) -> None:
    raw_dir = tmp_path / "raw"
    raw_dir.mkdir()
    df = _districts()
    df.loc[0, "MedHouseVal"] = np.nan  # cible manquante
    df = pd.concat([df, df.iloc[[1]]])  # doublon
    df.to_csv(raw_dir / "california_housing.csv", index=False)

    result = _run(raw_dir, tmp_path)

    assert result.returncode == 0, result.stderr
    n_out = len(pd.read_csv(tmp_path / "train" / "train.csv")) + len(
        pd.read_csv(tmp_path / "test" / "test.csv")
    )
    assert n_out == 39


def test_data_prep_fails_on_missing_column(tmp_path: Path) -> None:
    raw_dir = tmp_path / "raw"
    raw_dir.mkdir()
    _districts().drop(columns="Latitude").to_csv(raw_dir / "data.csv", index=False)

    result = _run(raw_dir, tmp_path)

    assert result.returncode != 0
    assert "Latitude" in result.stderr
