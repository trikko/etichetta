## Easy way

Just use dub run :setup on main root etichetta directory to setup dependencies.

## Hard way

If you want to use a custom onnx version (eg: with cuda), create an `onnx` folder here, and unpack the appropriate version of onnxruntime that you can download from this address: https://github.com/microsoft/onnxruntime/releases.

The result should be like this:

```
etichetta
 └─ext
    ├─README.md
    └─onnx (not onnxruntime-xx-yy)
       ├─include
       └─lib
```