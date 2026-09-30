# Endpoint batch

Le modèle est déployé sur un **endpoint batch** (`batch/`) : inférence différée sur de gros
volumes, déclenchée à la demande ou planifiée.

Ce choix découle du cas d'usage (voir `notebooks/01_Exploration.ipynb`) : le modèle sert à
**comparer et prioriser des districts** (zones sous-évaluées, valeur des garanties d'un
portefeuille, études de logement). On note tous les districts d'un coup, périodiquement, à
partir de données de recensement qui changent peu : aucune réponse temps réel n'est nécessaire.
Le batch tourne sur `cpu-cluster`, qui redescend à zéro nœud, alors qu'un endpoint en ligne
facturerait une VM en permanence.

L'exemple d'endpoint en ligne du starter kit a été supprimé. Si un besoin temps réel apparaît
(une application qui demande l'estimation d'un district à la volée), le recréer à partir de la
[documentation Microsoft](https://learn.microsoft.com/azure/machine-learning/how-to-deploy-online-endpoints).

N'introduisez pas d'AKS ou d'infrastructure de service dédiée sans besoin explicite
(scalabilité extrême, contrôle réseau avancé, etc.).
