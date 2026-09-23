"""Tests unitaires du composant data_prep (exécution locale, hors Azure ML)."""

import subprocess
import sys
from pathlib import Path


def test_data_prep_splits_train_test(tmp_path: Path) -> None:
    raw_dir = tmp_path / "raw"
    raw_dir.mkdir()
    csv_content = "feature_1,feature_2,target\n" + "\n".join(
        f"{i},{i * 2},{i % 2}" for i in range(20)
    )
    (raw_dir / "data.csv").write_text(csv_content)

    train_dir = tmp_path / "train"
    test_dir = tmp_path / "test"
    main_script = Path(__file__).parent.parent / "src" / "main.py"

    result = subprocess.run(
        [
            sys.executable,
            str(main_script),
            "--raw_data",
            str(raw_dir),
            "--test_size",
            "0.25",
            "--train_data",
            str(train_dir),
            "--test_data",
            str(test_dir),
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert (train_dir / "train.csv").exists()
    assert (test_dir / "test.csv").exists()
