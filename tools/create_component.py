#!/usr/bin/env python3
"""Générateur de composant Azure ML CLI v2.

Crée un nouveau composant minimal et valide dans `components/<name>/` :
`component.yml`, `src/main.py`, `tests/test_component.py`, `README.md`.

Usage :
    python tools/create_component.py <name>
    make new-component NAME=<name>
"""

import argparse
import re
import sys
from pathlib import Path

COMPONENT_YML = """\
# TEMPLATE: customize for client
# ------------------------------------------------------------------------
# Composant Azure ML CLI v2 — {name}.
# Référence Microsoft officielle :
# https://learn.microsoft.com/azure/machine-learning/how-to-create-component-pipelines-cli
$schema: https://azuremlschemas.azureedge.net/latest/commandComponent.schema.json
name: {name}
display_name: "{display_name}"
version: 1
type: command
description: "TODO — décrire la responsabilité unique de ce composant."

inputs:
  input_data:
    type: uri_folder
    description: "TODO — décrire l'entrée."

outputs:
  output_data:
    type: uri_folder
    description: "TODO — décrire la sortie."

code: ./src

# TEMPLATE: optional
environment: azureml:ml-project-training-env@latest

command: >-
  python main.py
  --input_data ${{{{inputs.input_data}}}}
  --output_data ${{{{outputs.output_data}}}}
"""

MAIN_PY = '''\
"""TODO — décrire la logique du composant {name}."""

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_data", type=str, required=True)
    parser.add_argument("--output_data", type=str, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    output_dir = Path(args.output_data)
    output_dir.mkdir(parents=True, exist_ok=True)

    # TODO — implémenter la logique du composant.


if __name__ == "__main__":
    main()
'''

TEST_PY = '''\
"""Tests unitaires du composant {name} (exécution locale, hors Azure ML)."""

import subprocess
import sys
from pathlib import Path


def test_{name}_runs(tmp_path: Path) -> None:
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    output_dir = tmp_path / "output"
    main_script = Path(__file__).parent.parent / "src" / "main.py"

    result = subprocess.run(
        [
            sys.executable,
            str(main_script),
            "--input_data",
            str(input_dir),
            "--output_data",
            str(output_dir),
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
'''

README_MD = """\
# Composant `{name}`

TODO — décrire la responsabilité unique de ce composant.

## Entrées / sorties

| Nom | Direction | Type | Description |
|---|---|---|---|
| `input_data` | entrée | `uri_folder` | TODO |
| `output_data` | sortie | `uri_folder` | TODO |

## Test local

```bash
pytest components/{name}/tests/
```
"""


def validate_name(name: str) -> None:
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
        raise ValueError(
            "Le nom du composant doit être en snake_case "
            "(lettres minuscules, chiffres, underscores)."
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", help="Nom du composant (snake_case, ex: feature_engineering)")
    args = parser.parse_args()

    validate_name(args.name)
    name = args.name
    display_name = name.replace("_", " ").capitalize()

    repo_root = Path(__file__).parent.parent
    component_dir = repo_root / "components" / name

    if component_dir.exists():
        print(f"Erreur : components/{name}/ existe déjà.", file=sys.stderr)
        sys.exit(1)

    (component_dir / "src").mkdir(parents=True)
    (component_dir / "tests").mkdir(parents=True)

    (component_dir / "component.yml").write_text(
        COMPONENT_YML.format(name=name, display_name=display_name)
    )
    (component_dir / "src" / "main.py").write_text(MAIN_PY.format(name=name))
    (component_dir / "tests" / "test_component.py").write_text(TEST_PY.format(name=name))
    (component_dir / "README.md").write_text(README_MD.format(name=name))

    print(f"Composant créé : components/{name}/")
    print("Prochaines étapes :")
    print(f"  1. Compléter components/{name}/src/main.py")
    print(f"  2. Compléter components/{name}/component.yml (entrées/sorties réelles)")
    print(f"  3. pytest components/{name}/tests/")
    print("  4. Ajouter le composant à ml/pipelines/training-pipeline.yml si nécessaire")


if __name__ == "__main__":
    main()
