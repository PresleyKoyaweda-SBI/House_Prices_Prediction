#!/usr/bin/env python3
"""Valide la syntaxe et la structure minimale des YAML Azure ML CLI v2.

Vérifie, pour chaque fichier `*.yml`/`*.yaml` sous `ml/` et `components/` :
  - que le YAML est syntaxiquement valide ;
  - que la clé `$schema` est présente et pointe vers un schéma Azure ML
    officiel (azuremlschemas.azureedge.net).

Utilisé par `make validate-yaml` et par la CI (voir .github/workflows/ci.yml).
"""

import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).parent.parent
SCHEMA_DIRS = ["ml", "components"]
SCHEMA_PREFIX = "https://azuremlschemas.azureedge.net/"
# Fichiers YAML valides qui ne sont pas des assets Azure ML CLI v2 (donc
# sans `$schema`) — ex: spécifications conda référencées par un
# environment.yml via `conda_file:`.
NON_SCHEMA_FILENAMES = {"conda.yml", "conda.yaml"}


def find_yaml_files() -> list[Path]:
    files: list[Path] = []
    for directory in SCHEMA_DIRS:
        base = REPO_ROOT / directory
        if base.exists():
            files.extend(base.rglob("*.yml"))
            files.extend(base.rglob("*.yaml"))
    return sorted(files)


def validate_file(path: Path) -> list[str]:
    errors = []
    try:
        content = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        return [f"YAML invalide : {exc}"]

    if not isinstance(content, dict):
        return ["Contenu YAML racine attendu : objet (mapping)."]

    schema = content.get("$schema")
    if not schema:
        errors.append("Clé `$schema` manquante.")
    elif not schema.startswith(SCHEMA_PREFIX):
        errors.append(f"`$schema` ne référence pas un schéma Azure ML officiel : {schema}")

    return errors


def main() -> None:
    files = find_yaml_files()
    if not files:
        print("Aucun fichier YAML trouvé sous ml/ ou components/.")
        sys.exit(0)

    has_errors = False
    for path in files:
        rel_path = path.relative_to(REPO_ROOT)
        if path.name in NON_SCHEMA_FILENAMES:
            print(f"SKIP {rel_path} (fichier non-CLI v2, ex: spec conda)")
            continue
        errors = validate_file(path)
        if errors:
            has_errors = True
            print(f"FAIL {rel_path}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"OK   {rel_path}")

    if has_errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
