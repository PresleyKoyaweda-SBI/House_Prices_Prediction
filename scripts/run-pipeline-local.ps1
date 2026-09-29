#Requires -Version 7.0
<#
.SYNOPSIS
    Dry-run 100% local du pipeline (data_prep → train → evaluate), sans
    aucune ressource Azure (équivalent PowerShell de run-pipeline-local.sh).

.DESCRIPTION
    Utile pendant la personnalisation des composants
    (docs/CUSTOMIZATION_GUIDE.md §7-11) pour valider vite le code sur les
    données du client, avant même que l'infra Azure soit prête.
    `register_model` n'est pas inclus : il nécessite un vrai workspace
    Azure ML. Prérequis : `make install-dev` déjà exécuté.

.PARAMETER RawCsv
    Chemin du CSV source. Défaut : sample_data/california_housing.csv.

.EXAMPLE
    ./scripts/run-pipeline-local.ps1
    ./scripts/run-pipeline-local.ps1 -RawCsv chemin/vers/mes_donnees.csv
#>
param(
    [string]$RawCsv = "sample_data/california_housing.csv"
)

$ErrorActionPreference = "Stop"

$WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $WorkDir | Out-Null

function Step($msg) {
    Write-Host ""
    Write-Host "▶ $msg"
    Write-Host "----------------------------------------"
}

# $ErrorActionPreference ne s'applique pas aux programmes externes (python) : sans ce contrôle,
# un composant en échec laisserait le script continuer et afficher un faux succès.
function Invoke-Python {
    python @args
    if ($LASTEXITCODE -ne 0) {
        throw "Échec de 'python $($args[0])' (code de sortie $LASTEXITCODE)"
    }
}

# Suivi MLflow isolé dans le dossier de travail (supprimé à la fin), sauf si un serveur de
# suivi est déjà configuré : un dry-run local ne doit rien écrire dans le dépôt.
if (-not $env:MLFLOW_TRACKING_URI) {
    $env:MLFLOW_TRACKING_URI = "sqlite:///$($WorkDir.Replace('\', '/'))/mlflow.db"
}

try {
    Step "0/3 — Préparation"
    New-Item -ItemType Directory -Path "$WorkDir/raw_data" | Out-Null
    Copy-Item $RawCsv "$WorkDir/raw_data/"
    Write-Host "✅ Données source : $RawCsv"

    Step "1/3 — data_prep"
    Invoke-Python components/data_prep/src/main.py `
        --raw_data "$WorkDir/raw_data" --test_size 0.2 `
        --train_data "$WorkDir/train_data" --test_data "$WorkDir/test_data"

    Step "2/3 — train"
    Invoke-Python components/train/src/main.py `
        --train_data "$WorkDir/train_data" `
        --model_output "$WorkDir/model_output"

    Step "3/3 — evaluate"
    Invoke-Python components/evaluate/src/main.py `
        --model_input "$WorkDir/model_output" --test_data "$WorkDir/test_data" `
        --evaluation_report "$WorkDir/evaluation_report"

    Write-Host ""
    Write-Host "🎉 Pipeline exécuté localement, sans Azure."
    Write-Host "Métriques :"
    Get-Content "$WorkDir/evaluation_report/metrics.json"
    Write-Host ""
}
finally {
    Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}
