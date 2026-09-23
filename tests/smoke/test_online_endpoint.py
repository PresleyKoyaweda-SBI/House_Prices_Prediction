"""Tests smoke — vérification post-déploiement d'un endpoint en ligne réel.

Contrairement aux tests unitaires/intégration, ces tests appellent une
ressource Azure réellement déployée. Ils sont ignorés (skip) tant que les
variables d'environnement nécessaires ne sont pas fournies — ce qui est le
cas par défaut en local et en CI sur les branches de développement.

Exécution (après déploiement, ex: étape de validation dev dans
.github/workflows/cd.yml) :
    ONLINE_ENDPOINT_URL=https://... ONLINE_ENDPOINT_KEY=... pytest tests/smoke/
"""

import os

import pytest
import requests

ENDPOINT_URL = os.environ.get("ONLINE_ENDPOINT_URL")
ENDPOINT_KEY = os.environ.get("ONLINE_ENDPOINT_KEY")

pytestmark = pytest.mark.skipif(
    not ENDPOINT_URL or not ENDPOINT_KEY,
    reason="ONLINE_ENDPOINT_URL / ONLINE_ENDPOINT_KEY non définis — endpoint non déployé.",
)


def test_endpoint_responds_successfully() -> None:
    # SAMPLE — adapter le payload au schéma d'entrée réel du modèle client.
    payload = {
        "input_data": {
            "columns": ["feature_1", "feature_2", "feature_3"],
            "data": [[5.1, 3.5, 1.4]],
        }
    }
    response = requests.post(
        ENDPOINT_URL,
        json=payload,
        headers={
            "Authorization": f"Bearer {ENDPOINT_KEY}",
            "Content-Type": "application/json",
        },
        timeout=30,
    )

    assert response.status_code == 200, response.text
