"""Contrôle de qualité avant enregistrement du modèle (gating).

Lit le rapport d'évaluation produit par `evaluate` et laisse passer le modèle seulement s'il
respecte les deux seuils d'acceptabilité fixés dans notebooks/01_Exploration.ipynb
(introduction) pour un outil de tri de zones :
- RMSE <= 0,50, soit une erreur typique de 50 000 $ sur la valeur médiane d'un district ;
- MAPE <= 20 %, soit une estimation en moyenne à moins de 20 % de la valeur réelle.

Si le modèle passe, il est recopié vers la sortie `model_output`. Une fois le pipeline terminé,
scripts/bootstrap-project.sh (étape 8) enregistre cette sortie dans le registre en type MLFLOW,
avec l'identité de celui qui lance le script. Le composant n'appelle donc pas le SDK Azure ML,
et l'identité du compute n'a besoin d'aucun rôle Azure (pas de role assignment, donc pas besoin
d'un Owner du resource group).

Si le modèle échoue, le composant s'arrête en erreur : le pipeline apparaît en échec dans le
studio, et rien n'est enregistré.
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

TARGET_UNIT_USD = 100_000  # la cible est exprimée en centaines de milliers de dollars


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_input", type=str, required=True)
    parser.add_argument("--evaluation_report", type=str, required=True)
    parser.add_argument("--rmse_threshold", type=float, required=True)
    parser.add_argument("--mape_threshold_pct", type=float, required=True)
    parser.add_argument("--model_output", type=str, required=True)
    return parser.parse_args()


def check_quality(metrics: dict, rmse_threshold: float, mape_threshold_pct: float) -> list[str]:
    # Renvoie la liste des seuils non respectés (vide = modèle accepté). Une métrique absente
    # compte comme un échec : sans elle, je ne peux pas juger la qualité du modèle.
    failures = []
    rmse = metrics.get("rmse")
    if rmse is None or rmse > rmse_threshold:
        failures.append(
            f"RMSE {rmse} > seuil {rmse_threshold}"
            if rmse is not None
            else "RMSE absente de metrics.json"
        )
    mape = metrics.get("mape_pct")
    if mape is None or mape > mape_threshold_pct:
        failures.append(
            f"MAPE {mape:.1f} % > seuil {mape_threshold_pct} %"
            if mape is not None
            else "MAPE absente de metrics.json"
        )
    return failures


def main() -> None:
    args = parse_args()

    metrics = json.loads((Path(args.evaluation_report) / "metrics.json").read_text())
    failures = check_quality(metrics, args.rmse_threshold, args.mape_threshold_pct)
    if failures:
        print("Modèle REFUSÉ, non enregistré : " + " ; ".join(failures), file=sys.stderr)
        sys.exit(1)

    # Le modèle MLflow est un dossier : je le recopie tel quel vers la sortie, que le script de
    # bootstrap enregistre ensuite en MLFLOW.
    shutil.copytree(args.model_input, args.model_output, dirs_exist_ok=True)
    print(
        f"Modèle ACCEPTÉ : RMSE = {metrics['rmse']:.4f} "
        f"(environ {metrics['rmse'] * TARGET_UNIT_USD:,.0f} $ d'écart typique), "
        f"MAPE = {metrics['mape_pct']:.1f} %. "
        "Enregistré en MLFLOW par le script de bootstrap après le pipeline."
    )


if __name__ == "__main__":
    main()
