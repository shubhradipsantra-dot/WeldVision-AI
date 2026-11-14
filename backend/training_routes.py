import os
import uuid
import shutil
import sqlite3
from datetime import datetime, timezone
from fastapi import APIRouter, BackgroundTasks, UploadFile, File, HTTPException
from pydantic import BaseModel
from typing import List
from training.extract_frames import extract_frames
from training.auto_label import auto_annotate_frames
from training.augment_dataset import augment_dataset
from training.create_dataset_yaml import create_dataset_yaml
from training.train_yolo import train_yolo

# FIX: Import the new function name instead of normalize_orientation
from image_orientation import normalize_and_convert

router = APIRouter()

TRAIN_DIR = "training_uploads"
DB_PATH = "inspections.db"
os.makedirs(TRAIN_DIR, exist_ok=True)

TRAIN_JOBS = {}

def _register_model(model_name: str, model_path: str):
    now = datetime.now(timezone.utc).isoformat()
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        INSERT INTO trained_models (model_name, model_path, created_at)
        VALUES (?, ?, ?)
        ON CONFLICT(model_name) DO UPDATE SET model_path = excluded.model_path,
                                              created_at  = excluded.created_at
        """,
        (model_name, model_path, now),
    )
    conn.commit()
    conn.close()

def train_job(job_id: str, video_path: str):
    TRAIN_JOBS[job_id]["status"] = "extracting"
    TRAIN_JOBS[job_id]["progress"] = 10
    
    frame_dir = os.path.join("training_frames", job_id)
    num_frames = extract_frames(video_path, frame_dir, sample_rate_sec=1)
    print(f"[train_job] Extracted {num_frames} frames to {frame_dir}")

    TRAIN_JOBS[job_id]["status"] = "annotating"
    TRAIN_JOBS[job_id]["progress"] = 15
    
    dataset_dir = os.path.join("datasets", job_id)
    auto_annotate_frames(frame_dir, dataset_dir, TRAIN_JOBS, job_id)

    img_dir = os.path.join(dataset_dir, "images")
    lbl_dir = os.path.join(dataset_dir, "labels")
    img_list = os.listdir(img_dir) if os.path.exists(img_dir) else []
    print(f"[train_job] images={len(img_list)}  labels_dir_exists={os.path.exists(lbl_dir)}")

    if not img_list:
        TRAIN_JOBS[job_id]["status"] = "failed"
        TRAIN_JOBS[job_id]["error"] = (
            "No images were produced during annotation. "
            "Check that the extracted frames are valid JPEGs and that "
            "the generic detection model (weld_defect_pipeline) is running."
        )
        return

    TRAIN_JOBS[job_id]["status"] = "augmenting"
    TRAIN_JOBS[job_id]["progress"] = 45
    augment_dataset(img_dir, lbl_dir, copies_per_image=5)

    TRAIN_JOBS[job_id]["status"] = "creating_dataset"
    TRAIN_JOBS[job_id]["progress"] = 50
    yaml_path = create_dataset_yaml(dataset_dir)

    TRAIN_JOBS[job_id]["status"] = "training"
    TRAIN_JOBS[job_id]["progress"] = 70
    best_model = train_yolo(yaml_path, job_id)

    # Immediately register the model in the database so it appears in Existing Models
    default_name = f"model_{job_id[:8]}"
    _register_model(default_name, best_model)

    TRAIN_JOBS[job_id]["status"] = "completed"
    TRAIN_JOBS[job_id]["progress"] = 100
    TRAIN_JOBS[job_id]["model_path"] = best_model
    TRAIN_JOBS[job_id]["model_name"] = default_name

def train_job_images(job_id: str, frame_dir: str):
    """Background task for uploaded image folders (skips frame extraction)."""
    TRAIN_JOBS[job_id]["status"] = "annotating"
    TRAIN_JOBS[job_id]["progress"] = 10

    dataset_dir = os.path.join("datasets", job_id)
    auto_annotate_frames(frame_dir, dataset_dir, TRAIN_JOBS, job_id)

    img_dir = os.path.join(dataset_dir, "images")
    lbl_dir = os.path.join(dataset_dir, "labels")
    img_list = os.listdir(img_dir) if os.path.exists(img_dir) else []
    print(f"[train_job_images] images={len(img_list)}  labels_dir_exists={os.path.exists(lbl_dir)}")

    if not img_list:
        TRAIN_JOBS[job_id]["status"] = "failed"
        TRAIN_JOBS[job_id]["error"] = (
            "No images were produced during annotation. "
            "Check that the uploaded images are valid (JPG/PNG/HEIC/etc.) and that "
            "the generic detection model (weld_defect_pipeline) is running."
        )
        return

    TRAIN_JOBS[job_id]["status"] = "augmenting"
    TRAIN_JOBS[job_id]["progress"] = 45
    augment_dataset(img_dir, lbl_dir, copies_per_image=5)

    TRAIN_JOBS[job_id]["status"] = "creating_dataset"
    TRAIN_JOBS[job_id]["progress"] = 50
    yaml_path = create_dataset_yaml(dataset_dir)

    TRAIN_JOBS[job_id]["status"] = "training"
    TRAIN_JOBS[job_id]["progress"] = 70
    best_model = train_yolo(yaml_path, job_id)

    # Immediately register the model in the database so it appears in Existing Models
    default_name = f"model_{job_id[:8]}"
    _register_model(default_name, best_model)

    TRAIN_JOBS[job_id]["status"] = "completed"
    TRAIN_JOBS[job_id]["progress"] = 100
    TRAIN_JOBS[job_id]["model_path"] = best_model
    TRAIN_JOBS[job_id]["model_name"] = default_name

@router.post("/train-model")
async def train_model(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
):
    job_id = str(uuid.uuid4())
    video_path = os.path.join(TRAIN_DIR, f"{job_id}.mp4")
    with open(video_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    TRAIN_JOBS[job_id] = {
        "status": "queued",
        "progress": 0,
        "model_path": None,
        "model_name": None,
    }

    background_tasks.add_task(train_job, job_id, video_path)
    return {"success": True, "job_id": job_id}

@router.post("/train-model-images")
async def train_model_images(
    background_tasks: BackgroundTasks,
    files: List[UploadFile] = File(...),
):
    job_id = str(uuid.uuid4())
    frame_dir = os.path.join("training_frames", job_id)
    os.makedirs(frame_dir, exist_ok=True)

    for i, file in enumerate(files):
        # Clean extension: strip spaces, lowercase, default to .jpg
        ext = os.path.splitext(file.filename)[1].strip().lower() if file.filename else ".jpg"
        if not ext:
            ext = ".jpg"

        # Save temporarily with original extension (e.g., .heic, .png)
        temp_path = os.path.join(frame_dir, f"frame_{i:06d}{ext}")
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # FIX: Convert HEIC/PNG/etc to JPG and fix EXIF orientation
        # This overwrites the file with a standard .jpg
        normalize_and_convert(temp_path, target_ext=".jpg")

    TRAIN_JOBS[job_id] = {
        "status": "queued",
        "progress": 0,
        "model_path": None,
        "model_name": None,
    }

    print(f"[train-model-images] Saved and converted {len(files)} files to {frame_dir}")
    print(f"[DEBUG] Files actually in dir: {os.listdir(frame_dir)}")

    background_tasks.add_task(train_job_images, job_id, frame_dir)
    return {"success": True, "job_id": job_id}

@router.get("/training-status/{job_id}")
def training_status(job_id: str):
    job = TRAIN_JOBS.get(job_id)
    if job is None:
        return {"error": "job not found"}
    return job

class RenameModelRequest(BaseModel):
    job_id: str
    model_name: str

@router.post("/rename-model")
def rename_model(req: RenameModelRequest):
    job = TRAIN_JOBS.get(req.job_id)
    default_name = f"model_{req.job_id[:8]}"
    old_name = job.get("model_name") if job else default_name
    model_path = job.get("model_path") if job else None

    # Check database first to see if it was auto-registered
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute(
        "SELECT id, model_name, model_path FROM trained_models WHERE model_name = ? OR model_path LIKE ?",
        (old_name, f"%{req.job_id}%")
    ).fetchone()

    if row:
        row_id, registered_name, registered_path = row
        # Rename in DB
        conn.execute("UPDATE trained_models SET model_name = ? WHERE id = ?", (req.model_name, row_id))
        conn.commit()
        conn.close()
        if job:
            job["model_name"] = req.model_name
        return {"success": True, "model_name": req.model_name, "model_path": registered_path}

    conn.close()

    # If not yet in DB, check if path exists on disk
    if not model_path:
        potential_path = os.path.join("custom_models", f"{req.job_id}.pt")
        if os.path.exists(potential_path):
            model_path = potential_path

    if not model_path or not os.path.exists(model_path):
        raise HTTPException(status_code=404, detail="Model weights not ready or file missing")

    _register_model(req.model_name, model_path)
    if job:
        job["model_name"] = req.model_name
    return {"success": True, "model_name": req.model_name, "model_path": model_path}

class RenameRequest(BaseModel):
    new_name: str

@router.delete("/models/{model_name}")
def delete_model(model_name: str):
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT model_path FROM trained_models WHERE model_name = ?", (model_name,)).fetchone()
    if row is None:
        conn.close()
        raise HTTPException(status_code=404, detail="Model not found")
    model_path = row[0]
    conn.execute("DELETE FROM trained_models WHERE model_name = ?", (model_name,))
    conn.commit()
    conn.close()

    if model_path and os.path.exists(model_path):
        try:
            os.remove(model_path)
        except OSError:
            pass

    return {"success": True, "deleted": model_name}

@router.patch("/models/{model_name}/rename")
def rename_model_inplace(model_name: str, req: RenameRequest):
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT model_path FROM trained_models WHERE model_name = ?", (model_name,)).fetchone()
    if row is None:
        conn.close()
        raise HTTPException(status_code=404, detail="Model not found")
    old_path = row[0]
    new_path = old_path

    if old_path and os.path.exists(old_path):
        dir_name = os.path.dirname(old_path)
        new_path = os.path.join(dir_name, f"{req.new_name}.pt")
        try:
            os.rename(old_path, new_path)
        except OSError:
            new_path = old_path

    conn.execute("UPDATE trained_models SET model_name = ?, model_path = ? WHERE model_name = ?", (req.new_name, new_path, model_name))
    conn.commit()
    conn.close()

    return {"success": True, "old_name": model_name, "new_name": req.new_name}