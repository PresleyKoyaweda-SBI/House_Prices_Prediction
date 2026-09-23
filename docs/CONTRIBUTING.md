# Contribuer

## Workflow de développement

1. Créer une branche `feature/{ticket}-{slug}`, `fix/...` ou `hotfix/...`
2. Apporter les modifications
3. Écrire/adapter les tests
4. Lancer les tests : `make test`
5. Lancer le lint : `make lint`
6. Commiter avec les Conventional Commits
7. Ouvrir une pull request vers `main`

`main` est protégée : jamais de push direct.

## Convention de commit

- `feat:` nouvelle fonctionnalité
- `fix:` correction de bug
- `docs:` documentation
- `test:` tests
- `refactor:` refactorisation sans changement de comportement
- `chore:` tâche de maintenance (dépendances, config)

Exemple : `feat: ajouter le composant feature_engineering`

## Ajouter un composant

```bash
make new-component NAME=mon_composant
```

Voir [MLOPS_LIFECYCLE.md](MLOPS_LIFECYCLE.md) pour l'intégration du nouveau
composant au pipeline d'entraînement.
