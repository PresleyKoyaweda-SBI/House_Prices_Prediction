# Sécurité

## Principe fondamental

**Ce dépôt ne doit jamais nécessiter le stockage d'un secret client**
(mot de passe, connection string, clé d'API) en clair dans le code, les
fichiers de configuration versionnés ou les secrets GitHub Actions
statiques. L'authentification repose sur l'identité — Managed Identity en
exécution, OIDC fédéré en CI/CD, compte utilisateur (`az login`) en local.

## Identités et RBAC

| Identité | Portée | Rôle | Défini dans |
|---|---|---|---|
| Managed Identity du ML Workspace | Storage Account | `Storage Blob Data Contributor` | `machine_learning_workspace.tf` |
| Managed Identity du ML Workspace | Container Registry | `AcrPull` | `machine_learning_workspace.tf` |
| Managed Identity du ML Workspace | Key Vault | `Key Vault Secrets User` | `machine_learning_workspace.tf` |
| Compute Azure ML (composants) | Workspace (via `AZUREML_ARM_*`) | Enregistrement de modèle | `components/register_model/src/main.py` |

Least privilege : chaque identité ne reçoit que les rôles strictement
nécessaires à son usage. `container_registry_config.admin_enabled` est à
`false` par défaut (`variables.tf`) — les identifiants admin ACR ne sont
activés que si un outil tiers l'exige explicitement (`docker login`).

## Groupe de ressources auto-géré (`ai_..._managed`)

Après un `terraform apply`, la souscription contient **deux** groupes de
ressources, pas un seul : le groupe piloté par Terraform
(`rg-<project>-<env>-<suffix>`) et un second, nommé
`ai_appi-<project>-<env>-<suffix>_<guid>_managed`, qu'**Azure crée seul**.

Ce n'est pas une fuite de configuration ni un doublon de déploiement.
`azurerm_application_insights` fonctionne en mode *workspace-based*
(obligatoire depuis 2023) et a besoin d'un Log Analytics Workspace pour
stocker les données d'ingestion ; comme aucun `workspace_id` explicite
n'est fourni dans `application_insights.tf`, Azure en provisionne un
automatiquement dans ce second groupe. Vérifiable :

```bash
az group show --name <ai_..._managed> --query managedBy -o tsv
# → pointe vers l'App Insights du groupe Terraform (relation "managedBy")
```

Ce groupe suit le cycle de vie de la ressource App Insights qui le
possède : il est supprimé automatiquement par `terraform destroy` (ou
`./scripts/destroy.sh`), sans action manuelle. Aucune ressource à y gérer
ni à sécuriser séparément.

## Secrets

- **Aucun secret n'est commité dans Git.** `.env.example` (versionné) ne
  contient que des identifiants non sensibles (subscription ID, nom de
  workspace) — jamais de mot de passe ou de clé.
- **CI/CD** : authentification Azure via OIDC fédéré
  (`azure/login@v2` avec `client-id`/`tenant-id`/`subscription-id`,
  voir `.github/workflows/cd.yml`) — pas de `AZURE_CLIENT_SECRET`.
  Configurer une [identité fédérée](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
  entre le dépôt GitHub et l'application Microsoft Entra ID du déploiement.
- **Local** : `az login` (compte utilisateur) pour les opérations manuelles
  (`terraform apply`, `az ml job create`).
- **Secrets applicatifs éventuels** (ex : clé d'API tierce fournie par le
  client) : stockés dans le Key Vault provisionné (`key_vault.tf`), jamais
  dans `.tfvars`, `.env` ou le code.

## State Terraform

Stocké dans un storage account Azure dédié (voir
`infrastructure/terraform/README.md`), pas en local — accès par Azure AD
(`use_azuread_auth = true` dans `environments/backend-*.hcl`), jamais par
clé de storage account. Nécessite le rôle `Storage Blob Data Contributor`
sur ce storage account pour chaque identité qui exécute Terraform :
l'utilisateur (`az login`) en local, l'identité fédérée OIDC en CI/CD (même
principe que l'authentification Azure du reste de ce document — aucun
secret statique supplémentaire). Le storage account de state a son propre
resource group (`rg-tfstate-<project>`), séparé de celui de l'infrastructure
applicative, pour ne jamais être supprimé par erreur via
`scripts/destroy.sh`.

## Réseau (optionnel)

Private Endpoints / intégration VNet ne sont **pas déployés par défaut** —
ils ajoutent une complexité opérationnelle réelle (résolution DNS privée,
gestion de sous-réseaux) qui n'est justifiée que par une exigence explicite
du client (isolation réseau réglementaire, absence totale d'exposition
publique). Si requis :

- `container_registry.tf` restreint déjà l'accès public en `prod`
  (`public_network_access_enabled = var.environment != "prod"`) ; ajouter
  l'équivalent (`network_rules`/`public_network_access_enabled`) sur
  `storage_account.tf`, `key_vault.tf` et `machine_learning_workspace.tf`,
  actuellement sans restriction réseau par défaut ;
- ajouter des `azurerm_private_endpoint` + `azurerm_private_dns_zone` par
  service concerné ;
- documenter la décision dans `.agents/value/FREE-TIER-LEDGER.md` ou
  l'équivalent projet (coût, complexité opérationnelle ajoutée).

# TEMPLATE: optional — cette section décrit une extension, pas une exigence
par défaut du starter kit.

## Chiffrement (optionnel)

Le chiffrement au repos est activé par défaut (clés gérées par Microsoft)
sur tous les services provisionnés. Les clés gérées par le client (CMK)
ne sont à activer que si une exigence de conformité l'impose explicitement
— elles ajoutent une dépendance opérationnelle (rotation, disponibilité du
Key Vault) qui doit être justifiée.

## Endpoints d'inférence

`ml/endpoints/online/online-endpoint.yml` utilise `auth_mode: key` par
défaut (accès simple pour prototypage). Pour une intégration avec des
applications internes du client, préférer `auth_mode: aad_token`
(Microsoft Entra ID) — voir
[authentification des endpoints en ligne](https://learn.microsoft.com/azure/machine-learning/how-to-authenticate-online-endpoint).

## Revue de sécurité avant mise en production

Avant un premier déploiement en production pour un client, vérifier :

- [ ] Aucun secret dans l'historique Git (`git log -p` sur les fichiers
      `.tfvars`, `.env*`) ;
- [ ] `admin_enabled` du Container Registry toujours à `false`, sauf besoin
      documenté ;
- [ ] `auth_mode` des endpoints conforme aux exigences du client ;
- [ ] Environnements GitHub `staging`/`production` protégés par une règle
      d'approbation manuelle ;
- [ ] Fédération OIDC configurée (pas de secret Azure statique dans les
      secrets GitHub) ;
- [ ] Réseau/CMK activés uniquement si explicitement requis (voir
      ci-dessus) ;
- [ ] State Terraform sur backend distant (jamais local) avant tout
      déploiement staging/prod, RBAC `Storage Blob Data Contributor`
      accordé uniquement aux identités qui en ont besoin.
