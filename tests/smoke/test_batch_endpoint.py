"""Tests smoke — vérification post-déploiement de l'endpoint batch réel.

Contrairement aux tests unitaires/intégration, ces tests appellent une
ressource Azure réellement déployée. Ils sont ignorés (skip) tant que les
variables d'environnement nécessaires ne sont pas fournies — ce qui est le
cas par défaut en local et en CI sur les branches de développement.

Le test soumet un petit CSV de districts à l'endpoint et attend la fin du
job de scoring : compter plusieurs minutes (démarrage d'un nœud de
cpu-cluster, qui redescend à zéro entre deux utilisations).

Exécution (après déploiement, ex: étape de validation dev dans
.github/workflows/cd.yml), avec une session `az login` active :
    AZURE_SUBSCRIPTION_ID=... AZURE_RESOURCE_GROUP=... \
    AZUREML_WORKSPACE_NAME=... BATCH_ENDPOINT_NAME=ml-project-batch-endpoint \
    pytest tests/smoke/
"""

import os
from pathlib import Path

import pandas as pd
import pytest

SETTINGS = {
    name: os.environ.get(name)
    for name in (
        "AZURE_SUBSCRIPTION_ID",
        "AZURE_RESOURCE_GROUP",
        "AZUREML_WORKSPACE_NAME",
        "BATCH_ENDPOINT_NAME",
    )
}

pytestmark = pytest.mark.skipif(
    not all(SETTINGS.values()),
    reason=f"{' / '.join(SETTINGS)} non définis — endpoint non déployé.",
)

# Trois districts réels (les 8 colonnes brutes attendues par le modèle) : baie de
# San Francisco, Los Angeles, et un district rural de la vallée centrale.
DISTRICTS = pd.DataFrame(
    {
        "MedInc": [8.3252, 3.5, 2.1],
        "HouseAge": [41.0, 30.0, 25.0],
        "AveRooms": [6.984, 5.2, 5.8],
        "AveBedrms": [1.024, 1.05, 1.1],
        "Population": [322.0, 1500.0, 900.0],
        "AveOccup": [2.556, 3.1, 2.9],
        "Latitude": [37.88, 34.05, 36.7],
        "Longitude": [-122.23, -118.25, -119.8],
    }
)


def test_batch_endpoint_scores_districts(tmp_path: Path) -> None:
    # Imports locaux : ces librairies ne servent qu'à ce test post-déploiement.
    from azure.ai.ml import Input, MLClient
    from azure.ai.ml.constants import AssetTypes
    from azure.identity import DefaultAzureCredential

    ml_client = MLClient(
        DefaultAzureCredential(),
        SETTINGS["AZURE_SUBSCRIPTION_ID"],
        SETTINGS["AZURE_RESOURCE_GROUP"],
        SETTINGS["AZUREML_WORKSPACE_NAME"],
    )
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    DISTRICTS.to_csv(input_dir / "districts.csv", index=False)

    # Un dossier local est envoyé sur le datastore par défaut du workspace.
    job = ml_client.batch_endpoints.invoke(
        endpoint_name=SETTINGS["BATCH_ENDPOINT_NAME"],
        input=Input(type=AssetTypes.URI_FOLDER, path=str(input_dir)),
    )
    ml_client.jobs.stream(job.name)  # bloque jusqu'à la fin du job

    assert ml_client.jobs.get(job.name).status == "Completed"
    # "score" est la sortie par défaut d'un déploiement batch de modèle MLflow.
    ml_client.jobs.download(name=job.name, output_name="score", download_path=tmp_path)
    predictions = list(tmp_path.rglob("predictions.csv"))
    assert predictions, "predictions.csv absent de la sortie du job"
    assert predictions[0].read_text().strip(), "predictions.csv est vide"
