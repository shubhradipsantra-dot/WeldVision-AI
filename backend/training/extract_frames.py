import cv2
import os


def _resize_max_dim(frame, max_dim=1280):
    """Downscale frame so its longer side is at most max_dim. Never
    upscales -- if the video is already smaller than max_dim, the frame
    is returned unchanged."""
    h, w = frame.shape[:2]

    if max(h, w) <= max_dim:
        return frame

    scale = max_dim / max(h, w)
    new_w = round(w * scale)
    new_h = round(h * scale)

    return cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_AREA)


def extract_frames(
    video_path,
    output_dir,
    sample_rate_sec=1.0,
    max_dim=1280
):
    os.makedirs(output_dir, exist_ok=True)

    cap = cv2.VideoCapture(video_path)

    fps = cap.get(cv2.CAP_PROP_FPS)

    if fps <= 0:
        fps = 25

    frame_interval = max(
        1,
        int(fps * sample_rate_sec)
    )

    frame_idx = 0
    saved = 0

    while True:

        ok, frame = cap.read()

        if not ok:
            break

        if frame_idx % frame_interval == 0:

            frame = _resize_max_dim(frame, max_dim)

            frame_path = os.path.join(
                output_dir,
                f"frame_{saved:06d}.jpg"
            )

            cv2.imwrite(
                frame_path,
                frame
            )

            saved += 1

        frame_idx += 1

    cap.release()

    return saved