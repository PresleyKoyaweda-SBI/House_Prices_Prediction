"""Tests unitaires du composant register_model (exécution locale, hors Azure ML).

Le composant ne fait qu'un contrôle de qualité et une copie de fichiers : il se teste entièrement
en local. L'enregistrement dans le registre, fait après le pipeline par
scripts/bootstrap-project.sh, n'est pas testable hors d'un vrai workspace.
"""

import json
import subprocess
import sys
from pathlib import Path

MAIN_PATH = Path(__file__).parent.parent / "src" / "main.py"


def _run(tmp_path: Path, metrics: dict) -> subprocess.CompletedProcess:
    model_dir = tmp_path / "model"
    model_dir.mkdir()
    (model_dir / "MLmodel").write_text("flavors: {}\n")  # un modèle MLflow est un dossier

    report_dir = tmp_path / "report"
    report_dir.mkdir()
    (report_dir / "metrics.json").write_text(json.dumps(metrics))

    return subprocess.run(
        [
            sys.executable,
            str(MAIN_PATH),
            "--model_input",
            str(model_dir),
            "--evaluation_report",
            str(report_dir),
            "--rmse_threshold",
            "0.5",
            "--mape_threshold_pct",
            "20",
            "--model_output",
            str(tmp_path / "output"),
        ],
        capture_output=True,
        text=True,
    )


def test_accepted_model_is_copied_to_output(tmp_path: Path) -> None:
    # RMSE 0,41 (41 000 $) et MAPE 14 % : les chiffres du notebook, sous les deux seuils.
    result = _run(tmp_path, {"rmse": 0.41, "mape_pct": 14.0})

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "output" / "MLmodel").exists()


def test_model_above_rmse_threshold_is_rejected(tmp_path: Path) -> None:
    # RMSE 0,8 (80 000 $ d'écart typique) : au-dessus du seuil de 0,5.
    result = _run(tmp_path, {"rmse": 0.8, "mape_pct": 14.0})

    assert result.returncode != 0
    assert "RMSE" in result.stderr
    assert not (tmp_path / "output").exists()


def test_model_above_mape_threshold_is_rejected(tmp_path: Path) -> None:
    # RMSE correcte, mais erreur relative moyenne de 25 % : au-dessus du seuil de 20 %.
    result = _run(tmp_path, {"rmse": 0.45, "mape_pct": 25.0})

    assert result.returncode != 0
    assert "MAPE" in result.stderr
    assert not (tmp_path / "output").exists()


def test_missing_metric_is_rejected(tmp_path: Path) -> None:
    # Sans la métrique, impossible de juger la qualité : refus par prudence.
    result = _run(tmp_path, {"r2": 0.87})

    assert result.returncode != 0
    assert not (tmp_path / "output").exists()
