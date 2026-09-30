"""Entraînement du modèle California Housing.

Reprend à l'identique le pipeline retenu dans notebooks/01_Exploration.ipynb :
feature engineering -> imputation -> XGBoost, avec cible en log et bornage des prédictions.

La comparaison des modèles relève de l'exploration et reste dans le notebook : ce composant ne
connaît que le modèle retenu (XGBoost optimisé, section 11.2). Ses hyperparamètres, eux, viennent
de `model_config.json` (copie de outputs/best_model_config.json produit par le notebook), pour
que le résultat de l'optimisation soit versionné avec le code. Si le notebook retient un jour un
autre modèle, ce fichier est à adapter : c'est un changement de code, relu comme tel.

Le modèle est écrit au format MLflow et prend en entrée les 8 colonnes brutes : aucun
prétraitement n'est nécessaire côté appelant (evaluate, endpoint).

Une différence volontaire avec le notebook : il réentraîne le modèle final sur 100 % des données
(section 12.3), alors qu'ici je n'entraîne que sur le jeu `train` de data_prep. Le jeu `test`
reste ainsi inédit pour `evaluate`, dont la métrique décide de l'enregistrement du modèle.
"""

import argparse
import json
from pathlib import Path

import mlflow
import numpy as np
import pandas as pd
from mlflow.models import infer_signature
from sklearn.compose import TransformedTargetRegressor
from sklearn.impute import SimpleImputer
from sklearn.metrics import root_mean_squared_error
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import FunctionTransformer
from xgboost import XGBRegressor

DEFAULT_CONFIG = Path(__file__).parent / "model_config.json"
# Graine du notebook, appliquée si la config ne fixe pas random_state.
RANDOM_STATE = 42
# Nom du modèle retenu tel que le notebook l'écrit dans best_model_config.json ("members").
MODEL_NAME = "XGBoost"
REQUIRED_CONFIG_KEYS = [
    "model",
    "members",
    "features",
    "target",
    "use_log_target",
    "clip_predictions",
    "target_bounds",
]

# Villes de référence du feature engineering (voir notebook, section 5.2).
CITIES = {
    "San Francisco": (37.7749, -122.4194),
    "Los Angeles": (34.0522, -118.2437),
    "San Diego": (32.7157, -117.1611),
    "San Jose": (37.3382, -121.8863),
    "Sacramento": (38.5816, -121.4944),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train_data", type=str, required=True)
    parser.add_argument("--model_config", type=str, default=str(DEFAULT_CONFIG))
    parser.add_argument("--model_output", type=str, required=True)
    return parser.parse_args()


def haversine_km(lat, lon, lat0: float, lon0: float):
    # Distance à vol d'oiseau (km) entre chaque district et un point de référence.
    lat, lon, lat0, lon0 = map(np.radians, (lat, lon, lat0, lon0))
    a = np.sin((lat - lat0) / 2) ** 2 + np.cos(lat) * np.cos(lat0) * np.sin((lon - lon0) / 2) ** 2
    return 6371 * 2 * np.arcsin(np.sqrt(a))


def add_features(df: pd.DataFrame) -> pd.DataFrame:
    # Feature engineering sans état (identique au notebook, section 9.2).
    df = df.copy()
    df["Households"] = df["Population"] / df["AveOccup"]
    df["BedrmsPerRoom"] = df["AveBedrms"] / df["AveRooms"]
    df["PeoplePerRoom"] = df["AveOccup"] / df["AveRooms"]
    df["IncomePerOccupant"] = df["MedInc"] / df["AveOccup"]
    dist_cols = []
    for city, (lat0, lon0) in CITIES.items():
        col = "Dist_" + city.replace(" ", "")
        df[col] = haversine_km(df["Latitude"], df["Longitude"], lat0, lon0)
        dist_cols.append(col)
    df["DistNearestCity"] = df[dist_cols].min(axis=1)
    df["RotLatLon45"] = df["Latitude"] + df["Longitude"]
    df["RotLatLonM45"] = df["Latitude"] - df["Longitude"]
    # Division par zéro possible en production : l'infini devient une valeur manquante imputée.
    return df.replace([np.inf, -np.inf], np.nan)


def is_extreme_district(X: pd.DataFrame) -> pd.Series:
    # Petits districts aux ratios peu fiables (notebook, section 6.1).
    return (X["AveOccup"] > 10) | (X["AveRooms"] > 20)


def load_config(path: Path) -> dict:
    # J'échoue clairement sur une config incomplète, ou si le notebook a retenu un autre modèle
    # que celui que ce composant sait entraîner, plutôt que sur une erreur obscure plus loin.
    config = json.loads(path.read_text(encoding="utf-8"))
    missing = [k for k in REQUIRED_CONFIG_KEYS if k not in config]
    if missing:
        raise ValueError(f"Clés manquantes dans {path.name} : {missing}")
    if list(config["members"]) != [MODEL_NAME]:
        raise ValueError(
            f"{path.name} décrit {list(config['members'])}, mais ce composant n'entraîne que "
            f"{MODEL_NAME}. Si le notebook a retenu un autre modèle, adapter "
            "components/train/src/main.py."
        )
    return config


def build_estimator(config: dict) -> TransformedTargetRegressor:
    low, high = config["target_bounds"]
    use_log, clip = config["use_log_target"], config["clip_predictions"]

    # Fonctions internes : cloudpickle les sérialise par valeur, le modèle enregistré ne dépend
    # donc pas de ce fichier pour être rechargé.
    def forward(y):
        return np.log1p(y) if use_log else y

    def inverse(y):
        y = np.expm1(y) if use_log else y
        return np.clip(y, low, high) if clip else y

    params = {"random_state": RANDOM_STATE, **config["members"][MODEL_NAME]}
    # Dans le notebook, n_jobs=1 car la validation croisée parallélise déjà ; ici il n'y a
    # qu'un entraînement, j'utilise donc tous les coeurs du nœud de calcul.
    params["n_jobs"] = -1
    pipe = Pipeline(
        [
            ("features", FunctionTransformer(add_features)),
            # Imputation seule : un arbre ne dépend que de l'ordre des valeurs, aucune mise à
            # l'échelle n'est utile. Les données de référence n'ont aucun manquant : c'est une
            # sécurité pour la production (donnée incomplète, division par zéro dans
            # add_features()).
            ("impute", SimpleImputer(strategy="median")),
            ("model", XGBRegressor(**params)),
        ]
    )
    return TransformedTargetRegressor(
        regressor=pipe, func=forward, inverse_func=inverse, check_inverse=False
    )


def main() -> None:
    args = parse_args()
    config = load_config(Path(args.model_config))

    train_df = pd.read_csv(Path(args.train_data) / "train.csv")
    missing = [c for c in [*config["features"], config["target"]] if c not in train_df.columns]
    if missing:
        raise ValueError(f"Colonnes manquantes dans train.csv : {missing}")
    X_train = train_df[config["features"]]
    y_train = train_df[config["target"]]
    # Décision de l'ablation du notebook (section 9.4) : false par défaut, les districts extrêmes
    # apportent de l'information utile. Si elle est activée, le filtre ne porte que sur
    # l'entraînement : evaluate mesure toujours l'erreur sur tous les districts.
    if config.get("drop_extreme_districts"):
        keep = ~is_extreme_district(X_train)
        X_train, y_train = X_train[keep], y_train[keep]

    model = build_estimator(config)
    with mlflow.start_run():
        mlflow.log_params(
            {
                "model": config["model"],
                "use_log_target": config["use_log_target"],
                "clip_predictions": config["clip_predictions"],
                "drop_extreme_districts": bool(config.get("drop_extreme_districts")),
                "n_train_rows": len(X_train),
            }
        )
        # Tous les hyperparamètres, pour retrouver dans MLflow le modèle exact du notebook.
        mlflow.log_params(
            {f"xgboost__{key}": value for key, value in config["members"][MODEL_NAME].items()}
        )
        mlflow.log_dict(config, "model_config.json")
        model.fit(X_train, y_train)

        # Erreur sur les données d'entraînement : comparée à la RMSE de test d'evaluate, elle
        # mesure le sur-apprentissage, comme l'overfit_gap du notebook (section 10).
        train_rmse = float(root_mean_squared_error(y_train, model.predict(X_train)))
        mlflow.log_metric("train_rmse", train_rmse)

        signature = infer_signature(X_train.head(100), model.predict(X_train.head(100)))
        # MLflow 3.15 sérialise par défaut en "skops", qui refuse les types internes de
        # scikit-learn et XGBoost (échec constaté même sur un simple RandomForest) :
        # cloudpickle est nécessaire. Le modèle ne doit être chargé que depuis une source de
        # confiance (le workspace Azure ML du projet).
        mlflow.sklearn.save_model(
            model,
            args.model_output,
            signature=signature,
            serialization_format=mlflow.sklearn.SERIALIZATION_FORMAT_CLOUDPICKLE,
        )

    print(
        f"Modèle '{config['model']}' entraîné sur {len(X_train)} districts "
        f"(RMSE d'entraînement : {train_rmse:.4f})"
    )


if __name__ == "__main__":
    main()
