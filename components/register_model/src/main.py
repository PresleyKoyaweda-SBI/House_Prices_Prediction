"""SAMPLE — enregistrement conditionnel du modèle dans le Model Registry.

Lit le rapport d'évaluation produit par le composant `evaluate` et
n'enregistre le modèle que si sa métrique dépasse un seuil (gating).
Ce seuil et la métrique utilisée sont un exemple pédagogique — à adapter
au cas d'usage réel du client (voir docs/CUSTOMIZATION_GUIDE.md).

L'enregistrement utilise le SDK Azure ML v2 (azure-ai-ml) avec les
informations d'espace de travail injectées automatiquement par Azure ML
dans l'environnement du job, et l'identité managée du compute pour
l'authentification (aucun secret requis).
"""

import argparse
import json
import os
from pathlib import Path

from azure.ai.ml import MLClient
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Model
from azure.identity import DefaultAzureCredential


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_input", type=str, required=True)
    parser.add_argument("--evaluation_report", type=str, required=True)
    parser.add_argument("--model_name", type=str, required=True)
    parser.add_argument("--accuracy_threshold", type=float, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    metrics_path = Path(args.evaluation_report) / "metrics.json"
    metrics = json.loads(metrics_path.read_text())
    accuracy = metrics.get("accuracy", 0.0)

    if accuracy < args.accuracy_threshold:
        print(f"Accuracy {accuracy:.4f} < seuil {args.accuracy_threshold} — modèle NON enregistré.")
        return

    # TEMPLATE: do not modify unless architecture requires it — ces variables
    # sont injectées automatiquement par Azure ML dans tout job en cours
    # d'exécution ; aucune configuration manuelle n'est nécessaire.
    ml_client = MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=os.environ["AZUREML_ARM_SUBSCRIPTION"],
        resource_group_name=os.environ["AZUREML_ARM_RESOURCEGROUP"],
        workspace_name=os.environ["AZUREML_ARM_WORKSPACE_NAME"],
    )

    model = Model(
        path=args.model_input,
        name=args.model_name,
        type=AssetTypes.MLFLOW_MODEL,
        description=f"SAMPLE — enregistré automatiquement (accuracy={accuracy:.4f}).",
        properties={"accuracy": str(accuracy)},
    )
    registered = ml_client.models.create_or_update(model)

    print(f"Modèle enregistré : {registered.name}, version {registered.version}")


if __name__ == "__main__":
    main()
