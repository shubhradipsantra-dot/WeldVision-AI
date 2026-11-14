from ultralytics import YOLO
from weld_defect_pipeline10 import run_pipeline, CFG
import sqlite3

DB_PATH = "inspections.db"

# Cache loaded specific models
loaded_models = {}


# ── GENERIC MODEL (weld_defect_pipeline) ─────────────────────────────────────

def run_detection(image_path, output_dir):
    """Run the generic multi-step weld defect pipeline.
    Used when no specific model is selected (model_name is None)."""
    print("USING GENERIC PIPELINE")
    cfg = CFG.copy()
    cfg["output_dir"] = output_dir
    return run_pipeline(image_path, cfg)


# ── SPECIFIC MODEL (YOLO trained via app) ────────────────────────────────────

def get_model_path(model_name):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT model_path FROM trained_models WHERE model_name = ?",
        (model_name,)
    )
    row = cursor.fetchone()
    conn.close()
    if row is None:
        raise Exception(f"Model '{model_name}' not found")
    return row[0]


def get_model(model_name):
    if model_name not in loaded_models:
        model_path = get_model_path(model_name)
        loaded_models[model_name] = YOLO(model_path)
        print(f"[MODEL LOADED] {model_name}")
    return loaded_models[model_name]