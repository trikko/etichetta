## Use pretrained AI as assistant
Many people have asked me what the purpose is and how to use AI with labeling. The goal is to simplify the annotation of images by leveraging an AI that has already been pre-trained.

For simplicity, let’s assume we want to create an AI capable of distinguishing my cat (“goose”) from other cats (“non_goose”). Below is a photo of Goose that I manually annotated using a label.

![goose](https://github.com/trikko/etichetta/assets/647157/d06c1b0a-15d9-4700-8cb4-3614d463e5f8)

The standard version of YOLO is able to recognize many different classes from "person" to "toothbrush". Among these is also the “cat” class. Why not take advantage of this potential? By opening the AI settings, I selected the `yolov8s.onnx` model and the `yoloclass.txt` label list. 

![popup](https://github.com/trikko/etichetta/assets/647157/f244c0ab-89f1-4be3-a00d-1cdaab00dd08)

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

![non_goose_1](https://github.com/trikko/etichetta/assets/647157/efde7eb3-e4ea-4cfd-8f7a-fb41e377fb2e)
![non_goose_2](https://github.com/trikko/etichetta/assets/647157/5a9ff296-58bb-4850-b625-1fc74b67793e)

Now all I have to do is simply adjust the proposed frame and press the `0` or `1` key to choose the right class. A nice difference compared to making all the rectangles from scratch!
