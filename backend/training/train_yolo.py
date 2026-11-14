import os
import shutil
import torch
from ultralytics import YOLO

device = 0 if torch.cuda.is_available() else "cpu"


def train_yolo(
    yaml_path,
    model_name
):
    model = YOLO(
        "yolo11n.pt"
    )

    model.train(
        data=yaml_path,
        epochs=40,
        # imgsz=640,
        batch=16,
        device=device,
        patience=10,
        project="custom_training",
        name=model_name
    )

    best_model = (
        f"custom_training/"
        f"{model_name}/weights/best.pt"
    )

    os.makedirs(
        "custom_models",
        exist_ok=True
    )

    final_model = os.path.join(
        "custom_models",
        f"{model_name}.pt"
    )

    shutil.copy(
        best_model,
        final_model
    )

    return final_model

