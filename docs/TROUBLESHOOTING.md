# 🆘 Troubleshooting - Dépannage

Solutions aux erreurs courantes.

## Erreurs Terraform

### "Provider not found"
```
Error: Unsupported or missing provider
```
**Solution:**
```bash
terraform init -upgrade
terraform validate
```

### "Insufficient privileges"
```
Error: Unauthorized (insufficient privileges)
```
**Solution:**
```bash
az login
az account set --subscription "your-subscription-id"
az account show  # Vérifier
terraform apply
```

### "Resource already exists"
```
Error: A resource with the ID ... already exists
```
**Solution:**
```bash
# Option 1: Changer project_name (génère suffix différent)
# Puis relancer: terraform apply

# Option 2: Importer la ressource existante
terraform import azurerm_resource_group.rg /subscriptions/.../resourceGroups/existing-rg
```

### "terraform.tfvars not found"
```
Error: Required variable... not defined
```
**Solution:**
```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Adapter les valeurs
terraform plan
```

## Erreurs Azure

### "Subscription ID not found"
```
Error: Invalid subscription ID
```
**Solution:**
```bash
az account list --output table
az account set --subscription "correct-id"
```

### "Insufficient permissions for Resource Group"
```
Error: Insufficient permissions... to perform action
```
**Solution:**
Vous avez besoin d'au minimum Contributor role. Contacter votre admin Azure.

## Erreurs Backend distant

### "Error: Backend configuration changed" / "Initialization required"
```
Error: Backend initialization required, please run "terraform init"
```
**Cause :** le backend n'a pas été initialisé avec `-backend-config`, ou
`environments/backend-<env>.hcl` n'existe pas encore. **Solution :**
```bash
make bootstrap-tfstate      # une seule fois par client/tenant
cp environments/backend-dev.hcl.example environments/backend-dev.hcl
# éditer avec les valeurs affichées par bootstrap-tfstate
make tf-init ENV=dev
```

### "AuthorizationPermissionMismatch" sur le storage account de state
```
Error: containers.Client#Create: ... AuthorizationPermissionMismatch
```
**Cause :** le backend utilise Azure AD (`use_azuread_auth = true`, pas de
clé de storage account) — l'identité qui exécute `terraform` (utilisateur
local ou identité OIDC en CI) n'a pas le rôle `Storage Blob Data
Contributor` sur ce storage account précis. **Solution :** voir la sortie
de `make bootstrap-tfstate` (commande `az role assignment create` affichée
en fin de script) ou `docs/SECURITY.md`.

## Erreurs Terraform State

### "State file locked"
```
Error: Error acquiring the state lock
```
**Solution:**
```bash
# Ne pas interrompre Terraform!
# Attendre quelques minutes
# Ou supprimer le lock (dangereux):
rm .terraform.lock.hcl
```

### "State file not found"
```
Error: Error loading state
```
**Solution (normale pour première utilisation):**
```bash
terraform init  # Recréer
terraform apply  # Premier déploiement
```

## Erreurs Réseau

### "Unable to connect to Azure"
```
Error: context deadline exceeded
```
**Solutions:**
```bash
# Vérifier la connexion internet
ping 8.8.8.8

# Vérifier Azure CLI
az account show

# Réessayer
terraform apply
```

### "Network connectivity issues"
```
Error: dial tcp: lookup on ...: no such host
```
**Solution:**
Vérifier votre VPN/Proxy/Firewall.

## Erreurs de Validation

### "Invalid variable value"
```
Error: Error in variable validation: ...
```
**Solution:**
Vérifier les valeurs dans terraform.tfvars:
```hcl
# Doit être valide:
location = "canadacentral"  # Pas "canada-central"
environment = "dev"         # Pas "development"
project_name = "my-project" # kebab-case uniquement
```

## Erreurs de Ressources

### "Storage account name already exists"
```
Error: storage account ... already exists
```
**Solution:**
Le nom du compte storage doit être unique globalement. Changer:
```hcl
project_name = "mon-projet-2"  # Ajouter numéro
```

### "Key Vault name not available"
```
Error: ... name is not available
```
**Solution:**
Le nom du Key Vault doit être unique. Changer:
```hcl
project_name = "autre-nom"
```

## Erreurs RBAC

### "Operation not permitted (no permissions)"
```
Error: authorization failed
```
**Solution:**
Vérifier les RBAC assignments. Vous devez avoir:
- Owner ou Contributor sur la subscription
- OU des permissions spécifiques pour chaque ressource

## Checker les Logs

### Logs Terraform Détaillés
```bash
TF_LOG=DEBUG terraform apply
# Produit beaucoup de output, à rechercher l'erreur

# Sauvegarder les logs
TF_LOG=DEBUG terraform apply 2>&1 | tee terraform-debug.log
```

### Logs Azure CLI
```bash
az account show -o jsonc
az storage account list --output table
az keyvault list --output table
```

## Erreurs Azure ML CLI v2 / Python

### "az: 'ml' is not in the 'az' command group"
```
ERROR: az ml: 'ml' is not in the 'az' command group.
```
**Solution:**
```bash
az extension add -n ml
az extension update -n ml
```

### "import file mismatch" en exécutant pytest sur plusieurs composants
```
import file mismatch:
imported module 'test_component' has this __file__ attribute: ...
```
**Cause :** plusieurs `components/*/tests/test_component.py` portent le même
nom de fichier. **Déjà résolu** dans ce dépôt via
`addopts = "--import-mode=importlib"` dans `pyproject.toml`
(`[tool.pytest.ini_options]`) — si l'erreur réapparaît, vérifier que cette
option n'a pas été retirée.

### "`$schema` ne référence pas un schéma Azure ML officiel"
Sortie de `python tools/validate_yaml.py` ou de la CI. **Solution :**
vérifier que le fichier YAML commence bien par
`$schema: https://azuremlschemas.azureedge.net/latest/<type>.schema.json`
(voir un fichier existant sous `ml/` ou `components/*/component.yml` comme
référence).

### "Failed to pull Docker image ... could not authenticate with the Docker registry"
```
UserError: Failed to pull Docker image <acr>.azurecr.io/azureml/... This
error may occur because the compute could not authenticate with the
Docker registry to pull the image.
```
**Cause :** le Container Registry de ce starter kit a l'admin user
désactivé (`admin_enabled = false`, voir `docs/SECURITY.md`). Dans ce cas,
AmlCompute pull les images avec **sa propre identité managée**, pas celle
du workspace — un `AcrPull` accordé uniquement à l'identité du workspace
ne suffit pas (constaté sur un test réel malgré un RBAC workspace→ACR
correctement propagé). **Solution :** `ml/compute/compute-cluster.yml`
déclare `identity: {type: system_assigned}` ; après création du compute,
accorder `AcrPull` à son identité (voir README — Quick Start, section
"Assets Azure ML"). Ne **jamais** activer `admin_enabled` sur l'ACR comme
contournement (violerait la posture de sécurité documentée).

### "AuthorizationFailed" sur `models/versions/read` dans register_model
```
azure.core.exceptions.HttpResponseError: (AuthorizationFailed) The client
'...' with object id '<principal_id du compute>' does not have
authorization to perform action
'Microsoft.MachineLearningServices/workspaces/models/versions/read'
```
**Cause :** une fois l'identité propre du compute créée (voir bug
ci-dessus), c'est **cette identité** — pas celle du workspace — qui est
utilisée par le SDK `azure-ai-ml` (`MLClient`) appelé depuis le code des
composants (ex. `register_model_job` → `ml_client.models.create_or_update`).
`AcrPull` seul ne couvre pas les appels au plan de contrôle Azure ML.
**Solution :** accorder également le rôle `AzureML Data Scientist` à
l'identité du compute, à la portée du workspace (voir README — Quick
Start, section "Assets Azure ML").

### "ImportError: cannot import name '_T' from 'marshmallow.fields'" dans un job Azure ML
```
File ".../azure/ai/ml/_schema/core/fields.py", line 19, in <module>
    from marshmallow.fields import _T, Field, Nested
ImportError: cannot import name '_T' from 'marshmallow.fields'
```
**Cause réelle :** `azure-ai-ml==1.19.*` (mi-2024) est trop ancien — son
code interne importe un symbole privé (`marshmallow.fields._T`) retiré des
versions récentes de marshmallow, alors même que sa contrainte déclarée
(`marshmallow<4.0.0,>=3.5`) est satisfaite. Épingler uniquement
`marshmallow<4.0.0` ou une version 3.x exacte **ne suffit pas** — constaté
sur un test réel : `marshmallow==3.26.2` (une version 3.x récente) n'a pas
non plus `_T`. **Solution :** mettre à jour `azure-ai-ml` vers une version
récente et compatible (`azure-ai-ml==1.34.*` dans ce starter kit —
vérifiée fonctionnelle), pas seulement contraindre marshmallow. Après
modification de `conda.yml`, réenregistrer l'environnement (§13 de
`CUSTOMIZATION_GUIDE.md`) ; ne pas fixer de `version:` dans
`training-environment.yml` pour laisser la CLI en générer une nouvelle à
chaque réenregistrement — un `version:` figé fait échouer la commande
(`Environment ... with version ... is already registered and cannot be
changed`).

### "error: Multiple top-level packages discovered in a flat-layout" sur `pip install -e ".[dev]"`
```
error: Multiple top-level packages discovered in a flat-layout: ['ml', 'notebooks', 'components', 'sample_data', 'environments', 'infrastructure']
```
**Cause :** ce dépôt a plusieurs dossiers à sa racine — sans configuration
explicite, setuptools refuse de deviner lequel packager. **Déjà résolu**
dans ce dépôt via `[tool.setuptools] py-modules = []` dans `pyproject.toml`
(ce `pyproject.toml` ne sert qu'à déclarer des dépendances, aucun package
Python n'est réellement construit ici — voir le commentaire au-dessus) —
si l'erreur réapparaît, vérifier que cette option n'a pas été retirée.

### `pip-audit` échoue après avoir mis à jour `mlflow`, `azureml-mlflow` ou `cryptography`
**Contexte :** ces trois paquets sont verrouillés ensemble et **ne peuvent
pas être montés indépendamment** :
- `mlflow` est épinglé exactement à `3.15.0` (pas de wildcard) car
  `azureml-mlflow==1.62.0.post6` plafonne `mlflow-skinny<=3.15.0` — une
  version mlflow plus récente casse la résolution des dépendances.
- `mlflow==3.15.0` exige lui-même `cryptography<50,>=43.0.0` —
  impossible de monter `cryptography` à 50.0.0 (qui corrige
  PYSEC-2026-3552) sans casser mlflow. Cette CVE ne touche que le
  déchiffrement PKCS#7/S-MIME, jamais utilisé dans ce repo — exclue via
  `--ignore-vuln PYSEC-2026-3552` dans `.github/workflows/ci.yml`.

**Solution :** pour monter mlflow au-delà de 3.15.0, vérifier d'abord (via
les métadonnées PyPI de la dernière version d'`azureml-mlflow`) que son
plafond `mlflow-skinny` a été relevé en conséquence, et retirer l'exception
`PYSEC-2026-3552` seulement si `cryptography>=50.0.0` devient compatible
avec la nouvelle contrainte mlflow. Ne jamais épingler un wildcard
(`mlflow==3.15.*`) sur ce genre de plafond exact — un futur patch pourrait
le dépasser silencieusement.

### Le pipeline échoue avec une entrée/sortie de composant introuvable
```
Error: ... has no output/input named ...
```
**Solution :** les noms d'`inputs`/`outputs` dans `component.yml` et dans
`ml/pipelines/training-pipeline.yml` (`${{parent.jobs...outputs.<nom>}}`)
doivent correspondre exactement. Valider hors ligne avant soumission :
```bash
python -c "from azure.ai.ml import load_job; load_job(source='ml/pipelines/training-pipeline.yml')"
```
(couvert automatiquement par `tests/integration/test_ml_assets_load.py`).

## Contacter le Support

Si l'erreur persiste:

1. **Vérifier la documentation:**
   - [README.md](../README.md)
   - [ARCHITECTURE.md](ARCHITECTURE.md)
   - [CUSTOMIZATION_GUIDE.md](CUSTOMIZATION_GUIDE.md)
   - [MLOPS_LIFECYCLE.md](MLOPS_LIFECYCLE.md)

2. **Vérifier les logs:**
   - `terraform plan` output
   - `TF_LOG=DEBUG` logs
   - Studio Azure ML (onglet "Outputs + logs" du job)

3. **Consulter les ressources:**
   - [Terraform Docs](https://www.terraform.io/docs)
   - [Azure ML CLI v2 Docs](https://learn.microsoft.com/azure/machine-learning/how-to-configure-cli)
   - [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

