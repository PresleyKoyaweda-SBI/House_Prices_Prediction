"""Tests unitaires du composant register_model.

Le cas "sous le seuil" s'exécute en subprocess (comportement observable :
rien n'est enregistré, aucun appel Azure). Le cas "au-dessus du seuil"
importe `main.py` directement et simule (`unittest.mock`) le SDK Azure ML
(`MLClient`, `DefaultAzureCredential`) — l'appel réel à un Model Registry
Azure ML nécessite un vrai workspace et reste hors scope ici (couvert par
tests/integration/ pour le chargement des définitions, jamais pour un
enregistrement réel).
"""

import importlib.util
import json
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock

MAIN_PATH = Path(__file__).parent.parent / "src" / "main.py"


def _load_main_module() -> types.ModuleType:
    spec = importlib.util.spec_from_file_location("register_model_main", MAIN_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_register_model_skips_below_threshold(tmp_path: Path) -> None:
    import subprocess

    model_dir = tmp_path / "model"
    model_dir.mkdir()

    report_dir = tmp_path / "report"
    report_dir.mkdir()
    # RMSE de 0,8 (80 000 $ d'écart typique) : au-dessus du seuil de 0,5, refusé.
    (report_dir / "metrics.json").write_text(json.dumps({"rmse": 0.8}))

    result = subprocess.run(
        [
            sys.executable,
            str(MAIN_PATH),
            "--model_input",
            str(model_dir),
            "--evaluation_report",
            str(report_dir),
            "--model_name",
            "test-model",
            "--rmse_threshold",
            "0.5",
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert "NON enregistré" in result.stdout


def test_register_model_registers_above_threshold(tmp_path: Path, monkeypatch) -> None:
    model_dir = tmp_path / "model"
    model_dir.mkdir()

    report_dir = tmp_path / "report"
    report_dir.mkdir()
    # RMSE de 0,45 : sous le seuil de 0,5, accepté.
    (report_dir / "metrics.json").write_text(json.dumps({"rmse": 0.45, "r2": 0.84}))

    monkeypatch.setenv("AZUREML_ARM_SUBSCRIPTION", "fake-subscription-id")
    monkeypatch.setenv("AZUREML_ARM_RESOURCEGROUP", "fake-rg")
    monkeypatch.setenv("AZUREML_ARM_WORKSPACE_NAME", "fake-workspace")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "main.py",
            "--model_input",
            str(model_dir),
            "--evaluation_report",
            str(report_dir),
            "--model_name",
            "test-model",
            "--rmse_threshold",
            "0.5",
        ],
    )

    module = _load_main_module()

    registered_model = MagicMock()
    registered_model.name = "test-model"
    registered_model.version = "1"
    fake_ml_client = MagicMock()
    fake_ml_client.models.create_or_update.return_value = registered_model
    monkeypatch.setattr(module, "MLClient", MagicMock(return_value=fake_ml_client))
    monkeypatch.setattr(module, "DefaultAzureCredential", MagicMock())

    module.main()

    fake_ml_client.models.create_or_update.assert_called_once()
    submitted_model = fake_ml_client.models.create_or_update.call_args[0][0]
    assert submitted_model.name == "test-model"
    assert submitted_model.properties["rmse"] == "0.45"
