# Données d'exemple (SAMPLE)

`training_data.csv` est un jeu de données synthétique minimal (20 lignes,
3 features numériques + une cible binaire `target`) utilisé uniquement pour
faire tourner le pipeline `ml/pipelines/training-pipeline.yml` de bout en bout
sans dépendre d'une source de données client.

**SAMPLE — à supprimer.** Ce dossier n'a aucune valeur métier. Dès qu'une
vraie source de données est branchée (voir `docs/CUSTOMIZATION_GUIDE.md`,
section « Source de données »), supprimez ce dossier et mettez à jour
`ml/data/sample-data-asset.yml` en conséquence.
