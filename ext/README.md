Create an `onnx` folder here, and unpack the appropriate version of onnxruntime that you can download from this address: https://github.com/microsoft/onnxruntime/releases.

The result should be like this:

```
etichetta
 └─ext
    ├─README.md
    └─onnx (not onnxruntime-xx-yy)
       ├─include
       └─lib
```

On windows, unpack also the gtk-bundle.zip in this directory too:

```
etichetta
 └─ext
    ├─README.md
    ├─onnx (not onnxruntime-xx-yy)
    |   ├─include
    |   └─lib
    └─gtk
       ├─bin
       ├─etc
       ├─lib
       └─share
```