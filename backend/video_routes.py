"""
Video defect-detection routes.

Design notes (read before merging into app.py):

- The existing weld pipeline (run_detection -> run_pipeline) is a heavy,
  multi-step CV process meant for ONE image at a time. It is not safe to
  call it on every frame of a video, so this module samples the video at a
  fixed rate (default: 1 frame per second) instead of processing every frame.

- Each sampled frame is run through the *exact same* run_detection() used
  by /predict-image and /predict-frame, so detection logic stays in one
  place (detector.py / weld_defect_pipeline.py). Nothing about the
  pipeline itself is touched.

- run_pipeline writes "09_final_result.jpg" (or, for a clean frame, the
  same filename via the ACCEPT-with-no-defects branch) into cfg["output_dir"].
  That annotated frame -- not the raw frame -- is what gets stitched back
  into the output video with cv2.VideoWriter. This re-uses the pipeline's
  own bbox-drawing code instead of duplicating it here.

- Because a single frame can take seconds to process, this endpoint is
  async: POST /predict-video immediately returns a job_id and kicks off
  processing in a FastAPI BackgroundTask. The client polls
  GET /video-status/{job_id} until status is "done" or "failed", then
  downloads the result from GET /video-result/{job_id}.

- Jobs are tracked in a simple in-memory dict for now (VIDEO_JOBS). If you
  need this to survive a server restart, move it into the same SQLite file
  app.py already uses (a "video_jobs" table) -- the get_db() helper in
  app.py can be reused as-is.
"""

import os
import uuid
import shutil
import threading
import traceback
from datetime import datetime, timezone

import cv2
from fastapi import APIRouter, BackgroundTasks, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse

from detector import get_model, run_detection

router = APIRouter()

VIDEO_UPLOAD_DIR = "uploads_video"
VIDEO_RESULT_DIR = "results_video"
FRAME_SAMPLE_RATE_SEC = 1.0  # process ~1 frame per second of video

os.makedirs(VIDEO_UPLOAD_DIR, exist_ok=True)
os.makedirs(VIDEO_RESULT_DIR, exist_ok=True)

# job_id -> {status, progress, total_frames, defect_count, decision,
#            error, result_path, created_at}
# In-memory only -- fine for a single-process dev/staging server.
VIDEO_JOBS: dict[str, dict] = {}


def _job_dir(job_id: str) -> str:
    d = os.path.join(VIDEO_RESULT_DIR, job_id)
    os.makedirs(d, exist_ok=True)
    return d


def _frames_dir(job_id: str) -> str:
    d = os.path.join(_job_dir(job_id), "frames")
    os.makedirs(d, exist_ok=True)
    return d


def process_video_job(job_id: str, input_path: str, model_name: str | None):
    """Runs in a BackgroundTask. Samples frames, runs run_detection on
    each sampled frame, then pipes raw BGR frames into ffmpeg which encodes
    as H.264 baseline + faststart -- the only format ExoPlayer reliably
    streams over plain HTTP on Android."""

    import subprocess

    job = VIDEO_JOBS[job_id]

    try:
        cap = cv2.VideoCapture(input_path)
        if not cap.isOpened():
            raise RuntimeError("Could not open uploaded video")

        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        # H.264 baseline requires even dimensions
        enc_width  = width  if width  % 2 == 0 else width  - 1
        enc_height = height if height % 2 == 0 else height - 1

        job["total_frames"] = total_frames
        job["fps"] = fps
        job["status"] = "processing"

        sample_every_n = max(1, round(fps * FRAME_SAMPLE_RATE_SEC))

        out_path = os.path.join(_job_dir(job_id), "annotated.mp4")
        frames_dir = _frames_dir(job_id)

        # Pipe raw BGR24 frames into ffmpeg -> H.264 baseline + faststart.
        ffmpeg_cmd = [
            "ffmpeg", "-y",
            "-f", "rawvideo",
            "-vcodec", "rawvideo",
            "-pix_fmt", "bgr24",
            "-s", f"{enc_width}x{enc_height}",
            "-r", str(fps),
            "-i", "pipe:0",
            "-vcodec", "libx264",
            "-profile:v", "baseline",
            "-level", "3.1",
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            "-preset", "fast",
            out_path,
        ]
        print(f"[ffmpeg] starting encoder  {enc_width}x{enc_height} @ {fps}fps")
        ffmpeg_proc = subprocess.Popen(
            ffmpeg_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )

        # ffmpeg logs per-frame stats to stderr by default. If nothing
        # reads that pipe while we're still writing raw frames to stdin
        # below, the OS pipe buffer (~64KB) fills up, ffmpeg blocks
        # trying to flush its own logs, stops consuming stdin, and our
        # stdin.write() calls below block forever -- a silent hang with
        # no exception raised (this is what was happening: the job sits
        # at "processing" forever). Draining stderr continuously in a
        # background thread for the life of the process avoids this.
        # communicate() later is NOT sufficient on its own -- it only
        # starts draining stderr after all frames are already written.
        stderr_chunks: list[bytes] = []

        def _drain_stderr():
            for chunk in iter(lambda: ffmpeg_proc.stderr.read(4096), b""):
                stderr_chunks.append(chunk)

        stderr_thread = threading.Thread(target=_drain_stderr, daemon=True)
        stderr_thread.start()

        all_defects = []
        overall_decision = "ACCEPT"
        last_annotated_frame = None
        frame_idx = 0

        while True:
            ok, frame = cap.read()
            if not ok:
                break

            is_sample_point = (frame_idx % sample_every_n == 0)

            if is_sample_point:
                raw_path = os.path.join(frames_dir, f"frame_{frame_idx:06d}.jpg")
                cv2.imwrite(raw_path, frame)

                frame_out_dir = os.path.join(frames_dir, f"out_{frame_idx:06d}")
                os.makedirs(frame_out_dir, exist_ok=True)

                if model_name:
                    # ── Specific model ────────────────────────────────────
                    model = get_model(model_name)

                    yolo_results = model.predict(
                        source=raw_path,
                        conf=0.25,
                        imgsz=640,
                        verbose=False,
                    )

                    r = yolo_results[0]
                    frame_defects = []

                    for box in r.boxes:
                        cls_id = int(box.cls[0])
                        conf = float(box.conf[0])
                        cls_name = model.names[cls_id]

                        if cls_name == "Normal Weld-NW":
                            continue

                        x1, y1, x2, y2 = map(float, box.xyxy[0])

                        frame_defects.append({
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

                    frame_decision = "REJECT" if frame_defects else "ACCEPT"

                    annotated_path_img = os.path.join(frame_out_dir, "annotated.jpg")
                    cv2.imwrite(annotated_path_img, r.plot())

                    result = {
                        "decision": frame_decision,
                        "defects": frame_defects,
                        "result_image": annotated_path_img,
                    }
                else:
                    # ── Generic model ─────────────────────────────────────
                    result = run_detection(raw_path, frame_out_dir)
                    frame_defects = result.get("defects", [])

                timestamp_sec = round(frame_idx / fps, 2)
                for d in frame_defects:
                    d_with_time = dict(d)
                    d_with_time["frame_index"] = frame_idx
                    d_with_time["timestamp_sec"] = timestamp_sec
                    all_defects.append(d_with_time)

                if result["decision"] == "REJECT":
                    overall_decision = "REJECT"
                elif result["decision"] == "REVIEW" and overall_decision != "REJECT":
                    overall_decision = "REVIEW"

                annotated_path = result.get("result_image")
                if annotated_path and os.path.exists(annotated_path):
                    last_annotated_frame = cv2.imread(annotated_path)
                else:
                    last_annotated_frame = frame

                shutil.rmtree(frame_out_dir, ignore_errors=True)
                os.remove(raw_path)

            frame_to_write = last_annotated_frame if last_annotated_frame is not None else frame
            if frame_to_write.shape[1] != enc_width or frame_to_write.shape[0] != enc_height:
                frame_to_write = cv2.resize(frame_to_write, (enc_width, enc_height))

            ffmpeg_proc.stdin.write(frame_to_write.tobytes())

            frame_idx += 1
            if total_frames:
                job["progress"] = round(min(frame_idx / total_frames, 1.0) * 100, 1)

        cap.release()

        # Close stdin so ffmpeg knows input is done, then wait for it to
        # finish and join the stderr-draining thread (which has been
        # running the whole time, so there's nothing left to deadlock on).
        ffmpeg_proc.stdin.close()
        ffmpeg_proc.wait()
        stderr_thread.join(timeout=5)
        stderr_out = b"".join(stderr_chunks).decode(errors="replace")
        print(f"[ffmpeg] returncode={ffmpeg_proc.returncode}")
        if ffmpeg_proc.returncode != 0:
            print(f"[ffmpeg] FAILED stderr:\n{stderr_out}")
            raise RuntimeError(f"ffmpeg encoding failed (rc={ffmpeg_proc.returncode}):\n{stderr_out}")
        print(f"[ffmpeg] success -> {out_path}")

        job["status"] = "done"
        job["progress"] = 100.0
        job["decision"] = overall_decision
        job["defects"] = all_defects
        job["defect_count"] = len(all_defects)
        job["result_path"] = out_path

    except Exception as e:
        job["status"] = "failed"
        job["error"] = str(e)
        job["traceback"] = traceback.format_exc()
    finally:
        # remove the uploaded source video once processing is finished
        try:
            os.remove(input_path)
        except OSError:
            pass


@router.post("/predict-video")
async def predict_video(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    model_name: str = Form(None),
):
    job_id = str(uuid.uuid4())

    ext = os.path.splitext(file.filename or "")[1] or ".mp4"
    input_path = os.path.join(VIDEO_UPLOAD_DIR, f"{job_id}{ext}")

    with open(input_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    VIDEO_JOBS[job_id] = {
        "status": "queued",
        "progress": 0.0,
        "total_frames": None,
        "fps": None,
        "decision": None,
        "defects": [],
        "defect_count": 0,
        "result_path": None,
        "error": None,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    background_tasks.add_task(process_video_job, job_id, input_path, model_name)

    return {"success": True, "job_id": job_id}


@router.get("/video-status/{job_id}")
def video_status(job_id: str):
    job = VIDEO_JOBS.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")

    return {
        "job_id": job_id,
        "status": job["status"],            # queued | processing | done | failed
        "progress": job["progress"],         # 0-100
        "decision": job["decision"],         # ACCEPT | REVIEW | REJECT | None
        "defect_count": job["defect_count"],
        "defects": job["defects"],
        "error": job["error"],
        "video_url": (
            f"/video-result/{job_id}" if job["status"] == "done" else None
        ),
    }


@router.get("/video-result/{job_id}")
def video_result(job_id: str):
    job = VIDEO_JOBS.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    if job["status"] != "done" or not job["result_path"]:
        raise HTTPException(status_code=409, detail=f"job is {job['status']}, not ready")

    return FileResponse(job["result_path"], media_type="video/mp4")

