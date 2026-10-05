## Use pretrained AI as assistant
Many people have asked me what the purpose is and how to use AI with Etichetta. The goal is to simplify the annotation of images by leveraging an AI that has already been pre-trained.

For simplicity, let’s assume we want to create an AI capable of distinguishing my cat (“goose”) from other cats (“non_goose”). Below is a photo of Goose that I manually annotated using Etichetta.

<img src="https://github.com/trikko/etichetta/assets/647157/d06c1b0a-15d9-4700-8cb4-3614d463e5f8" width="480">

The standard version of YOLO is able to recognize many different classes from "person" to "toothbrush". Among these is also the “cat” class. Why not take advantage of this potential? By opening the AI settings, I selected the `yolov8s.onnx` model and the `yoloclass.txt` label list. 

<img src="https://github.com/trikko/etichetta/assets/647157/f244c0ab-89f1-4be3-a00d-1cdaab00dd08" width="480">

This list contains all the classes that YOLO recognizes, one per line. I changed line 16 from “cat” to “non_goose”.

```txt
person
bicycle
car
motorbike
... more classes ...
bird
non_goose
dog
... more classes ...
toothbrush
```

In this way, returning to the photos to be labeled and pressing the `A` key, all the cats recognized by the AI are labeled as “non_goose” (with a percentage representing the degree of certainty) 

<img src="https://github.com/trikko/etichetta/assets/647157/efde7eb3-e4ea-4cfd-8f7a-fb41e377fb2e" width="480">
<img src="https://github.com/trikko/etichetta/assets/647157/5a9ff296-58bb-4850-b625-1fc74b67793e" width="480">

Now all I have to do is simply adjust the proposed frame and press the `0` or `1` key to choose the right class (you see? the cat in the second photo is Goose). A nice difference compared to making all the rectangles from scratch!

## Supported models
Etichetta reads the output layout of the ONNX model and picks the right decoder by itself. These are the layouts it understands (all tested except YOLOv7, which shares the YOLOv5 layout):

| Model | Output |
|---|---|
| YOLOv8, YOLO11, YOLOv10, YOLO26 (default Ultralytics export) | `[1, 4+classes, N]` |
| YOLOv5 (from the original yolov5 repo), YOLOv7 | `[1, N, 5+classes]` |
| YOLOv10 and YOLO26 end-to-end (`nms=False`), any Ultralytics export with `nms=True` | `[1, N, 6]` |
| RT-DETR (Ultralytics) | `[1, N, 6]` |

The labels file must have one line for each class the model knows, in the same order: Etichetta uses its length to recognize the layout.

To export a model with [Ultralytics](https://docs.ultralytics.com/modes/export/):

```bash
yolo export model=yolo11s.pt format=onnx
```

## GPU acceleration
Etichetta runs the model on the GPU through WebGPU, which uses Vulkan on Linux, Direct3D 12 on Windows and Metal on macOS: it works with AMD, Intel and NVIDIA cards, no extra drivers needed. If a CUDA build of onnxruntime is installed, CUDA is used instead.

`Use GPU acceleration` in `Edit > AI settings...` is on by default and Etichetta remembers your choice. If the GPU can't be used, the model runs on CPU.

If FFmpeg is installed, pictures are scaled for the model with its `libswscale`, about twice as fast; otherwise with GdkPixbuf. The bottom of `AI settings...` shows what is in use.

## Train your own model
Once you have annotated some images, you can train a model on them and use it to annotate the rest. `tools/train.py` does everything starting from your Etichetta project folder: it splits the images in training and validation sets, trains a YOLO model with [Ultralytics](https://docs.ultralytics.com) and exports it to ONNX.

```bash
pip install ultralytics
python tools/train.py path/to/my-project
```

At the end the script prints where `model.onnx` and `labels.txt` are (inside `my-project/models/`): load them from `Edit > AI settings...`.

Useful options (`--help` lists them all):

| Option | Default | |
|---|---|---|
| `--model` | `yolo11n.pt` | starting model: `yolo11s.pt`, `yolo11m.pt`... are more accurate and slower. You can also pass a `.pt` you trained before |
| `--epochs` | `100` | training epochs. Training stops earlier if it doesn't improve for `--patience` epochs (`30`). With less than 10 validation images there is no early stop and the last epoch is kept: their score is too random to pick the best one |
| `--imgsz` | `640` | image size used by the model |
| `--batch` | `16` | lower it if you run out of memory. With few images it is lowered by itself, so the model is updated several times per epoch |
| `--device` | GPU if available | `cpu`, `0` for the first GPU, `mps` on Apple Silicon |
| `--val` | `0.2` | fraction of images used for validation |
| `--include-unlabeled` | off | use images without annotations as background |

Training on a CPU works but is slow: with a GPU it is many times faster.
