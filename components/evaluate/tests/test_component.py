"""Tests unitaires du composant evaluate (exécution locale, hors Azure ML)."""

import subprocess
import sys
from pathlib import Path

import mlflow
import pandas as pd
from sklearn.ensemble import RandomForestClassifier


def test_evaluate_writes_metrics_report(tmp_path: Path) -> None:
    train_df = pd.DataFrame(
        {
            "feature_1": range(20),
            "feature_2": [i * 2 for i in range(20)],
            "target": [i % 2 for i in range(20)],
        }
    )
    model = RandomForestClassifier(n_estimators=5, random_state=42)
    model.fit(train_df.drop(columns=["target"]), train_df["target"])

    model_dir = tmp_path / "model"
    mlflow.sklearn.save_model(model, model_dir)

    test_dir = tmp_path / "test"
    test_dir.mkdir()
    train_df.to_csv(test_dir / "test.csv", index=False)

    report_dir = tmp_path / "report"
    main_script = Path(__file__).parent.parent / "src" / "main.py"

    result = subprocess.run(
        [
            sys.executable,
            str(main_script),
            "--model_input",
            str(model_dir),
            "--test_data",
            str(test_dir),
            "--evaluation_report",
            str(report_dir),
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert (report_dir / "metrics.json").exists()
