"""Tests unitaires du composant train (exécution locale, hors Azure ML)."""

import subprocess
import sys
from pathlib import Path


def test_train_produces_mlflow_model(tmp_path: Path) -> None:
    train_dir = tmp_path / "train"
    train_dir.mkdir()
    csv_content = "feature_1,feature_2,target\n" + "\n".join(
        f"{i},{i * 2},{i % 2}" for i in range(20)
    )
    (train_dir / "train.csv").write_text(csv_content)

    model_out = tmp_path / "model"
    main_script = Path(__file__).parent.parent / "src" / "main.py"

    result = subprocess.run(
        [
            sys.executable,
            str(main_script),
            "--train_data",
            str(train_dir),
            "--n_estimators",
            "10",
            "--model_output",
            str(model_out),
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert model_out.exists()
    assert (model_out / "MLmodel").exists()
