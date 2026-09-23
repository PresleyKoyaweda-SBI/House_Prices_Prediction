#!/bin/bash
set -euo pipefail

# Dry-run 100% local du pipeline (data_prep → train → evaluate), sans
# aucune ressource Azure. Utile pendant la personnalisation des composants
# (docs/CUSTOMIZATION_GUIDE.md §7-11) pour valider vite le code sur les
# données du client, avant même que l'infra Azure soit prête.
#
# `register_model` n'est pas inclus : il nécessite un vrai workspace Azure
# ML (voir components/register_model/README.md) — le rapport de métriques
# produit ici (evaluation_report/metrics.json) suffit à juger si le modèle
# passerait le seuil de gating.
#
# Prérequis : `make install-dev` (dépendances du pyproject.toml déjà
# installées dans l'environnement Python actif).
#
# Usage :
#   ./scripts/run-pipeline-local.sh [chemin_csv]   (défaut : sample_data/training_data.csv)

RAW_CSV="${1:-sample_data/training_data.csv}"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

step() { echo ""; echo "▶ $1"; echo "----------------------------------------"; }

step "0/3 — Préparation"
mkdir -p "$WORKDIR/raw_data"
cp "$RAW_CSV" "$WORKDIR/raw_data/"
echo "✅ Données source : $RAW_CSV"

step "1/3 — data_prep"
python components/data_prep/src/main.py \
  --raw_data "$WORKDIR/raw_data" --test_size 0.2 \
  --train_data "$WORKDIR/train_data" --test_data "$WORKDIR/test_data"

step "2/3 — train"
python components/train/src/main.py \
  --train_data "$WORKDIR/train_data" --n_estimators 100 \
  --model_output "$WORKDIR/model_output"

step "3/3 — evaluate"
python components/evaluate/src/main.py \
  --model_input "$WORKDIR/model_output" --test_data "$WORKDIR/test_data" \
  --evaluation_report "$WORKDIR/evaluation_report"

echo ""
echo "🎉 Pipeline exécuté localement, sans Azure."
echo "Métriques :"
cat "$WORKDIR/evaluation_report/metrics.json"
echo ""
