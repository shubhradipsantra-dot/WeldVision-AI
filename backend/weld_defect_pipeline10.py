import cv2
import numpy as np
import os
import argparse
import csv
import time
from sklearn.mixture import GaussianMixture
from sklearn.preprocessing import StandardScaler
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from PIL import Image

# ── YOLO11s-cls imports (replaces EfficientNet/torchvision) ─────
import torch
from ultralytics import YOLO

BASE_DIR = os.path.dirname(
    os.path.abspath(__file__)
)

# ─────────────────────────────────────────────
# CONFIG  — tweak these for your setup
# ─────────────────────────────────────────────
CFG = {
    "blur_threshold":      80,      # Laplacian variance; below = too blurry
    "min_brightness":      20,      # discard if mean gray below this
    "max_brightness":      235,     # discard if mean gray above this
    "sigmas_f": [1.0, 2.0, 3.0],
    "sigmas_b": [12.0, 20.0, 30.0],
    "ka":          2.0,             # area-threshold empirical coefficient
    "merge_votes": 0.35,            # fraction of maps a region must appear in
    "min_defect_px": 15,            # minimum defect area in pixels
    "px_per_mm":   10.0,            # calibration: pixels per mm (measure yours)
    "n_classes":   1,               # crack, porosity
    "classifier_model": r"models\best (11).pt",   # YOLO11s-cls checkpoint
    "output_dir":  "output",

    # ── Shape-feature filtering (candidate validation stage before YOLO) ──
    "shape_filter_min_votes": 4,    # min rule-votes (out of 7) — kept for reference/debug only, no longer gates YOLO
    "yolo_high_conf":         0.90, # above this, trust YOLO alone (no shape veto)
    "yolo_conf_thresh":       0.50, # min YOLO confidence to even consider a candidate
    "final_score_thresh":     0.50, # min combined final_score to accept a defect (low/mid-confidence path)
    "w_yolo":                 0.65, # deprecated — final_score now uses fixed weights below
    "w_shape":                0.35, # deprecated

    # ── Early texture rejection (contour-level, before extract_features/classify) ──
    "texture_reject_min_votes":        3,    # votes (out of 5) needed to reject a contour as weld texture
    "texture_reject_ring_px":          11,   # dilation kernel size (px) used to build the surrounding "ring"
    "texture_reject_circularity_thresh": 0.45,
    "texture_reject_solidity_thresh":    0.80,
    "texture_reject_mean_diff_thresh":   6,   # inside-vs-ring mean intensity diff below this -> texture vote
    "texture_reject_std_diff_thresh":    4,   # inside-vs-ring std diff below this -> texture vote
}

DEFECT_NAMES = {
    -1: "Background",
     0: "Porosity"
}

DEFECT_COLORS = {
    0: (0,180,0)
}

# ── Classifier globals (replaces EN_MODEL / EN_CLASSES / EN_TRANSFORM) ──
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
YOLO_MODEL   = None   # YOLO11s-cls model (ultralytics.YOLO)
YOLO_CLASSES = None   # dict {idx: class_name}, taken from model.names


# ─────────────────────────────────────────────
# STEP 0 — helpers
# ─────────────────────────────────────────────
def save(name, img, out_dir):
    path = os.path.join(out_dir, name)
    cv2.imwrite(path, img)
    print(f"  saved → {path}")
    return path

def ensure_dir(d):
    os.makedirs(d, exist_ok=True)

def to_bgr(gray):
    return cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)


# ─────────────────────────────────────────────
# MODEL LOADING  (now loads YOLO11s-cls instead of EfficientNet)
# ─────────────────────────────────────────────
def load_classifier(model_path):
    model = YOLO(model_path)
    model.to(DEVICE)
    classes = model.names
    return model, classes


# ─────────────────────────────────────────────
# STEP 1 — Quality gate
# ────────────────────────────────────────────
def quality_gate(frame, cfg):
    print("\n[STEP 1] Quality gate")
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    blur_score = cv2.Laplacian(gray, cv2.CV_64F).var()
    mean_bright = float(gray.mean())

    print(f"  Blur score  : {blur_score:.1f}  (need ≥ {cfg['blur_threshold']})")
    print(f"  Mean bright : {mean_bright:.1f}  (need {cfg['min_brightness']}–{cfg['max_brightness']})")

    ok = True
    reason = []
    if blur_score < cfg["blur_threshold"]:
        ok = False
        reason.append("too blurry")
    if mean_bright < cfg["min_brightness"]:
        ok = False
        reason.append("underexposed")
    if mean_bright > cfg["max_brightness"]:
        ok = False
        reason.append("overexposed")

    vis = frame.copy()
    status = "PASS" if ok else f"FAIL: {', '.join(reason)}"
    color = (0, 200, 0) if ok else (0, 0, 220)
    cv2.putText(vis, f"Quality: {status}", (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)
    cv2.putText(vis, f"Blur={blur_score:.0f}  Bright={mean_bright:.0f}",
                (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 1)

    print(f"  Result      : {status}")
    return ok, gray, vis


# ─────────────────────────────────────────────
# STEP 2 — Histogram stretching (dynamic stretch)
# ────────────────────────────────────────────
def histogram_stretch(gray, cfg, out_dir):
    print("\n[STEP 2] Histogram stretching")
    stretched = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    
    combined = np.hstack([gray, stretched])
    vis = to_bgr(combined)
    h, w = gray.shape
    cv2.putText(vis, "Original", (10, 20),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200,200,200), 1)
    cv2.putText(vis, "Stretched", (w + 10, 20),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200,200,200), 1)
    save("02_histogram_stretch.jpg", vis, out_dir)
    print(f"  Input  range: [{gray.min()}, {gray.max()}]")
    print(f"  Output range: [{stretched.min()}, {stretched.max()}]")
    return stretched


# ─────────────────────────────────────────────
# STEP 3 — Multi-scale DoG difference images
# ─────────────────────────────────────────────
def multiscale_dog(gray, cfg, out_dir):
    print("\n[STEP 3] Multi-scale Difference-of-Gaussians")
    diff_images = []

    grid_rows = len(cfg["sigmas_f"])
    grid_cols = len(cfg["sigmas_b"])
    cell_h, cell_w = gray.shape
    grid = np.zeros((cell_h * grid_rows, cell_w * grid_cols), dtype=np.uint8)

    for ri, sf in enumerate(cfg["sigmas_f"]):
        fg = cv2.GaussianBlur(gray, (0, 0), sf)
        for ci, sb in enumerate(cfg["sigmas_b"]):
            bg = cv2.GaussianBlur(gray, (0, 0), sb)
            diff = cv2.subtract(bg, fg)
            diff_norm = cv2.normalize(diff, None, 0, 255,
                                      cv2.NORM_MINMAX).astype(np.uint8)
            diff_images.append((sf, sb, diff_norm))

            y0, x0 = ri * cell_h, ci * cell_w
            grid[y0:y0+cell_h, x0:x0+cell_w] = diff_norm

            label = f"sf={sf} sb={sb}"
            print(f"  DoG({label:16s})  max={diff_norm.max():3d}")

    max_side = 1200
    gh, gw = grid.shape
    if max(gh, gw) > max_side:
        scale = max_side / max(gh, gw)
        grid = cv2.resize(grid, (int(gw*scale), int(gh*scale)))

    save("03_dog_grid.jpg", to_bgr(grid), out_dir)
    return diff_images


# ─────────────────────────────────────────────
# STEP 4 — Multi-intensity binarization
# ─────────────────────────────────────────────
def multi_intensity_binarize(diff_images, cfg, out_dir):
    print("\n[STEP 4] Multi-intensity binarization")
    binary_maps = []
    total = 0

    for sf, sb, diff in diff_images:
        t1 = float(diff.mean())
        if t1 < 1.0:
            t1 = 1.0
        n = 1
        while True:
            t = (2 ** (n - 1)) * t1
            if t > diff.max() or n > 8:
                break
            _, bmap = cv2.threshold(diff, t, 255, cv2.THRESH_BINARY)
            binary_maps.append((sf, sb, t, bmap))
            total += 1
            n += 1

    print(f"  Generated {total} binary maps")

    n_show = min(9, len(binary_maps))
    cols = 3
    rows = (n_show + cols - 1) // cols
    h, w = binary_maps[0][3].shape
    grid = np.zeros((rows * h, cols * w), dtype=np.uint8)
    for idx in range(n_show):
        r, c = divmod(idx, cols)
        sf, sb, t, bmap = binary_maps[idx]
        grid[r*h:(r+1)*h, c*w:(c+1)*w] = bmap
    max_side = 1200
    gh, gw = grid.shape
    if max(gh, gw) > max_side:
        sc = max_side / max(gh, gw)
        grid = cv2.resize(grid, (int(gw*sc), int(gh*sc)),
                          interpolation=cv2.INTER_NEAREST)
    save("04_binary_maps_sample.jpg", to_bgr(grid), out_dir)
    return binary_maps


# ─────────────────────────────────────────────
# STEP 5 — Screen (area filter) + merge (vote heatmap)
# ─────────────────────────────────────────────
def screen_and_merge(binary_maps, gray, cfg, out_dir):
    print("\n[STEP 5] Screen + merge candidates")
    h, w = gray.shape
    heat = np.zeros((h, w), dtype=np.float32)

    kept_total = 0
    for sf, sb, t, bmap in binary_maps:
        area_thresh = cfg["ka"] * (sf / (t + 1e-6))
        area_thresh = max(area_thresh, cfg["min_defect_px"])

        contours, _ = cv2.findContours(bmap, cv2.RETR_EXTERNAL,
                                       cv2.CHAIN_APPROX_SIMPLE)
        mask = np.zeros((h, w), dtype=np.uint8)
        kept = 0
        for c in contours:
            if cv2.contourArea(c) >= area_thresh:
                cv2.drawContours(mask, [c], -1, 255, -1)
                kept += 1
        heat += mask.astype(np.float32) / 255.0
        kept_total += kept

    print(f"  Total blobs kept across all maps: {kept_total}")

    heat_norm = cv2.normalize(
        heat, None, 0, 255,
        cv2.NORM_MINMAX
    ).astype(np.uint8)

    heat_color = cv2.applyColorMap(
        heat_norm,
        cv2.COLORMAP_JET
    )

    overlay = cv2.addWeighted(
        to_bgr(gray),
        0.5,
        heat_color,
        0.5,
        0
    )

    save(
        "05_heatmap_overlay.jpg",
        overlay,
        out_dir
    )

    nonzero = heat_norm[heat_norm > 0]

    if len(nonzero) == 0:
        final_binary = np.zeros_like(heat_norm)
        p=0
    else:
        p = np.percentile(nonzero, 85)

        _, final_binary = cv2.threshold(
            heat_norm,
            p,
            255,
            cv2.THRESH_BINARY
        )

    final_binary = final_binary.astype(np.uint8)
    print(f"  Percentile threshold: {p:.1f}")

    n_regions = cv2.connectedComponents(final_binary)[0] - 1
    print(f"  Final candidate regions: {n_regions}")
    save("06_final_binary.jpg", to_bgr(final_binary), out_dir)
    return final_binary


# ─────────────────────────────────────────────
# STEP 6 — Contour extraction + morphological refinement
# ─────────────────────────────────────────────
def refine_contours(final_binary, gray, cfg, out_dir):
    print("\n[STEP 6] Contour refinement")

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    closed = cv2.morphologyEx(final_binary, cv2.MORPH_CLOSE, kernel)

    contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL,
                                   cv2.CHAIN_APPROX_NONE)

    candidates = []
    vis = to_bgr(gray)
    for c in contours:
        area = cv2.contourArea(c)

        x,y,w,h = cv2.boundingRect(c)

        aspect = max(w,h)/(min(w,h)+1e-6)

        if area < 20 and aspect < 4:
            continue
        mask = np.zeros_like(gray)
        cv2.drawContours(mask, [c], -1, 255, -1)
        candidates.append({"contour": c, "mask": mask, "area": area})
        cv2.drawContours(vis, [c], -1, (0, 255, 0), 1)

    print(f"  Candidates after size filter: {len(candidates)}")
    save("06b_refined_contours.jpg", vis, out_dir)
    return candidates


# ─────────────────────────────────────────────
# STEP 7 — Feature extraction (SGD + color)
# ─────────────────────────────────────────────
def extract_features(candidates, gray, frame_bgr, cfg, out_dir):
    print("\n[STEP 7] Feature extraction")

    rows = []
    vis = frame_bgr.copy()

    for idx, cand in enumerate(candidates):
        c   = cand["contour"]
        msk = cand["mask"]

        area      = cv2.contourArea(c)
        perimeter = cv2.arcLength(c, True)
        x, y, w, h = cv2.boundingRect(c)

        hull      = cv2.convexHull(c)
        hull_area = max(cv2.contourArea(hull), 1e-6)

        compactness    = (4 * np.pi * area) / (perimeter**2 + 1e-6)
        rectangularity = area / (w * h + 1e-6)
        elongation     = min(w, h) / (max(w, h) + 1e-6)
        solidity       = area / hull_area
        roundness      = (4 * area) / (np.pi * max(w, h)**2 + 1e-6)

        dist_map   = cv2.distanceTransform(msk, cv2.DIST_L2, 5)
        inscribed_r = float(dist_map.max()) + 1e-6
        _, enc_r   = cv2.minEnclosingCircle(c)
        enc_r      = max(enc_r, 1e-6)
        dev_index  = (np.pi * inscribed_r**2) / (area + 1e-6)
        eucl_leng  = inscribed_r / enc_r

        M = cv2.moments(c)
        cx_m = M["m10"] / (M["m00"] + 1e-6)
        cy_m = M["m01"] / (M["m00"] + 1e-6)
        left  = np.sum(msk[:, :int(cx_m)])
        right = np.sum(msk[:, int(cx_m):])
        top   = np.sum(msk[:int(cy_m), :])
        bot   = np.sum(msk[int(cy_m):, :])
        sym_h = min(left, right) / (max(left, right) + 1e-6)
        sym_v = min(top,  bot)   / (max(top,  bot)  + 1e-6)
        symmetry = sym_h * sym_v

        roi = frame_bgr[y:y+h, x:x+w]
        if roi.size == 0:
            mean_hue = mean_sat = mean_val = 0.0
        else:
            hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
            mean_hue = float(hsv[:,:,0].mean()) / 180.0
            mean_sat = float(hsv[:,:,1].mean()) / 255.0
            mean_val = float(hsv[:,:,2].mean()) / 255.0

        gray_roi = gray[y:y+h, x:x+w]

        if gray_roi.size == 0:
            mean_intensity = 0
            std_intensity = 0
            contrast = 0
            lap_var = 0
            edge_density = 0
            entropy = 0

        else:

            mean_intensity = float(np.mean(gray_roi))

            std_intensity = float(np.std(gray_roi))

            contrast = float(
                gray_roi.max() - gray_roi.min()
            )

            lap = cv2.Laplacian(
                gray_roi,
                cv2.CV_64F
            )

            lap_var = float(
                lap.var()
            )

            edges = cv2.Canny(
                gray_roi,
                40,
                120
            )

            edge_density = np.count_nonzero(edges) / edges.size

            hist = cv2.calcHist(
                [gray_roi],
                [0],
                None,
                [256],
                [0,256]
            )

            hist /= hist.sum() + 1e-9

            entropy = float(
                -np.sum(
                    hist * np.log2(hist + 1e-9)
                )
            )

        feat = [compactness, rectangularity, roundness, dev_index,
                solidity, elongation, symmetry, eucl_leng,
                mean_hue, mean_sat, mean_val]

        area_mm2  = area  / (cfg["px_per_mm"]**2)
        length_mm = max(w, h) / cfg["px_per_mm"]

        rows.append({
            "id":            idx,
            "x": x, "y": y, "w": w, "h": h,
            "area_px":       round(area, 1),
            "area_mm2":      round(area_mm2, 3),
            "length_mm":     round(length_mm, 3),
            "compactness":   round(compactness, 4),
            "rectangularity":round(rectangularity, 4),
            "roundness":     round(roundness, 4),
            "dev_index":     round(dev_index, 4),
            "solidity":      round(solidity, 4),
            "elongation":    round(elongation, 4),
            "symmetry":      round(symmetry, 4),
            "eucl_leng":     round(eucl_leng, 4),
            "mean_hue":      round(mean_hue, 4),
            "mean_sat":      round(mean_sat, 4),
            "mean_val":      round(mean_val, 4),
            "mean_intensity": round(mean_intensity, 2),
            "std_intensity":  round(std_intensity, 2),
            "contrast":       round(contrast, 2),
            "lap_var":        round(lap_var, 2),
            "edge_density":   round(edge_density, 4),
            "entropy":        round(entropy, 4),
            "feature_vec":   feat,
        })

        cv2.rectangle(vis, (x, y), (x+w, y+h), (0, 200, 255), 1)
        cv2.putText(vis, f"#{idx}", (x, y-4),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 200, 255), 1)

        print(f"  #{idx:2d}  area={area_mm2:.2f}mm²  len={length_mm:.2f}mm  "
              f"comp={compactness:.3f}  rect={rectangularity:.3f}  "
              f"elong={elongation:.3f}  sol={solidity:.3f}")

    save("07_features_vis.jpg", vis, out_dir)

    if rows:
        csv_path = os.path.join(out_dir, "07_features.csv")
        keys = [k for k in rows[0].keys() if k != "feature_vec"]
        with open(csv_path, "w", newline="") as f:
            w_ = csv.DictWriter(f, fieldnames=keys)
            w_.writeheader()
            for r in rows:
                w_.writerow({k: r[k] for k in keys})
        print(f"  Features saved → {csv_path}")

    return rows


# ─────────────────────────────────────────────
# STEP 7b — Shape descriptors / scoring helpers
# ────────────────────────────────────────────
def _shape_descriptors(cand):
    contour = cand["contour"]
    mask    = cand["mask"]

    area = cv2.contourArea(contour)
    perimeter = cv2.arcLength(contour, True)
    x, y, w, h = cv2.boundingRect(contour)

    hull = cv2.convexHull(contour)
    hull_area = max(cv2.contourArea(hull), 1e-6)

    compactness    = (4 * np.pi * area) / (perimeter**2 + 1e-6)
    rectangularity = area / (w * h + 1e-6)
    elongation     = min(w, h) / (max(w, h) + 1e-6)
    solidity       = area / hull_area
    roundness      = (4 * area) / (np.pi * max(w, h)**2 + 1e-6)

    dist = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    inscribed = float(dist.max()) + 1e-6
    _, enc = cv2.minEnclosingCircle(contour)
    enc = max(enc, 1e-6)
    dev_index = (np.pi * inscribed**2) / (area + 1e-6)
    eucl = inscribed / enc

    return {
        "area": area, "x": x, "y": y, "w": w, "h": h,
        "compactness": compactness,
        "rectangularity": rectangularity,
        "elongation": elongation,
        "solidity": solidity,
        "roundness": roundness,
        "dev_index": dev_index,
        "eucl_leng": eucl,
    }

def feature_filter(cand, cfg=CFG):
    d = _shape_descriptors(cand)
    if d["area"] < 20:
        return False
    score = 0
    if d["solidity"]       > 0.80: score += 1
    if d["compactness"]    > 0.40: score += 1
    if d["roundness"]      > 0.25: score += 1
    if d["rectangularity"] > 0.35: score += 1
    if d["elongation"]     > 0.20: score += 1
    if d["eucl_leng"]      > 0.25: score += 1
    if d["dev_index"]      > 0.45: score += 1
    return score >= cfg.get("shape_filter_min_votes", 4)

def shape_score(cand):
    d = _shape_descriptors(cand)
    def clip01(v):
        return max(0.0, min(1.0, v))
    s = (
        0.20 * clip01(d["compactness"]) +
        0.15 * clip01(d["rectangularity"]) +
        0.15 * clip01(d["roundness"]) +
        0.20 * clip01(d["solidity"]) +
        0.10 * clip01(d["elongation"]) +
        0.10 * clip01(d["eucl_leng"]) +
        0.10 * clip01(d["dev_index"])
    )
    return clip01(s)

def _inside_ring_split(gray, cand, ring_px=11):
    if ring_px % 2 == 0:
        ring_px += 1
    pad = ring_px + 2
    x, y, w, h = cv2.boundingRect(cand["contour"])
    H, W = gray.shape[:2]
    x1, y1 = max(0, x - pad), max(0, y - pad)
    x2, y2 = min(W, x + w + pad), min(H, y + h + pad)
    roi_gray = gray[y1:y2, x1:x2]
    roi_mask = cand["mask"][y1:y2, x1:x2]
    if roi_gray.size == 0 or roi_mask.size == 0:
        return None
    inside_mask = (roi_mask > 0).astype(np.uint8) * 255
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ring_px, ring_px))
    outer  = cv2.dilate(inside_mask, kernel, iterations=1)
    ring   = cv2.subtract(outer, inside_mask)
    inside_pixels = roi_gray[inside_mask > 0]
    ring_pixels   = roi_gray[ring > 0]
    if inside_pixels.size < 4 or ring_pixels.size < 4:
        return None
    return roi_gray, inside_mask, ring, inside_pixels, ring_pixels

# ─────────────────────────────────────────────
# STEP 6b — Early texture rejection
# ─────────────────────────────────────────────
def reject_texture_contours(candidates, gray, cfg, out_dir):
    print("\n[STEP 6b] Early texture rejection (circularity/solidity/inside-vs-ring)")
    min_votes = cfg.get("texture_reject_min_votes", 3)
    ring_px   = cfg.get("texture_reject_ring_px", 11)
    circularity_thresh = cfg.get("texture_reject_circularity_thresh", 0.45)
    solidity_thresh     = cfg.get("texture_reject_solidity_thresh", 0.80)
    mean_diff_thresh     = cfg.get("texture_reject_mean_diff_thresh", 6)
    std_diff_thresh       = cfg.get("texture_reject_std_diff_thresh", 4)
    kept = []
    vis = to_bgr(gray)
    for idx, cand in enumerate(candidates):
        c = cand["contour"]
        area = cand["area"]
        perimeter = cv2.arcLength(c, True)
        circularity = (4 * np.pi * area) / (perimeter * perimeter + 1e-6)
        hull = cv2.convexHull(c)
        hull_area = cv2.contourArea(hull)
        solidity = area / (hull_area + 1e-6)
        votes = 0
        reasons = []
        if circularity < circularity_thresh:
            votes += 1
            reasons.append(f"circularity={circularity:.2f}<{circularity_thresh}")
        if solidity < solidity_thresh:
            votes += 1
            reasons.append(f"solidity={solidity:.2f}<{solidity_thresh}")
        split = _inside_ring_split(gray, cand, ring_px)
        if split is not None:
            roi_gray, inside_mask, ring, inside_px, ring_px_vals = split
            mean_inside = float(inside_px.mean())
            mean_outside = float(ring_px_vals.mean())
            mean_diff = abs(mean_inside - mean_outside)
            if mean_diff < mean_diff_thresh:
                votes += 1
                reasons.append(f"mean_diff={mean_diff:.1f}<{mean_diff_thresh}")
            std_inside = float(inside_px.std())
            std_outside = float(ring_px_vals.std())
            std_diff = abs(std_inside - std_outside)
            if std_diff < std_diff_thresh:
                votes += 1
                reasons.append(f"std_diff={std_diff:.1f}<{std_diff_thresh}")
            edges = cv2.Canny(roi_gray, 40, 120)
            edge_inside_count = np.count_nonzero(edges[inside_mask > 0])
            edge_ring_count   = np.count_nonzero(edges[ring > 0])
            edge_density_inside = edge_inside_count / max(1, np.count_nonzero(inside_mask))
            edge_density_ring   = edge_ring_count / max(1, np.count_nonzero(ring))
            if edge_density_inside > edge_density_ring:
                votes += 1
                reasons.append(
                    f"edge_in={edge_density_inside:.2f}>edge_ring={edge_density_ring:.2f}"
                )
        if votes >= min_votes:
            print(f"  #{idx} REJECTED (texture, votes={votes}/5): " + ", ".join(reasons))
            cv2.drawContours(vis, [c], -1, (0, 0, 255), 1)
            continue
        kept.append(cand)
        cv2.drawContours(vis, [c], -1, (0, 255, 0), 1)
    print(f"  Candidates after texture rejection: {len(kept)} / {len(candidates)}")
    save("06c_texture_rejected.jpg", vis, out_dir)
    return kept

def appearance_score(gray, cand, cfg=None):
    cfg = cfg or {}
    ring_px = cfg.get("appearance_ring_px", 11)
    split = _inside_ring_split(gray, cand, ring_px)
    if split is None:
        return 0.0
    roi_gray, inside_mask, ring, inside_pixels, ring_pixels = split
    mean_inside = float(inside_pixels.mean())
    mean_ring   = float(ring_pixels.mean())
    mean_diff   = abs(mean_inside - mean_ring)
    std_inside = float(inside_pixels.std())
    std_ring   = float(ring_pixels.std())
    std_diff   = abs(std_inside - std_ring)
    hist_inside = cv2.calcHist(
        [inside_pixels.astype(np.uint8)], [0], None, [32], [0, 256]
    )
    hist_ring = cv2.calcHist(
        [ring_pixels.astype(np.uint8)], [0], None, [32], [0, 256]
    )
    cv2.normalize(hist_inside, hist_inside)
    cv2.normalize(hist_ring, hist_ring)
    hist_distance = cv2.compareHist(
        hist_inside, hist_ring, cv2.HISTCMP_BHATTACHARYYA
    )
    edges_full = cv2.Canny(roi_gray, 40, 120)
    edges_inside = edges_full[inside_mask > 0]
    edges_ring   = edges_full[ring > 0]
    edge_density_inside = (
        np.count_nonzero(edges_inside) / max(1, edges_inside.size)
    )
    edge_density_ring = (
        np.count_nonzero(edges_ring) / max(1, edges_ring.size)
    )
    edge_ratio = edge_density_inside / (edge_density_ring + 1e-6)
    lap_full = cv2.Laplacian(roi_gray, cv2.CV_64F)
    lap_inside = lap_full[inside_mask > 0]
    lap_ring   = lap_full[ring > 0]
    lap_var_inside = float(lap_inside.var()) if lap_inside.size else 0.0
    lap_var_ring   = float(lap_ring.var()) if lap_ring.size else 0.0
    lap_diff = abs(lap_var_inside - lap_var_ring)
    score = 0.0
    edge_ratio_thresh = cfg.get("appearance_edge_ratio_thresh", 1.5)
    if mean_diff > cfg.get("appearance_mean_diff_thresh", 12):
        score += 0.25
    if std_diff > cfg.get("appearance_std_diff_thresh", 8):
        score += 0.15
    if hist_distance > cfg.get("appearance_hist_dist_thresh", 0.25):
        score += 0.25
    if edge_ratio > edge_ratio_thresh or edge_ratio < (1.0 / edge_ratio_thresh):
        score += 0.15
    if lap_diff > cfg.get("appearance_lap_diff_thresh", 200):
        score += 0.20
    return max(0.0, min(1.0, score))


# ─────────────────────────────────────────────
# STEP 8a — Unsupervised Clustering (1st Classifier)
# Uses Gaussian Mixture Model (GMM) on the extracted shape and appearance
# features to separate candidates into "defect-like" vs "texture/noise" clusters.
# This acts as a 1st pass filter before the supervised YOLO classifier.
# ─────────────────────────────────────────────
def unsupervised_filter(candidates, feature_rows, frame_bgr, cfg, out_dir):
    print("\n[STEP 8a] Unsupervised Clustering (1st Classifier)")
    if not feature_rows:
        return []
    
    feat_keys = [
        "compactness", "rectangularity", "roundness", "dev_index", 
        "solidity", "elongation", "symmetry", "eucl_leng", 
        "mean_hue", "mean_sat", "mean_val",
        "mean_intensity", "std_intensity", "contrast", 
        "lap_var", "edge_density", "entropy"
    ]
    
    X = np.array([[r[k] for k in feat_keys] for r in feature_rows])
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    n_components = 2
    gmm = GaussianMixture(n_components=n_components, random_state=42, covariance_type='full')
    gmm.fit(X_scaled)
    labels = gmm.predict(X_scaled)
    
    # Get indices for key features
    compactness_idx = feat_keys.index("compactness")
    solidity_idx = feat_keys.index("solidity")
    roundness_idx = feat_keys.index("roundness")
    
    cluster_means = np.zeros((n_components, X.shape[1]))
    for i in range(n_components):
        mask = (labels == i)
        if np.any(mask):
            cluster_means[i] = X[mask].mean(axis=0)
    
    # CRITICAL FIX: Defects have HIGH compactness, solidity, roundness
    # The cluster with HIGHER average of these = defect cluster
    defect_score = (
        cluster_means[:, compactness_idx] * 0.40 +
        cluster_means[:, solidity_idx] * 0.35 +
        cluster_means[:, roundness_idx] * 0.25
    )
    
    defect_cluster = np.argmax(defect_score)
    
    print(f"  Cluster 0 mean (comp/sol/round): {cluster_means[0, compactness_idx]:.3f} / {cluster_means[0, solidity_idx]:.3f} / {cluster_means[0, roundness_idx]:.3f}")
    print(f"  Cluster 1 mean (comp/sol/round): {cluster_means[1, compactness_idx]:.3f} / {cluster_means[1, solidity_idx]:.3f} / {cluster_means[1, roundness_idx]:.3f}")
    print(f"  Defect scores: Cluster 0={defect_score[0]:.3f}, Cluster 1={defect_score[1]:.3f}")
    print(f"  Identified Defect Cluster: {defect_cluster}")
    
    # Visualization
    kept_candidates = []
    kept_ids = []
    rejected_ids = []
    
    vis = frame_bgr.copy()
    
    for i, cand in enumerate(candidates):
        row = feature_rows[i]
        x, y, w, h = row['x'], row['y'], row['w'], row['h']
        
        if labels[i] == defect_cluster:
            kept_candidates.append(cand)
            kept_ids.append(i)
            cv2.rectangle(vis, (x, y), (x+w, y+h), (0, 255, 0), 2)
            cv2.putText(vis, f"Defect #{i}", (x, max(y-5, 10)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
        else:
            rejected_ids.append(i)
            cv2.rectangle(vis, (x, y), (x+w, y+h), (0, 0, 255), 1)
            cv2.putText(vis, f"Noise #{i}", (x, max(y-5, 10)), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 0, 255), 1)
            
    print(f"  Candidates kept after unsupervised filter: {len(kept_candidates)} / {len(candidates)}")
    print(f"  \033[92mKept IDs (Defect Cluster): {kept_ids[:20]}{'...' if len(kept_ids) > 20 else ''}\033[0m")
    print(f"  \033[91mRejected IDs (Noise Cluster): {rejected_ids[:20]}{'...' if len(rejected_ids) > 20 else ''}\033[0m")
    
    save("08a_unsupervised_clusters.jpg", vis, out_dir)
    
    return kept_candidates


# ─────────────────────────────────────────────
# STEP 8b — Classification (YOLO11s-cls .pt)
# Now acts as the 2nd pass. The unsupervised GMM (Step 8a) has already
# filtered out the bulk of texture/noise. YOLO confirms the defect type
# and provides a confidence score.
# ─────────────────────────────────────────────
def classify(candidates, gray, frame_bgr, cfg, out_dir):

    print("\n[STEP 8b] CNN Classification (2nd Classifier / Cross-check)")

    results = []
    vis = frame_bgr.copy()

    for idx, cand in enumerate(candidates):

        x, y, w, h = cv2.boundingRect(cand["contour"])

        pad = 10

        x1 = max(0, x - pad)
        y1 = max(0, y - pad)

        x2 = min(
            frame_bgr.shape[1],
            x + w + pad
        )

        y2 = min(
            frame_bgr.shape[0],
            y + h + pad
        )

        patch = gray[y1:y2, x1:x2]

        if patch.size == 0:
            continue

        patch_bgr = cv2.cvtColor(patch, cv2.COLOR_GRAY2BGR)
        patch_bgr = cv2.resize(patch_bgr, (224, 224))

        yolo_result = YOLO_MODEL.predict(
            patch_bgr,
            imgsz=224,
            device=DEVICE,
            verbose=False
        )[0]

        probs = yolo_result.probs          
        pred  = int(probs.top1)            
        conf  = float(probs.top1conf.item())  
        cls_name = YOLO_CLASSES[pred]

        high_conf = cfg.get("yolo_high_conf", 0.90)

        if conf >= high_conf:
            s_score = None
            a_score = None
            final_score = conf
            print(
                f"#{idx} {cls_name} yolo_conf={conf:.4f} "
                f"(>= high_conf {high_conf:.2f} -> trusting YOLO, no shape/appearance check)"
            )
        else:
            s_score = shape_score(cand)
            a_score = appearance_score(gray, cand, cfg)
            final_score = (
                0.40 * conf +
                0.30 * s_score +
                0.30 * a_score
            )
            print(
                f"#{idx} {cls_name} yolo_conf={conf:.4f} "
                f"shape_score={s_score:.4f} appearance_score={a_score:.4f} "
                f"final_score={final_score:.4f}"
            )

        if conf < cfg.get("yolo_conf_thresh", 0.50):
            continue

        if conf < high_conf and final_score < cfg.get("final_score_thresh", 0.50):
            continue

        if cls_name.lower() == "normal":
            continue

        elif cls_name.lower() == "porosity":
            color = (0, 255, 0)
            defect_name = "Porosity"

        elif cls_name.lower() == "spatter":
            color = (0, 0, 255)
            defect_name = "Spatter"

        else:
            continue

        area = cv2.contourArea(
            cand["contour"]
        )

        area_mm2 = area / (
            cfg["px_per_mm"]**2
        )

        severity = (
            "MAJOR"
            if area_mm2 > 5
            else "MINOR"
        )

        decision = (
            "REJECT"
            if severity == "MAJOR"
            else "REVIEW"
        )

        results.append({
            "id": idx,
            "type": defect_name,
            "severity": severity,
            "decision": decision,
            "confidence": round(conf, 3),
            "shape_score": (round(s_score, 3) if s_score is not None else None),
            "appearance_score": (round(a_score, 3) if a_score is not None else None),
            "final_score": round(final_score, 3),
            "area_mm2": round(area_mm2, 3),
            "bbox": (x, y, w, h)
        })

        cv2.rectangle(
            vis,
            (x, y),
            (x+w, y+h),
            color,
            2
        )

        cv2.putText(
            vis,
            f"{defect_name} {conf:.0%}",
            (x, y-5),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            color,
            1
        )

        print(
            f"#{idx} "
            f"{defect_name} "
            f"{conf:.2f}"
        )

    save(
        "08_classification.jpg",
        vis,
        out_dir
    )

    return results


# ────────────────────────────────────────────
# STEP 9 — Final result summary image
# ─────────────────────────────────────────────
def final_summary(results, gray, frame_bgr, cfg, out_dir):
    print("\n[STEP 9] Final summary")

    overall = "ACCEPT"
    for r in results:
        if r["decision"] == "REJECT":
            overall = "REJECT"
            break
        elif r["decision"] == "REVIEW":
            overall = "REVIEW"

    vis = frame_bgr.copy()

    for r in results:
        x, y, w, h = r["bbox"]

        color_map = {
            "Porosity": (0, 255, 0),
            "Spatter":  (0, 0, 255)
        }

        col = color_map.get(r["type"], (255, 255, 0))

        cv2.rectangle(vis, (x, y), (x+w, y+h), col, 2)

        cv2.putText(
            vis,
            r["type"],
            (x, max(y-4, 10)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            col,
            1
        )

    banner_col = (0,180,0) if overall=="ACCEPT" else \
                 (0,140,255) if overall=="REVIEW" else (0,0,220)
    cv2.rectangle(vis, (0, 0), (vis.shape[1], 50), banner_col, -1)
    cv2.putText(vis, f"RESULT: {overall}  |  {len(results)} defect(s) found",
                (10, 33), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255,255,255), 2)

    save("09_final_result.jpg", vis, out_dir)

    print("\n" + "="*55)
    print(f"  OVERALL DECISION : {overall}")
    print(f"  Total defects    : {len(results)}")
    for r in results:
        print(f"    #{r['id']}  {r['type']:20s}  "
              f"{r['area_mm2']:.2f}mm²  {r['severity']}  "
              f"final_score={r.get('final_score', 0):.3f}")
    print("="*55)

    log_path = os.path.join(out_dir, "09_result_log.txt")
    with open(log_path, "w") as f:
        f.write(f"timestamp : {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"decision  : {overall}\n")
        f.write(f"n_defects : {len(results)}\n\n")
        for r in results:
            f.write(str(r) + "\n")
    print(f"  Log saved → {log_path}")

    return overall


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
def run_pipeline(image_path, cfg=CFG):
    ensure_dir(cfg["output_dir"])

    global YOLO_MODEL, YOLO_CLASSES
    if YOLO_MODEL is None:
        print("\nLoading YOLO11s-cls classifier...")
        YOLO_MODEL, YOLO_CLASSES = load_classifier(
            cfg["classifier_model"]
        )
        print("Classes:", YOLO_CLASSES)

    print(f"\n{'='*55}")
    print(f"  Weld Defect Detection Pipeline")
    print(f"  Image : {image_path}")
    print(f"{'='*55}")

    # load
    frame = cv2.imread(image_path)
    print("=" * 60)
    print("Loaded image:", image_path)
    print("Shape:", frame.shape)

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    score = cv2.Laplacian(gray, cv2.CV_64F).var()

    print("Blur score immediately after imread:", score)

    cv2.imwrite("debug_loaded.jpg", frame)
    print("=" * 60)
    if frame is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")
    print(f"  Image size: {frame.shape[1]}×{frame.shape[0]} px")

    save("00_original.jpg", frame, cfg["output_dir"])

    # ── Step 1: Quality gate ──────────────────────────────────────
    ok, gray, qvis = quality_gate(frame, cfg)
    save("01_quality_gate.jpg", qvis, cfg["output_dir"])
    if not ok:
        gray_check  = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        blur_score  = cv2.Laplacian(gray_check, cv2.CV_64F).var()
        mean_bright = float(gray_check.mean())
        reasons = []
        if blur_score < cfg["blur_threshold"]:
            reasons.append("too blurry")
        if mean_bright < cfg["min_brightness"]:
            reasons.append("underexposed")
        if mean_bright > cfg["max_brightness"]:
            reasons.append("overexposed")
        print("\n  Frame rejected at quality gate. Fix lighting/focus and retry.")
        return {
            "decision":     "RETAKE",
            "defects":      [],
            "result_image": None,
            "error":        ", ".join(reasons) if reasons else "quality check failed",
        }

    # ── Step 2: Histogram stretch ─────────────────────────────────
    gray = histogram_stretch(gray, cfg, cfg["output_dir"])

    # ── Step 3: Multi-scale DoG ──────────────────────────────────
    diff_images = multiscale_dog(gray, cfg, cfg["output_dir"])

    # ── Step 4: Multi-intensity binarization ─────────────────────
    binary_maps = multi_intensity_binarize(diff_images, cfg, cfg["output_dir"])

    # ── Step 5: Screen + merge ────────────────────────────────────
    final_binary = screen_and_merge(binary_maps, gray, cfg, cfg["output_dir"])

    # ── Step 6: Contour refinement ────────────────────────────────
    candidates = refine_contours(final_binary, gray, cfg, cfg["output_dir"])

    if not candidates:
        print("\n  No defect candidates found. Weld appears clean.")
        vis = frame.copy()
        cv2.putText(vis, "RESULT: ACCEPT — No defects found", (10, 33),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,200,0), 2)
        result_path = save("09_final_result.jpg", vis, cfg["output_dir"])
        return {
            "decision":     "ACCEPT",
            "defects":      [],
            "result_image": result_path,
            "error":        None,
        }

    # ── Step 6b: Early texture rejection (circularity/solidity/inside-vs-ring) ──
    candidates = reject_texture_contours(candidates, gray, cfg, cfg["output_dir"])

    if not candidates:
        print("\n  No defect candidates remain after texture rejection. Weld appears clean.")
        vis = frame.copy()
        cv2.putText(vis, "RESULT: ACCEPT — No defects found", (10, 33),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,200,0), 2)
        result_path = save("09_final_result.jpg", vis, cfg["output_dir"])
        return {
            "decision":     "ACCEPT",
            "defects":      [],
            "result_image": result_path,
            "error":        None,
        }

    # ── Step 7: Feature extraction (for CSV / inspection logging) ──
    feature_rows = extract_features(candidates, gray, frame, cfg, cfg["output_dir"])

    # ── Step 8a: Unsupervised Clustering (1st Classifier) ──
    candidates = unsupervised_filter(candidates, feature_rows, frame, cfg, cfg["output_dir"])
    if not candidates:
        print("\n  No defect candidates remain after unsupervised clustering. Weld appears clean.")
        vis = frame.copy()
        cv2.putText(vis, "RESULT: ACCEPT — No defects found", (10, 33),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,200,0), 2)
        result_path = save("09_final_result.jpg", vis, cfg["output_dir"])
        return {
            "decision":     "ACCEPT",
            "defects":      [],
            "result_image": result_path,
            "error":        None,
        }

    # ── Step 8b: YOLO Classification (2nd Classifier / Cross-check) ──
    results = classify(
        candidates,
        gray,
        frame,
        cfg,
        cfg["output_dir"]
    )

    # ── Step 9: Final summary ─────────────────────────────────────
    decision = final_summary(results, gray, frame, cfg, cfg["output_dir"])

    return {
        "decision":     decision,
        "defects":      results,
        "result_image": os.path.join(cfg["output_dir"], "09_final_result.jpg"),
        "error":        None,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Weld defect detection pipeline")
    parser.add_argument("--image",      required=True,        help="Path to weld image")
    parser.add_argument("--px_per_mm",  type=float, default=10.0,
                        help="Camera calibration: pixels per mm")
    parser.add_argument("--output_dir", default="output",     help="Output folder")
    args = parser.parse_args()

    CFG["px_per_mm"]  = args.px_per_mm
    CFG["output_dir"] = args.output_dir

    run_pipeline(args.image, CFG)