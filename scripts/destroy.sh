#!/bin/bash

# Destroy script - Destruction sécurisée

echo "⚠️  ATTENTION: Destruction de l'infrastructure"
echo "=============================================="
echo ""
echo "Cette action va SUPPRIMER toutes les ressources Azure!"
echo ""

read -p "Êtes-vous certain? (yes/no) " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]
then
    echo "❌ Destruction annulée"
    exit 1
fi

echo ""
echo "🔍 Sauvegarde des données avant destruction..."
cd infrastructure/terraform
terraform output -json > backup-before-destroy.json
echo "✅ Sauvegardés dans backup-before-destroy.json"

echo ""
echo "📊 Affichage du plan de destruction..."
terraform plan -destroy

read -p "Confirmer la destruction? (yes/no) " -r
echo

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]
then
    echo "Destruction en cours..."
    terraform destroy -auto-approve
    echo "✅ Destruction complète"
else
    echo "❌ Destruction annulée"
    exit 1
fi
