import os
import cv2
import albumentations as A
from tqdm import tqdm

# -------------------------------------------------------
# CLASS MAP
# -------------------------------------------------------

CLASS_MAP = {
    0: "Porosity",
    1: "Spatter"
}

# -------------------------------------------------------
# AUGMENTATION PIPELINE
# -------------------------------------------------------

transform = A.Compose(
    [
        A.HorizontalFlip(p=0.5),

        A.RandomBrightnessContrast(
            brightness_limit=0.2,
            contrast_limit=0.2,
            p=0.7
        ),

        A.GaussNoise(
            std_range=(0.1, 0.2),
            p=0.4
        ),

        A.Blur(
            blur_limit=3,
            p=0.3
        ),

        A.Rotate(
            limit=5,
            border_mode=cv2.BORDER_REFLECT,
            p=0.5
        ),

        A.Affine(
            scale=(0.9, 1.1),
            translate_percent=(-0.05, 0.05),
            rotate=(-5, 5),
            p=0.5
        )
    ],

    bbox_params=A.BboxParams(
        format="yolo",
        label_fields=["class_labels"],
        min_visibility=0.1,
        clip=True
    )
)

# -------------------------------------------------------
# READ YOLO LABELS
# -------------------------------------------------------

def read_yolo_labels(label_path):

    bboxes = []
    class_labels = []

    if not os.path.exists(label_path):
        return bboxes, class_labels

    eps = 1e-6

    with open(label_path, "r") as f:

        for line in f:

            parts = line.strip().split()

            if len(parts) != 5:
                continue

            try:
                cls = int(parts[0])

                x = float(parts[1])
                y = float(parts[2])
                w = float(parts[3])
                h = float(parts[4])

            except:
                continue

            # ---------------------------------
            # Basic validation
            # ---------------------------------

            if w <= 0 or h <= 0:
                continue

            if w > 1 or h > 1:
                continue

            # ---------------------------------
            # Clip values
            # ---------------------------------

            x = min(max(x, eps), 1.0 - eps)
            y = min(max(y, eps), 1.0 - eps)
            w = min(max(w, eps), 1.0)
            h = min(max(h, eps), 1.0)

            # ---------------------------------
            # Keep box inside image
            # ---------------------------------

            if x - w/2 < 0:
                x = w/2 + eps

            if y - h/2 < 0:
                y = h/2 + eps

            if x + w/2 > 1:
                x = 1 - w/2 - eps

            if y + h/2 > 1:
                y = 1 - h/2 - eps

            # Final validation

            if x - w/2 < 0:
                continue

            if y - h/2 < 0:
                continue

            if x + w/2 > 1:
                continue

            if y + h/2 > 1:
                continue

            bboxes.append([x, y, w, h])
            class_labels.append(cls)

    return bboxes, class_labels


# -------------------------------------------------------
# SAVE LABELS
# -------------------------------------------------------

def save_yolo_labels(label_path, bboxes, labels):

    with open(label_path, "w") as f:

        for bbox, cls in zip(bboxes, labels):

            x, y, w, h = bbox

            x = min(max(x, 0.0), 1.0)
            y = min(max(y, 0.0), 1.0)
            w = min(max(w, 0.0), 1.0)
            h = min(max(h, 0.0), 1.0)

            f.write(
                f"{cls} "
                f"{x:.6f} "
                f"{y:.6f} "
                f"{w:.6f} "
                f"{h:.6f}\n"
            )


# -------------------------------------------------------
# MAIN AUGMENTATION
# -------------------------------------------------------

def augment_dataset(
    images_dir,
    labels_dir,
    copies_per_image=3
):

    image_files = [
        f for f in os.listdir(images_dir)
        if f.lower().endswith(
            (".jpg", ".jpeg", ".png")
        )
    ]

    for image_name in tqdm(image_files):

        image_path = os.path.join(
            images_dir,
            image_name
        )

        label_path = os.path.join(
            labels_dir,
            os.path.splitext(image_name)[0] + ".txt"
        )

        image = cv2.imread(image_path)

        if image is None:
            continue

        bboxes, labels = read_yolo_labels(
            label_path
        )

        # Images with no bounding boxes are valid background/negative
        # training samples — don't skip them.  We just skip *augmentation*
        # for them (nothing to transform) so they're kept as-is in the
        # dataset and YOLO can learn from them.
        if len(bboxes) == 0:
            continue

        for i in range(copies_per_image):

            try:

                augmented = transform(
                    image=image,
                    bboxes=bboxes,
                    class_labels=labels
                )

            except Exception as e:

                print(f"\nSkipping {image_name}")
                print(e)
                continue

            aug_img = augmented["image"]
            aug_boxes = augmented["bboxes"]
            aug_labels = augmented["class_labels"]

            if len(aug_boxes) == 0:
                continue

            new_image_name = (
                os.path.splitext(image_name)[0]
                + f"_aug{i}.jpg"
            )

            new_label_name = (
                os.path.splitext(image_name)[0]
                + f"_aug{i}.txt"
            )

            cv2.imwrite(
                os.path.join(
                    images_dir,
                    new_image_name
                ),
                aug_img
            )

            save_yolo_labels(
                os.path.join(
                    labels_dir,
                    new_label_name
                ),
                aug_boxes,
                aug_labels
            )

    print("\nAugmentation complete.")