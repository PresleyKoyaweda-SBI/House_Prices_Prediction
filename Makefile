.PHONY: help install install-dev lint format typecheck test test-unit test-integration test-smoke \
	validate-yaml new-component run-local \
	bootstrap-tfstate bootstrap-project tf-init tf-fmt tf-fmt-check tf-validate tf-plan tf-apply tf-output \
	deploy-dev deploy-staging deploy-prod \
	clean

TF_DIR := infrastructure/terraform

help:
	@echo "Installation :"
	@echo "  make install          - Installer les dépendances (runtime)"
	@echo "  make install-dev      - Installer les dépendances (runtime + dev)"
	@echo ""
	@echo "Qualité du code :"
	@echo "  make lint             - Lint (ruff)"
	@echo "  make format           - Formatage (ruff)"
	@echo "  make typecheck        - Vérification de types (mypy)"
	@echo ""
	@echo "Tests :"
	@echo "  make test             - Tous les tests"
	@echo "  make test-unit        - Tests unitaires"
	@echo "  make test-integration - Tests d'intégration"
	@echo "  make test-smoke       - Tests smoke (post-déploiement)"
	@echo ""
	@echo "Azure ML :"
	@echo "  make new-component NAME=x - Générer un nouveau composant"
	@echo "  make validate-yaml    - Valider la syntaxe des YAML ml/ et components/"
	@echo "  make run-local        - Pipeline complet en local, sans Azure (data_prep→train→evaluate)"
	@echo ""
	@echo "Terraform :"
	@echo "  make tf-init ENV=dev  - terraform init (backend distant, voir environments/backend-<ENV>.hcl)"
	@echo "  make tf-fmt           - terraform fmt (écrit les corrections)"
	@echo "  make tf-fmt-check     - terraform fmt -check (CI)"
	@echo "  make tf-validate      - terraform validate"
	@echo "  make tf-plan ENV=dev  - terraform plan -var-file=environments/<ENV>.tfvars"
	@echo "  make tf-apply ENV=dev - terraform apply -var-file=environments/<ENV>.tfvars"
	@echo "  make tf-output        - Afficher les outputs Terraform"
	@echo ""
	@echo "Déploiement par environnement :"
	@echo "  make deploy-dev       - Déployer l'infrastructure dev"
	@echo "  make deploy-staging   - Déployer l'infrastructure staging"
	@echo "  make deploy-prod      - Déployer l'infrastructure prod"
	@echo ""
	@echo "Nettoyage :"
	@echo "  make clean            - Supprimer les artefacts locaux"
	@echo ""
	@echo "Premier déploiement d'un projet :"
	@echo "  make bootstrap-project ENV=dev - Infra + pipeline en une commande (après clone)"

# Installation
install:
	pip install .

install-dev:
	pip install -e ".[dev,notebooks]"

# Qualité du code
lint:
	ruff check .

format:
	ruff format .

typecheck:
	mypy components tools

# Tests
test:
	pytest

test-unit:
	pytest tests/unit/ -v

test-integration:
	pytest tests/integration/ -v

test-smoke:
	pytest tests/smoke/ -v

# Azure ML
new-component:
	python tools/create_component.py $(NAME)

validate-yaml:
	python tools/validate_yaml.py

run-local:
	./scripts/run-pipeline-local.sh

# Terraform
ENV ?= dev

# Bootstrap du storage account de state Terraform — une seule fois par
# client/tenant, avant le tout premier `make tf-init`. Voir
# infrastructure/terraform/README.md.
bootstrap-tfstate:
	./scripts/bootstrap-tfstate.sh

# Backend distant (state Terraform) — voir environments/backend-<ENV>.hcl,
# à créer à partir de environments/backend-<ENV>.hcl.example une fois le
# storage account de state provisionné (make bootstrap-tfstate). Voir
# infrastructure/terraform/README.md.
tf-init:
	cd $(TF_DIR) && terraform init -backend-config=../../environments/backend-$(ENV).hcl

tf-fmt:
	cd $(TF_DIR) && terraform fmt -recursive

tf-fmt-check:
	cd $(TF_DIR) && terraform fmt -check -recursive

tf-validate:
	cd $(TF_DIR) && terraform validate

tf-plan:
	cd $(TF_DIR) && terraform plan -var-file=../../environments/$(ENV).tfvars

tf-apply:
	cd $(TF_DIR) && terraform apply -var-file=../../environments/$(ENV).tfvars

tf-output:
	cd $(TF_DIR) && terraform output

deploy-dev:
	$(MAKE) tf-apply ENV=dev

deploy-staging:
	$(MAKE) tf-apply ENV=staging

deploy-prod:
	$(MAKE) tf-apply ENV=prod

# Premier déploiement d'un projet (après clone)
bootstrap-project:
	./scripts/bootstrap-project.sh $(ENV)

# Nettoyage
clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	rm -rf .pytest_cache .ruff_cache .mypy_cache build dist *.egg-info .coverage htmlcov
