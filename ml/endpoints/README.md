# Endpoints (optionnel)

Deux familles d'exemples sont fournies — **choisissez celle adaptée au
besoin réel du client et supprimez l'autre** (ne déployez jamais les deux
par défaut) :

- `online/` — inférence temps réel synchrone (API REST), pour une prédiction
  à la demande sur une requête unique ou un petit lot.
- `batch/` — inférence différée sur de gros volumes de données, planifiée ou
  déclenchée à la demande.

# TEMPLATE: optional — dans la majorité des cas, un seul des deux modèles
de déploiement est nécessaire. Un endpoint managé Azure ML (online ou batch)
suffit pour la quasi-totalité des cas d'usage ; n'introduisez pas d'AKS ou
d'infrastructure de service dédiée sans besoin explicite (scalabilité
extrême, contrôle réseau avancé, etc.).
