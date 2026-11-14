import os
import yaml


def create_dataset_yaml(dataset_dir):
    yaml_path = os.path.join(
        dataset_dir,
        "data.yaml"
    )

    data = {
        "path": os.path.abspath(dataset_dir),
        "train": "images",
        "val": "images",
        "nc": 2,
        "names": [
            "Porosity",
            "Spatter"
        ]
    }

    with open(
        yaml_path,
        "w"
    ) as f:
        yaml.dump(
            data,
            f,
            sort_keys=False
        )

    return yaml_path