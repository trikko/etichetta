#!/usr/bin/env python3
"""
Train a YOLO model on an Etichetta project and export it for Etichetta's AI assistant.

The project is the folder you open in Etichetta:

    my-project/
        images/        your pictures
        labels/        one .txt for each annotated picture (written by Etichetta)
        classes.txt    one class name per line (or labels.txt)

Requirements:

    pip install ultralytics

Quick start:

    python train.py my-project

At the end you get my-project/models/<name>/model.onnx and labels.txt:
load them in Etichetta from Edit > AI settings.
"""

import argparse
import os
import random
import shutil
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def read_classes(project):
    for name in ("labels.txt", "classes.txt"):
        f = project / name
        if f.exists():
            classes = [l.strip() for l in f.read_text().splitlines() if l.strip()]
            if classes:
                return classes, f
    sys.exit(f"No classes.txt or labels.txt found in {project}")


def read_label_file(path, num_classes):
    """Return the valid YOLO lines of a label file, and how many lines were skipped."""
    lines, skipped = [], 0

    for raw in path.read_text().splitlines():
        parts = raw.split()
        if not parts:
            continue

        try:
            cls = int(parts[0])
            cx, cy, w, h = (float(v) for v in parts[1:5])
        except (ValueError, IndexError):
            skipped += 1
            continue

        # Boxes drawn from bottom-right have negative size
        w, h = abs(w), abs(h)

        if not 0 <= cls < num_classes or w == 0 or h == 0:
            skipped += 1
            continue

        lines.append(f"{cls} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}")

    return lines, skipped


def link_or_copy(src, dst):
    try:
        os.symlink(src.resolve(), dst)
    except (OSError, NotImplementedError):
        shutil.copy2(src, dst)


def build_dataset(project, classes, dest, val_fraction, include_unlabeled, seed):
    images = sorted(p for p in (project / "images").iterdir() if p.suffix.lower() in IMAGE_EXTENSIONS)
    if not images:
        sys.exit(f"No images found in {project / 'images'}")

    samples, unlabeled, skipped_lines = [], 0, 0
    counts = Counter()

    for image in images:
        label = project / "labels" / (image.stem + ".txt")

        if label.exists():
            lines, skipped = read_label_file(label, len(classes))
            skipped_lines += skipped
        elif include_unlabeled:
            lines = []
        else:
            unlabeled += 1
            continue

        counts.update(int(l.split()[0]) for l in lines)
        samples.append((image, lines))

    if len(samples) < 2:
        sys.exit("At least 2 annotated images are needed (one for training, one for validation)")

    random.Random(seed).shuffle(samples)
    n_val = max(1, round(len(samples) * val_fraction))
    splits = {"val": samples[:n_val], "train": samples[n_val:]}

    if not splits["train"]:
        sys.exit("Validation split leaves no images for training: lower --val")

    if dest.exists():
        shutil.rmtree(dest)

    for split, items in splits.items():
        (dest / split / "images").mkdir(parents=True)
        (dest / split / "labels").mkdir(parents=True)

        for image, lines in items:
            link_or_copy(image, dest / split / "images" / image.name)
            (dest / split / "labels" / (image.stem + ".txt")).write_text("\n".join(lines) + ("\n" if lines else ""))

    names = "\n".join(f"  {i}: {json_string(c)}" for i, c in enumerate(classes))
    (dest / "data.yaml").write_text(f"path: {json_string(str(dest.resolve()))}\ntrain: train/images\nval: val/images\nnames:\n{names}\n")

    print(f"Images: {len(splits['train'])} for training, {len(splits['val'])} for validation")
    if unlabeled:
        print(f"Skipped {unlabeled} images never annotated (use --include-unlabeled to use them as background)")
    if skipped_lines:
        print(f"Skipped {skipped_lines} invalid lines in label files")
    print("Boxes per class:")
    for i, c in enumerate(classes):
        if counts[i]:
            print(f"  {i:3d} {c}: {counts[i]}")

    missing = [c for i, c in enumerate(classes) if counts[i] == 0]
    if missing:
        shown = ", ".join(missing[:10]) + (f" and {len(missing) - 10} more" if len(missing) > 10 else "")
        print(f"Warning: no examples for {shown}. The model won't learn these classes.")

    return dest / "data.yaml"


def json_string(s):
    # YAML accepts JSON strings: safe for names with spaces, colons, quotes
    import json
    return json.dumps(s)


def main():
    parser = argparse.ArgumentParser(
        description="Train a YOLO model on an Etichetta project and export it to ONNX for Etichetta.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("project", type=Path, help="Etichetta project folder (with images/, labels/ and classes.txt)")
    parser.add_argument("--model", default="yolo11n.pt",
                        help="starting model: yolo11n/s/m/l/x.pt, yolov8n.pt, yolo26n.pt... (downloaded automatically) "
                             "or a .pt you trained before. Bigger models are more accurate and slower")
    parser.add_argument("--epochs", type=int, default=100, help="training epochs")
    parser.add_argument("--patience", type=int, default=30, help="stop early after this many epochs without improvements")
    parser.add_argument("--imgsz", type=int, default=640, help="image size used by the model")
    parser.add_argument("--batch", type=int, default=16, help="images per batch: lower it if you run out of memory")
    parser.add_argument("--device", default=None, help="cpu, 0 (first GPU), 0,1 (two GPUs), mps (Apple). Default: GPU if available")
    parser.add_argument("--val", type=float, default=0.2, help="fraction of images used for validation")
    parser.add_argument("--seed", type=int, default=0, help="random seed for the train/validation split")
    parser.add_argument("--include-unlabeled", action="store_true",
                        help="use images without a label file as background (no objects)")
    parser.add_argument("--name", default=None, help="name of this training. Default: date and time")
    parser.add_argument("--output", type=Path, default=None, help="where to save the results. Default: <project>/models")
    args = parser.parse_args()

    project = args.project
    if not (project / "images").is_dir():
        sys.exit(f"{project} doesn't look like an Etichetta project: images/ is missing")

    try:
        from ultralytics import YOLO
    except ImportError:
        sys.exit("Ultralytics is not installed. Run: pip install ultralytics")

    classes, classes_file = read_classes(project)
    name = args.name or datetime.now().strftime("%Y%m%d-%H%M%S")
    out = (args.output or project / "models").resolve() / name

    data = build_dataset(project, classes, out / "dataset", args.val, args.include_unlabeled, args.seed)

    model = YOLO(args.model)
    model.train(
        data=str(data),
        epochs=args.epochs,
        patience=args.patience,
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        seed=args.seed,
        project=str(out),
        name="training",
        exist_ok=True,
    )

    best = out / "training" / "weights" / "best.pt"

    # opset 17 keeps the model readable by the onnxruntime shipped with Etichetta
    onnx = Path(YOLO(str(best)).export(format="onnx", imgsz=args.imgsz, opset=17))
    shutil.copy2(onnx, out / "model.onnx")
    shutil.copy2(classes_file, out / "labels.txt")

    print()
    print("Done! In Etichetta open Edit > AI settings and load:")
    print(f"  model:  {out / 'model.onnx'}")
    print(f"  labels: {out / 'labels.txt'}")
    print(f"Charts and metrics of the training are in {out / 'training'}")
    print(f"To train again starting from this model: --model {best}")


if __name__ == "__main__":
    main()
