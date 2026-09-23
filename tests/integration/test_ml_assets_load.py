"""Tests d'intégration : chargement des définitions Azure ML CLI v2 via le
SDK Azure ML v2 (azure-ai-ml), sans connexion à un workspace réel.

Ces tests valident que les fichiers YAML sont non seulement syntaxiquement
corrects (voir tests/unit/test_validate_yaml.py) mais aussi conformes à ce
que le SDK/CLI Azure ML v2 attend réellement — une vérification plus forte
qu'un simple contrôle de clé `$schema`.
"""

from pathlib import Path

import pytest
from azure.ai.ml import load_component, load_job

REPO_ROOT = Path(__file__).parent.parent.parent

COMPONENT_FILES = sorted((REPO_ROOT / "components").glob("*/component.yml"))


@pytest.mark.parametrize("component_path", COMPONENT_FILES, ids=lambda p: p.parent.name)
def test_component_definition_loads(component_path: Path) -> None:
    component = load_component(source=str(component_path))
    assert component.name


def test_training_pipeline_loads() -> None:
    pipeline_path = REPO_ROOT / "ml" / "pipelines" / "training-pipeline.yml"
    pipeline = load_job(source=str(pipeline_path))
    expected_jobs = {"data_prep_job", "train_job", "evaluate_job", "register_model_job"}
    assert expected_jobs.issubset(pipeline.jobs.keys())
