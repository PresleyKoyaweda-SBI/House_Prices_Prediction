"""Tests unitaires de tools/validate_yaml.py."""

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent

spec = importlib.util.spec_from_file_location(
    "validate_yaml", REPO_ROOT / "tools" / "validate_yaml.py"
)
validate_yaml = importlib.util.module_from_spec(spec)
sys.modules["validate_yaml"] = validate_yaml
spec.loader.exec_module(validate_yaml)


def test_validate_file_accepts_valid_schema(tmp_path: Path) -> None:
    yml = tmp_path / "asset.yml"
    yml.write_text(
        "$schema: https://azuremlschemas.azureedge.net/latest/data.schema.json\nname: x\n"
    )
    assert validate_yaml.validate_file(yml) == []


def test_validate_file_flags_missing_schema(tmp_path: Path) -> None:
    yml = tmp_path / "asset.yml"
    yml.write_text("name: x\n")
    errors = validate_yaml.validate_file(yml)
    assert any("schema" in e.lower() for e in errors)


def test_validate_file_flags_wrong_schema_host(tmp_path: Path) -> None:
    yml = tmp_path / "asset.yml"
    yml.write_text("$schema: https://example.com/schema.json\nname: x\n")
    errors = validate_yaml.validate_file(yml)
    assert any("officiel" in e.lower() for e in errors)


def test_validate_file_flags_invalid_yaml(tmp_path: Path) -> None:
    yml = tmp_path / "asset.yml"
    yml.write_text("name: [unterminated\n")
    errors = validate_yaml.validate_file(yml)
    assert errors
