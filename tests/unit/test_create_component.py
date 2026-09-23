"""Tests unitaires du générateur tools/create_component.py.

Le script détermine la racine du dépôt à partir de son propre emplacement
(`Path(__file__).parent.parent`), pas du répertoire courant : chaque test
copie donc le script dans une arborescence temporaire `tools/` pour éviter
d'écrire dans le vrai dossier `components/` du dépôt.
"""

import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent


def _install_script(tmp_path: Path) -> Path:
    tools_dir = tmp_path / "tools"
    tools_dir.mkdir()
    (tmp_path / "components").mkdir()
    script = tools_dir / "create_component.py"
    shutil.copy(REPO_ROOT / "tools" / "create_component.py", script)
    return script


def test_create_component_generates_expected_files(tmp_path: Path) -> None:
    script = _install_script(tmp_path)

    result = subprocess.run(
        [sys.executable, str(script), "feature_engineering"],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr

    component_dir = tmp_path / "components" / "feature_engineering"
    assert (component_dir / "component.yml").exists()
    assert (component_dir / "src" / "main.py").exists()
    assert (component_dir / "tests" / "test_component.py").exists()
    assert (component_dir / "README.md").exists()


def test_create_component_rejects_invalid_name(tmp_path: Path) -> None:
    script = _install_script(tmp_path)

    result = subprocess.run(
        [sys.executable, str(script), "Not-Valid-Name"],
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0


def test_create_component_refuses_to_overwrite_existing(tmp_path: Path) -> None:
    script = _install_script(tmp_path)
    (tmp_path / "components" / "existing").mkdir()

    result = subprocess.run(
        [sys.executable, str(script), "existing"],
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
