import os
import cv2
import shutil
from detector import run_detection

# FIX: Import the new function name
from image_orientation import normalize_and_convert

CLASS_MAP = {
    "Porosity": 0,
    "Spatter": 1,
}

# Cleaned set. Added .heic/.heif for iOS. No trailing spaces.
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tiff", ".tif", ".heic", ".heif"}

def create_yolo_label(image_path, defects, label_path):
    img = cv2.imread(image_path)
    if img is None:
        # Skip label creation for corrupt images
        return
    h, w = img.shape[:2]

    with open(label_path, "w") as f:
        for defect in defects:
            defect_type = defect["type"]
            if defect_type not in CLASS_MAP:
                continue

            class_id = CLASS_MAP[defect_type]
            x, y, bw, bh = defect["bbox"]

            # Convert to YOLO format (center_x, center_y, width, height normalized)
            xc = (x + bw / 2) / w
            yc = (y + bh / 2) / h
            bw = bw / w
            bh = bh / h

            f.write(f"{class_id} {xc:.6f} {yc:.6f} {bw:.6f} {bh:.6f}\n")

def auto_annotate_frames(frame_dir, dataset_dir, train_jobs=None, job_id=None):
    images_dir = os.path.join(dataset_dir, "images")
    labels_dir = os.path.join(dataset_dir, "labels")
    os.makedirs(images_dir, exist_ok=True)
    os.makedirs(labels_dir, exist_ok=True)

    # Filter valid images
    frames = sorted([
        f for f in os.listdir(frame_dir)
        if os.path.splitext(f)[1].lower() in IMAGE_EXTS
    ])

    total = len(frames)
    print(f"[auto_annotate] Found {total} valid images in {frame_dir}")

    for idx, frame_name in enumerate(frames):
        frame_path = os.path.join(frame_dir, frame_name)

        # FIX: Use normalize_and_convert. 
        # It handles HEIC conversion and EXIF rotation, returning the new .jpg path.
        frame_path = normalize_and_convert(frame_path, target_ext=".jpg")

        output_dir = os.path.join(dataset_dir, "temp")
        os.makedirs(output_dir, exist_ok=True)

        result = run_detection(frame_path, output_dir)
        print(f"[auto_annotate] Frame {idx+1}/{total}: {len(result.get('defects', []))} defects found")

        base_name = os.path.splitext(frame_name)[0]
        jpg_name = base_name + ".jpg"

        image_dst = os.path.join(images_dir, jpg_name)
        label_dst = os.path.join(labels_dir, base_name + ".txt")

        # Read source as BGR, write as proper JPEG
        src_img = cv2.imread(frame_path)
        if src_img is not None:
            cv2.imwrite(image_dst, src_img)
        else:
            shutil.copy(frame_path, image_dst)

        # Always write a label file — empty = background sample (valid for YOLO)
        create_yolo_label(image_dst, result.get("defects", []), label_dst)

        # Clean up temp dir
        if os.path.exists(output_dir):
            shutil.rmtree(output_dir, ignore_errors=True)

        if train_jobs is not None and job_id is not None:
            progress = 10 + ((idx + 1) / total * 30)
            train_jobs[job_id]["progress"] = round(progress)

    print("[auto_annotate] Annotation complete.")