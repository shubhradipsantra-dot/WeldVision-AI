from fastapi import FastAPI, UploadFile, File, Form, Request, HTTPException
from fastapi.responses import FileResponse
from detector import get_model, run_detection
from image_orientation import normalize_and_convert
import shutil
import uuid
import os
import sqlite3
import time
import cv2
import hashlib
import secrets
from datetime import datetime, timezone

app = FastAPI()

# Allow CORS for any origin (frontend may run on different host/port)
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


from video_routes import router as video_router
app.include_router(video_router)

from training_routes import router as training_router
app.include_router(training_router)

UPLOAD_DIR = "uploads"
RESULT_DIR = "results"
DB_PATH = "inspections.db"

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(RESULT_DIR, exist_ok=True)

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS inspections (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            decision TEXT NOT NULL,
            defect_count INTEGER NOT NULL,
            source TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS trained_models (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_name TEXT UNIQUE,
            model_path TEXT,
            created_at TEXT
        )
        """
    )
    # Add created_at column to trained_models if upgrading from old schema
    try:
        conn.execute("ALTER TABLE trained_models ADD COLUMN created_at TEXT")
    except Exception:
        pass  # Column already exists

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS sessions (
            token TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )
    conn.commit()
    conn.close()

def sync_custom_models():
    """Discover any .pt model weights in custom_models/ that aren't yet
    in the trained_models database table, and auto-register them."""
    custom_dir = "custom_models"
    if not os.path.exists(custom_dir):
        return
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT model_name, model_path FROM trained_models").fetchall()
    existing_paths = {os.path.normpath(r[1]) for r in rows if r[1]}
    existing_names = {r[0] for r in rows if r[0]}
    now = datetime.now(timezone.utc).isoformat()

    for fname in os.listdir(custom_dir):
        if not fname.endswith(".pt"):
            continue
        full_path = os.path.join(custom_dir, fname)
        norm_full = os.path.normpath(full_path)
        if norm_full in existing_paths or fname in existing_names:
            continue

        base_name = os.path.splitext(fname)[0]
        if base_name in existing_names:
            continue

        if len(base_name) == 36 and '-' in base_name:
            m_name = f"model_{base_name[:8]}"
        else:
            m_name = base_name

        unique_name = m_name
        counter = 1
        while unique_name in existing_names:
            unique_name = f"{m_name}_{counter}"
            counter += 1

        conn.execute(
            "INSERT INTO trained_models (model_name, model_path, created_at) VALUES (?, ?, ?)",
            (unique_name, full_path, now),
        )
        existing_names.add(unique_name)
        existing_paths.add(norm_full)
        print(f"[sync_custom_models] Registered: {unique_name} -> {full_path}")

    conn.commit()
    conn.close()

init_db()
sync_custom_models()

# ─── AUTH HELPERS ──────────────────────────────────────────────────────────

def _hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def _generate_token() -> str:
    return secrets.token_hex(32)

def _get_user_by_email(email: str):
    if not email:
        return None
    email_clean = email.strip().lower()
    conn = get_db()
    row = conn.execute("SELECT * FROM users WHERE LOWER(email) = LOWER(?)", (email_clean,)).fetchone()
    conn.close()
    return dict(row) if row else None

def _get_user_by_token(token: str):
    if not token:
        return None
    conn = get_db()
    row = conn.execute(
        "SELECT u.* FROM users u JOIN sessions s ON u.id = s.user_id WHERE s.token = ?",
        (token,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None

def _optional_auth(request: Request):
    """Returns user dict if a valid Bearer token is present, else None.
    Backend endpoints work without auth (for local-only deployment) but
    will honour a valid token if one is provided."""
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
        return _get_user_by_token(token)
    return None

# ─── AUTH ROUTES ──────────────────────────────────────────────────────────

from pydantic import BaseModel as PydanticBaseModel

class AuthRequest(PydanticBaseModel):
    email: str
    password: str

class ForgotPasswordRequest(PydanticBaseModel):
    email: str

class VerifyOtpRequest(PydanticBaseModel):
    email: str
    otp: str

class ResetPasswordRequest(PydanticBaseModel):
    email: str
    otp: str
    new_password: str

class ResendVerificationRequest(PydanticBaseModel):
    email: str

@app.post("/auth/register")
def auth_register(req: AuthRequest):
    email = req.email.strip().lower()
    existing = _get_user_by_email(email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    user_id = str(uuid.uuid4())
    password_hash = _hash_password(req.password)
    now = datetime.now(timezone.utc).isoformat()
    conn = get_db()
    conn.execute(
        "INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)",
        (user_id, email, password_hash, now)
    )
    token = _generate_token()
    conn.execute(
        "INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)",
        (token, user_id, now)
    )
    conn.commit()
    conn.close()
    return {"access_token": token, "user_id": user_id, "email": email}

@app.post("/auth/login")
def auth_login(req: AuthRequest):
    email = req.email.strip().lower()
    user = _get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=401, detail="No account found with this email.")
    if user["password_hash"] != _hash_password(req.password):
        raise HTTPException(status_code=401, detail="Incorrect password. Please try again.")
    token = _generate_token()
    conn = get_db()
    conn.execute(
        "INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)",
        (token, user["id"], datetime.now(timezone.utc).isoformat())
    )
    conn.commit()
    conn.close()
    return {"access_token": token, "user_id": user["id"], "email": user["email"]}

@app.post("/auth/forgot-password")
def auth_forgot_password(req: ForgotPasswordRequest):
    email = req.email.strip().lower()
    user = _get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=404, detail="No account found with this email.")
    return {"message": "Reset code is 000000 (Development OTP)."}

@app.post("/auth/verify-reset-otp")
def auth_verify_otp(req: VerifyOtpRequest):
    # Stub: accept "000000" as the dev OTP
    if req.otp.strip() != "000000":
        raise HTTPException(status_code=400, detail="Invalid code. Use 000000 for dev.")
    return {"message": "Code verified."}

@app.post("/auth/reset-password")
def auth_reset_password(req: ResetPasswordRequest):
    if req.otp.strip() != "000000":
        raise HTTPException(status_code=400, detail="Invalid code. Use 000000 for dev.")
    email = req.email.strip().lower()
    user = _get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    new_hash = _hash_password(req.new_password)
    conn = get_db()
    conn.execute("UPDATE users SET password_hash = ? WHERE LOWER(email) = LOWER(?)", (new_hash, email))
    conn.commit()
    conn.close()
    return {"message": "Password updated successfully."}

@app.post("/auth/resend-verification")
def auth_resend_verification(req: ResendVerificationRequest):
    return {"message": "Verification email resent (dev mode — no email actually sent)."}

# ─────────────────────────────────────────────────────────────────────────

def log_inspection(uid: str, decision: str, defect_count: int, source: str):
    """Persist one inspection outcome. Failures are logged but never block
    the API response."""
    try:
        conn = get_db()
        conn.execute(
            "INSERT INTO inspections (id, created_at, decision, defect_count, source) "
            "VALUES (?, ?, ?, ?, ?)",
            (uid, datetime.now(timezone.utc).isoformat(), decision, defect_count, source),
        )
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"  [warn] failed to log inspection {uid}: {e}")

def _parse_results(results):
    """Convert ultralytics Results into the defect list + decision the app
    expects. Returns (decision, defects) where decision is ACCEPT or REJECT."""
    defects = []
    for r in results:
        boxes = r.boxes
        if boxes is None:
            continue
        for i in range(len(boxes)):
            cls_id = int(boxes.cls[i].item())
            conf = float(boxes.conf[i].item())
            x1, y1, x2, y2 = boxes.xyxy[i].tolist()
            label = r.names.get(cls_id, str(cls_id))
            defects.append({
                "type": label,
                "confidence": round(conf, 4),
                "bbox": [round(x1), round(y1), round(x2 - x1), round(y2 - y1)],
                "severity": "MAJOR" if conf >= 0.6 else "MINOR",
                "area_mm2": round((x2 - x1) * (y2 - y1) / 100, 2),
            })
    decision = "REJECT" if defects else "ACCEPT"
    return decision, defects

@app.post("/predict-image")
async def predict_image(
    request: Request,
    file: UploadFile = File(...),
    model_name: str = Form(None),
):
    uid = str(uuid.uuid4())
    
    # Build base URL dynamically from the incoming request so the Flutter
    # client can load the result image regardless of the server's IP.
    base_url = str(request.base_url).rstrip("/")
    ext = os.path.splitext(file.filename or "")[1].strip().lower() or ".jpg"
    temp_path = os.path.join(UPLOAD_DIR, f"{uid}_temp{ext}")
    result_dir = os.path.join(RESULT_DIR, uid)
    os.makedirs(result_dir, exist_ok=True)

    with open(temp_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # Convert HEIC/PNG/etc to JPG and fix EXIF orientation
    input_path = normalize_and_convert(temp_path, target_ext=".jpg")

    if model_name:
        # ── Specific model: YOLO trained via app ─────────────────────────
        print(f"Using model: {model_name}")
        model = get_model(model_name)

        results = model.predict(
            source=input_path,
            conf=0.15,
            imgsz=640,
            verbose=False,
        )

        result = results[0]
        defects = []

        for box in result.boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            cls_name = model.names[cls_id]

            if cls_name == "Normal Weld-NW":
                continue

            x1, y1, x2, y2 = map(float, box.xyxy[0])

            defects.append({
                "type": cls_name,
                "confidence": round(conf, 3),
                "bbox": [
                    round(x1),
                    round(y1),
                    round(x2 - x1),
                    round(y2 - y1),
                ],
                "severity": "MAJOR" if conf > 0.7 else "MINOR",
                "area_mm2": round((x2 - x1) * (y2 - y1) / 100, 2),
            })

        decision = "REJECT" if defects else "ACCEPT"

        annotated_path = os.path.join(result_dir, "09_final_result.jpg")
        cv2.imwrite(annotated_path, result.plot())

        error = None
    else:
        # ── Generic model: weld_defect_pipeline ──────────────────────────
        print("USING GENERIC PIPELINE")
        result = run_detection(input_path, result_dir)
        decision = result["decision"]
        defects = result["defects"]
        error = result.get("error")

    log_inspection(uid, decision, len(defects), source="image")

    return {
        "success": True,
        "decision": {
            "decision": decision,
            "defects": defects,
            "error": error,
        },
        "image_url": f"{base_url}/result/{uid}",
    }

@app.get("/result/{uid}")
def get_result(uid: str):
    image_path = os.path.join(RESULT_DIR, uid, "09_final_result.jpg")
    return FileResponse(image_path)

@app.post("/predict-frame")
async def predict_frame(
    file: UploadFile = File(...),
    model_name: str = Form(None),
):
    uid = str(uuid.uuid4())

    # Extract and clean extension, default to .jpg
    ext = os.path.splitext(file.filename or "")[1].strip().lower() or ".jpg"
    temp_path = os.path.join(UPLOAD_DIR, f"{uid}_temp{ext}")

    with open(temp_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # Convert HEIC/PNG/etc to JPG and fix EXIF orientation
    frame_path = normalize_and_convert(temp_path, target_ext=".jpg")

    # Read image dimensions first so we can normalise bounding boxes
    img = cv2.imread(frame_path)
    h, w = img.shape[:2] if img is not None else (0, 0)

    if model_name:
        # ── Specific model ────────────────────────────────────────────────
        print(f"Using model: {model_name}")
        model = get_model(model_name)

        t0 = time.time()
        results = model.predict(
            source=frame_path,
            conf=0.15,
            imgsz=640,
            verbose=False,
        )
        print(f"YOLO inference: {(time.time()-t0)*1000:.0f} ms")

        result = results[0]
        defects = []

        for box in result.boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            cls_name = model.names[cls_id]

            if cls_name == "Normal Weld-NW":
                continue

            x1, y1, x2, y2 = map(float, box.xyxy[0])
            bw, bh = x2 - x1, y2 - y1

            defects.append({
                "type": cls_name,
                "class": cls_name,          # Flutter reads d['class'] ?? d['type']
                "confidence": round(conf, 3),
                # Normalized (0.0–1.0) for Flutter live overlay CustomPaint
                "x": round(x1 / w, 4) if w else 0.0,
                "y": round(y1 / h, 4) if h else 0.0,
                "width": round(bw / w, 4) if w else 0.0,
                "height": round(bh / h, 4) if h else 0.0,
                "bbox": [round(x1), round(y1), round(bw), round(bh)],
                "severity": "MAJOR" if conf > 0.7 else "MINOR",
                "area_mm2": round(bw * bh / 100, 2),
            })

        decision = "REJECT" if defects else "ACCEPT"
        error = None
    else:
        # ── Generic model ─────────────────────────────────────────────────
        print("USING GENERIC PIPELINE")
        result = run_detection(frame_path, RESULT_DIR)
        decision = result["decision"]
        raw_defects = result["defects"]
        error = result.get("error")

        # Normalise generic-pipeline defects too so Flutter overlay works
        defects = []
        for d in raw_defects:
            bbox = d.get("bbox", [0, 0, 0, 0])
            x1, y1, bw, bh = (float(v) for v in bbox[:4])
            defects.append({
                **d,
                "class": d.get("type", "Unknown"),
                "x": round(x1 / w, 4) if w else 0.0,
                "y": round(y1 / h, 4) if h else 0.0,
                "width": round(bw / w, 4) if w else 0.0,
                "height": round(bh / h, 4) if h else 0.0,
            })

    log_inspection(uid, decision, len(defects), source="frame")

    return {
        "decision": decision,
        "defects": defects,
        "image_width": w,
        "image_height": h,
        "error": error,
    }

@app.get("/stats")
def get_stats():
    """Aggregate stats for the home screen 'Today at a Glance' row."""
    conn = get_db()
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    today_rows = conn.execute(
        "SELECT decision, defect_count FROM inspections WHERE created_at LIKE ?",
        (f"{today_str}%",),
    ).fetchall()

    conn.close()

    inspections_today = len(today_rows)

    if inspections_today == 0:
        return {
            "inspections_today": 0,
            "pass_rate": 0.0,
            "avg_defects": 0.0,
            "active_scans": 0,
        }

    accepted = sum(1 for r in today_rows if r["decision"] == "ACCEPT")
    pass_rate = round((accepted / inspections_today) * 100, 1)
    avg_defects = round(
        sum(r["defect_count"] for r in today_rows) / inspections_today, 2
    )

    return {
        "inspections_today": inspections_today,
        "pass_rate": pass_rate,
        "avg_defects": avg_defects,
        "active_scans": 0,  # local backend has no live "active scan" queue
    }

@app.get("/inspections/recent")
def get_recent_inspections(limit: int = 20):
    """Return the most recent inspection records for the history feed."""
    conn = get_db()
    rows = conn.execute(
        "SELECT id, created_at, decision, defect_count, source "
        "FROM inspections ORDER BY created_at DESC LIMIT ?",
        (min(limit, 100),),
    ).fetchall()
    conn.close()
    return {
        "inspections": [
            {
                "id": r["id"],
                "created_at": r["created_at"],
                "decision": r["decision"],
                "defect_count": r["defect_count"],
                "source": r["source"],
            }
            for r in rows
        ]
    }

@app.get("/models")
def get_models():
    """Return all trained models.  The Flutter ExistingModelsScreen expects
    either a plain list OR a dict with a 'models' key — both are handled
    on the client side.  We return a dict for future-proofing."""
    sync_custom_models()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT id, model_name, model_path, created_at FROM trained_models ORDER BY id DESC")
    models = [
        {
            "id": row["id"],
            "model_name": row["model_name"],
            "name": row["model_name"],          # alias used by older Flutter code
            "model_path": row["model_path"],
            "created_at": row["created_at"],
            "status": "ready",
        }
        for row in cur.fetchall()
    ]
    conn.close()
    return {"models": models}