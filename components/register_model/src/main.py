"""Enregistrement conditionnel du modèle dans le Model Registry Azure ML.

Lit le rapport d'évaluation produit par `evaluate` et n'enregistre le modèle que si sa RMSE est
inférieure ou égale au seuil fixé (gating). Le seuil par défaut, 0,50, correspond à une erreur
typique de 50 000 $ sur la valeur médiane d'un district : au-delà, l'estimation n'est plus assez
fiable pour trier des zones (voir notebooks/01_Exploration.ipynb, introduction).

L'enregistrement utilise le SDK Azure ML v2 (azure-ai-ml) avec les informations d'espace de
travail injectées automatiquement par Azure ML dans l'environnement du job, et l'identité managée
du compute pour l'authentification (aucun secret requis).
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
    parser.add_argument("--rmse_threshold", type=float, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    metrics_path = Path(args.evaluation_report) / "metrics.json"
    metrics = json.loads(metrics_path.read_text())
    # Métrique absente = on ne peut pas juger la qualité du modèle : on refuse par prudence.
    rmse = metrics.get("rmse", float("inf"))

    if rmse > args.rmse_threshold:
        print(f"RMSE {rmse:.4f} > seuil {args.rmse_threshold} — modèle NON enregistré.")
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

    # Les métriques sont stockées comme propriétés du modèle : on les retrouve dans le registre
    # sans avoir à rouvrir le run d'évaluation.
    properties = {k: f"{v:.6g}" for k, v in metrics.items() if isinstance(v, int | float)}
    model = Model(
        path=args.model_input,
        name=args.model_name,
        type=AssetTypes.MLFLOW_MODEL,
        description=(
            f"Estimation de la valeur médiane des logements par district "
            f"(RMSE={rmse:.4f}, soit environ {rmse * 100_000:,.0f} $ d'écart typique)."
        ),
        properties=properties,
    )
    registered = ml_client.models.create_or_update(model)

    print(f"Modèle enregistré : {registered.name}, version {registered.version}")


if __name__ == "__main__":
    main()
