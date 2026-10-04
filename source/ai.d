/*
Copyright (c) 2024 Andrea Fontana, Ferhat Kurtulmuş

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
*/

module ai;

import std;
import onnxruntime;
import common;

import gdkpixbuf.Pixbuf : Pixbuf;

import mir.ndslice;

import common : Rectangle, Point;
import glib.Idle;

alias ProviderFunc = extern (C) OrtStatus* function(OrtSessionOptions* options, int device_id);
alias ExecutionProvider = Tuple!(string, ProviderFunc);

struct AI
{
   static:

   bool hasAI = false;
   bool hasModel() { return modelFile.length > 0 && labelsFile.length > 0; };

   string modelFile;
   string labelsFile;
   string[] labels;
   int[int] labelsMap;  // labelsMap[10] => returns the index of the label 10 of YOLO as it is in the picture array.

   size_t inputW;
   size_t inputH;

   double minConfidence;
   double maxOverlapping;

   ExecutionProvider[] availableExecProviders;
   string activeProvider;  // Provider used by the loaded model

   // Output layouts we can decode. nc = number of classes.
   enum OutputFormat
   {
      unknown,
      yolov8,     // [1, 4+nc, N]: cx, cy, w, h, class scores (YOLOv8, YOLOv9, YOLO11, YOLO12)
      yolov8T,    // [1, N, 4+nc]: same, transposed (RT-DETR, coordinates may be normalized)
      yolov5,     // [1, N, 5+nc]: cx, cy, w, h, objectness, class scores (YOLOv5, YOLOv7)
      endToEnd    // [1, N, 6]: x1, y1, x2, y2, score, class (YOLOv10/YOLO26 end-to-end, nms=True exports)
                  //            or normalized cx, cy, w, h, score, class (RT-DETR)
   }

   // A detection in input tensor coordinates (pixels of the letterboxed image)
   struct Detection
   {
      float x1, y1, x2, y2;
      int   cls;
      float score;
   }

   private
   {
      const(char)* inputName;
      const(char)* outputName;

      const(OrtApi)* ort = null;
      OrtEnv* env;
      OrtEpDevice* webgpuDevice;   // GPU used by the WebGPU plugin (Vulkan, Direct3D 12 or Metal)
      OrtSession* session;
      OrtMemoryInfo* memory_info;
      OrtValue*[1] output_tensors;
   }

   void reinit()
   {
      addWorkingDirectoryChangeCallback( (_) {
         modelFile = "";
         labelsFile = "";
         labels = null;
         labelsMap = null;
      });

      auto ortbase = OrtGetApiBase();
      if (ortbase)
      {
         info("Found onnxruntime ", ortbase.GetVersionString().to!string);

         ort = ortbase.GetApi(ORT_API_VERSION);

         // An older library doesn't support the API version we were built with
         if (ort is null)
         {
            warning("onnxruntime is too old, version 1.24 or later is needed");
            return;
         }

         hasAI = true;
      }
      else
      {
         warning("Can't load onnx libraries");
         return;
      }

      ort.CreateEnv(OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR, "etichetta", &env).validate();

      // with a proper linkage you can use hardware accel with different backends

      static immutable executionProvidersNames = ["CUDA", "Tensorrt", "ROCM", "MIGraphX", "Dnnl", "CPU"];

      availableExecProviders = null;

      // Check dynamically for symbols inside the shared library
      // In this way we can load the provider only if it is available
      version(Posix)
      {
         foreach(p; executionProvidersNames)
         {
            import core.sys.posix.dlfcn : dlsym;
            auto provider = p;
            auto func = "OrtSessionOptionsAppendExecutionProvider_" ~ provider;

            if (cast(void*)dlsym(null, func.ptr))
            {
               info("Found ", provider, " provider");
               availableExecProviders ~= ExecutionProvider(provider, cast(ProviderFunc)dlsym(null, func.ptr));
            }
         }
      }
      else version(Windows)
      {
         import core.sys.windows.windows : GetProcAddress, LoadLibraryA;
         auto hModule = LoadLibraryA("onnxruntime.dll");
         if (hModule !is null)
         {
            foreach(p; executionProvidersNames)
            {
               auto provider = p;
               auto func = "OrtSessionOptionsAppendExecutionProvider_" ~ provider;
               auto funcPtr = cast(ProviderFunc) GetProcAddress(hModule, func.ptr);
               if (funcPtr !is null)
               {
                  info("Found ", provider, " provider");
                  availableExecProviders ~= ExecutionProvider(provider, funcPtr);
               }
            }
         }
      }


      registerWebGPU();

      import scaler : Swscale;
      Swscale.load();
   }

   // The WebGPU plugin gives GPU acceleration on any vendor. It's a separate library, loaded if found.
   private void registerWebGPU()
   {
      version(Windows) immutable plugin = "onnxruntime_providers_webgpu.dll";
      else version(OSX) immutable plugin = "libonnxruntime_providers_webgpu.dylib";
      else immutable plugin = "libonnxruntime_providers_webgpu.so";

      auto exeDir = dirName(thisExePath);
      auto candidates = [
         buildPath(exeDir, plugin),                                  // Windows
         buildPath(exeDir, "..", "lib", plugin),                     // AppImage, Flatpak
         buildPath(exeDir, "..", "..", "ext", "onnx", "lib", plugin), // Development build
         buildPath("/usr/local/lib", plugin)                         // Installed by tools/setup
      ];

      auto found = std.algorithm.iteration.filter!(c => exists(c))(candidates);
      if (found.empty)
      {
         info("WebGPU plugin not found");
         return;
      }

      try
      {
         auto path = found.front.absolutePath.buildNormalizedPath;

         version(Windows) ort.RegisterExecutionProviderLibrary(env, "webgpu", cast(Parameters!(typeof(OrtApi.RegisterExecutionProviderLibrary))[2]) path.toUTF16z).validate();
         else ort.RegisterExecutionProviderLibrary(env, "webgpu", path.toStringz).validate();

         OrtEpDevice** devices;
         size_t count;
         ort.GetEpDevices(env, &devices, &count).validate();

         foreach (d; devices[0 .. count])
         {
            if (ort.EpDevice_EpName(d).fromStringz == "WebGpuExecutionProvider")
            {
               webgpuDevice = d;
               break;
            }
         }

         if (webgpuDevice is null)
         {
            info("WebGPU plugin loaded, but no GPU found");
            return;
         }

         // Native GPU providers (CUDA, ...) are usually faster: WebGPU goes right after them
         auto pos = availableExecProviders.countUntil!(p => p[0] == "Dnnl" || p[0] == "CPU");
         if (pos < 0) pos = availableExecProviders.length;
         availableExecProviders = availableExecProviders[0 .. pos] ~ ExecutionProvider("WebGPU", null) ~ availableExecProviders[pos .. $];

         info("Found WebGPU provider");
      }
      catch (Exception e) { warning("Can't load WebGPU plugin: ", e.msg); }
   }

   // GPU providers available, best first (Dnnl is a CPU library)
   string[] gpuProviders()
   {
      import std.algorithm.iteration : map, filter;
      return availableExecProviders.map!(p => p[0]).filter!(n => n != "CPU" && n != "Dnnl").array;
   }

   // Release the current session. Pointers are reset so they can't be released twice.
   private void releaseSession()
   {
      if (session !is null) { ort.ReleaseSession(session); session = null; }
      if (memory_info !is null) { ort.ReleaseMemoryInfo(memory_info); memory_info = null; }
   }

   void unload()
   {
      releaseSession();

      labelsFile = "";
      modelFile = "";

      labels = null;
      labelsMap = null;
   }

   // Load a model. With useGpu, GPU providers are tried in order and CPU is the last resort.
   bool load(string file, string labels, bool useGpu = false)
   {
      assert(hasAI);
      modelFile = "";

      import std.string : toStringz;

      OrtSessionOptions* session_options;

      releaseSession();

      // Try loading the model
      try
      {
         // Execution providers must be added to the options before the session is created.
         // If a provider can't be used (missing drivers, libraries, ...) we try the next one, CPU last.
         foreach (selected; (useGpu ? gpuProviders : []) ~ "CPU")
         {
            ort.CreateSessionOptions(&session_options).validate();
            scope(exit) ort.ReleaseSessionOptions(session_options);

            ort.SetIntraOpNumThreads(session_options, 4);
            ort.SetSessionLogSeverityLevel(session_options, 4);
            ort.SetSessionGraphOptimizationLevel(session_options, GraphOptimizationLevel.ORT_ENABLE_ALL);
            ort.SetSessionExecutionMode(session_options, ExecutionMode.ORT_PARALLEL);

            try
            {
               // CPU is always available, no need to add it
               if (selected != "CPU")
               {
                  auto found = std.algorithm.searching.find!(p => p[0] == selected)(availableExecProviders);
                  if (found.empty) throw new Exception("provider not available");

                  // Plugins are added through their device, the others through their own function
                  if (selected == "WebGPU") ort.SessionOptionsAppendExecutionProvider_V2(session_options, env, &webgpuDevice, 1, null, null, 0).validate();
                  else found.front[1](session_options, 0).validate();
               }

               // ORTCHAR_T is wchar_t on Windows, char elsewhere
               version(Windows) ort.CreateSession(env, cast(Parameters!(typeof(OrtApi.CreateSession))[1]) file.toUTF16z, session_options, &session).validate();
               else ort.CreateSession(env, file.toStringz, session_options, &session).validate();

               info("PROVIDER SELECTED: ", selected);
               activeProvider = selected;
               break;
            }
            catch (Exception e)
            {
               if (selected == "CPU") throw e;
               warning("Can't use provider ", selected, ", trying the next one: ", e.msg);
            }
         }


         size_t num_input_nodes;
         ort.SessionGetInputCount(session, &num_input_nodes).validate();
         ort.CreateCpuMemoryInfo(OrtAllocatorType.OrtArenaAllocator, OrtMemType.OrtMemTypeDefault, &memory_info).validate();

         // Node names change between exporters ("output0", "output", ...): read them from the model
         OrtAllocator* allocator;
         ort.GetAllocatorWithDefaultOptions(&allocator).validate();

         char* name;
         ort.SessionGetInputName(session, 0, allocator, &name).validate();
         inputName = name.fromStringz.idup.toStringz;
         ort.AllocatorFree(allocator, name).validate();

         ort.SessionGetOutputName(session, 0, allocator, &name).validate();
         outputName = name.fromStringz.idup.toStringz;
         ort.AllocatorFree(allocator, name).validate();
      }
      catch (Exception e)
      {
         info("Error loading model: ", e.msg);
         releaseSession();
         return false;
      }

      try {
         import std.algorithm : filter, map;
         labelsFile = labels;
         this.labels = readText(labels).splitter("\n").filter!(a => a.length > 0).map!(x => x.strip).array;
      }
      catch (Exception e)
      {
         warning("Error reading labels file: ", e.msg);
         return false;
      }

      OrtTypeInfo* input_type_info;
      ort.SessionGetInputTypeInfo(session, 0, &input_type_info);

      // Get input node shape
      OrtTensorTypeAndShapeInfo* input_shape_info;
      ort.CastTypeInfoToTensorInfo(input_type_info, &input_shape_info);

      size_t num_dims;
      ort.GetDimensionsCount(input_shape_info, &num_dims);

      if (num_dims != 4)
      {
         warning("Input shape is not 4D");
         return false;
      }

      long[4] input_dims;

      ort.GetDimensions(input_shape_info, input_dims.ptr, num_dims);

      // NCHW. Models exported with dynamic shapes report -1: use the usual YOLO size.
      inputH = input_dims[2] > 0 ? input_dims[2] : 640;
      inputW = input_dims[3] > 0 ? input_dims[3] : 640;

      if (input_dims[1] != 3)
      {
         warning("Only rgb images are supported as input");
         return false;
      }

      debug info("Input shape: ", inputW, "x", inputH);

      modelFile = file;
      return true;
   }

   void boxes()
   {
      assert(hasAI);

      import picture : Picture;
      assert(session !is null);

      float scale;
      auto impr = letterBoxAndPreprocess(Picture.pixbuf, scale);

      import core.thread;
      import glib.Idle;

      import picture : Picture;

      scope float* outPtr;
      long[3] outDims;
      size_t numberOfelements;

      try infer(impr, outPtr, outDims, numberOfelements);
      catch (Exception e)
      {
         // A GPU can fail while running (out of memory, unsupported operation, ...): retry on CPU
         if (activeProvider == "CPU") throw e;
         warning("Inference on ", activeProvider, " failed, switching to CPU: ", e.msg);

         auto model = modelFile, labelsPath = labelsFile;
         if (!load(model, labelsPath, false)) throw e;
         infer(impr, outPtr, outDims, numberOfelements);
      }

      scope Slice!(float*, 3) outSlice = outPtr[0..numberOfelements].sliced(outDims[0], outDims[1], outDims[2]);

      auto format = detectFormat(outSlice, labels.length);

      if (format == OutputFormat.unknown)
      {
         warning("Unsupported model output shape ", outDims, " with ", labels.length, " labels");
         return;
      }

      size_t unknown = 0;
      Rectangle[] candidates;

      foreach (d; decode(outSlice, format, minConfidence))
      {
         // We don't have this class in the gui
         if (d.cls !in labelsMap)
         {
            unknown++;
            continue;
         }

         // only one scale value is enough with a letterbox image.
         candidates ~= Rectangle(Point(d.x1/scale/Picture.width, d.y1/scale/Picture.height), Point(d.x2/scale/Picture.width, d.y2/scale/Picture.height), labelsMap[d.cls], d.score);
      }

      // Non-maximum suppression: best scores first, a box is dropped if it overlaps too much
      // a box with the same label that is already in the picture (drawn by hand or kept before)
      candidates.sort!((a, b) => a.score > b.score);

      foreach (candidate; candidates)
      {
         bool toAdd = true;

         foreach (idx, b; Picture.rects)
         {
            if (b.label != candidate.label || iou(b, candidate) <= maxOverlapping)
               continue;

            // Boxes drawn by hand have score = float.max and are never replaced
            if (b.score < candidate.score)
               Picture.rects[idx] = candidate;

            toAdd = false;
            break;
         }

         if (toAdd)
            Picture.rects ~= candidate;
      }

      return;
   }

   // Intersection over union of two boxes
   double iou(in Rectangle a, in Rectangle b)
   {
      import std.algorithm.comparison : min, max;

      // Corners may be swapped if the box was drawn from bottom-right
      auto ax1 = min(a.p1.x, a.p2.x), ax2 = max(a.p1.x, a.p2.x), ay1 = min(a.p1.y, a.p2.y), ay2 = max(a.p1.y, a.p2.y);
      auto bx1 = min(b.p1.x, b.p2.x), bx2 = max(b.p1.x, b.p2.x), by1 = min(b.p1.y, b.p2.y), by2 = max(b.p1.y, b.p2.y);

      auto w = min(ax2, bx2) - max(ax1, bx1);
      auto h = min(ay2, by2) - max(ay1, by1);

      if (w <= 0 || h <= 0)
         return 0;

      auto intersection = w * h;
      auto areaA = (ax2 - ax1) * (ay2 - ay1);
      auto areaB = (bx2 - bx1) * (by2 - by1);

      return intersection / (areaA + areaB - intersection);
   }

   // Guess the output layout from its shape and the number of classes in the labels file
   OutputFormat detectFormat(S)(S output, size_t nc)
   {
      auto rows = output.shape[1];
      auto cols = output.shape[2];

      // [1, N, 6] with integer class ids in the last column. Checked first: with 1 or 2 classes
      // the shape alone can't tell it from YOLOv5 or a transposed YOLOv8.
      if (cols == 6)
      {
         bool integral = true;
         foreach (i; 0 .. rows)
         {
            auto c = output[0, i, 5];
            if (c != cast(int)c || c < 0 || c >= nc) { integral = false; break; }
         }

         if (integral) return OutputFormat.endToEnd;
      }

      if (rows == 4 + nc && cols != 4 + nc) return OutputFormat.yolov8;
      if (cols == 5 + nc) return OutputFormat.yolov5;
      if (cols == 4 + nc) return OutputFormat.yolov8T;

      // Labels file doesn't match the model: few attributes and many candidates is the YOLOv8 layout,
      // as before. Classes without a label are skipped.
      if (rows > 4 && rows < cols) return OutputFormat.yolov8;

      return OutputFormat.unknown;
   }

   // Extract the detections over the threshold, in input tensor coordinates
   Detection[] decode(S)(S output, OutputFormat format, double threshold)
   {
      import mir.algorithm.iteration : maxIndex;

      Detection[] result;

      Detection fromCenter(float cx, float cy, float w, float h, size_t cls, float score)
      {
         return Detection(cx - 0.5f * w, cy - 0.5f * h, cx + 0.5f * w, cy + 0.5f * h, cast(int)cls, score);
      }

      final switch (format)
      {
         case OutputFormat.unknown:
            break;

         case OutputFormat.yolov8:
            foreach (i; 0 .. output.shape[2])
            {
               auto scores = output[0, 4 .. $, i];
               auto cls = scores.maxIndex[0];
               if (scores[cls] > threshold)
                  result ~= fromCenter(output[0, 0, i], output[0, 1, i], output[0, 2, i], output[0, 3, i], cls, scores[cls]);
            }
            break;

         case OutputFormat.yolov8T:
            // RT-DETR gives coordinates normalized to [0, 1]
            bool normalized = true;
            foreach (i; 0 .. output.shape[1])
               foreach (j; 0 .. 4)
                  if (output[0, i, j] > 1.5f) normalized = false;

            float sx = normalized ? inputW : 1;
            float sy = normalized ? inputH : 1;

            foreach (i; 0 .. output.shape[1])
            {
               auto scores = output[0, i, 4 .. $];
               auto cls = scores.maxIndex[0];
               if (scores[cls] > threshold)
                  result ~= fromCenter(output[0, i, 0] * sx, output[0, i, 1] * sy, output[0, i, 2] * sx, output[0, i, 3] * sy, cls, scores[cls]);
            }
            break;

         case OutputFormat.yolov5:
            foreach (i; 0 .. output.shape[1])
            {
               auto scores = output[0, i, 5 .. $];
               auto cls = scores.maxIndex[0];
               auto score = output[0, i, 4] * scores[cls];   // objectness * class probability
               if (score > threshold)
                  result ~= fromCenter(output[0, i, 0], output[0, i, 1], output[0, i, 2], output[0, i, 3], cls, score);
            }
            break;

         case OutputFormat.endToEnd:
            // YOLO gives corners in pixels, RT-DETR gives center and size normalized to [0, 1]
            bool normalized = true;
            foreach (i; 0 .. output.shape[1])
               foreach (j; 0 .. 4)
                  if (output[0, i, j] > 1.5f) normalized = false;

            foreach (i; 0 .. output.shape[1])
            {
               if (output[0, i, 4] <= threshold) continue;

               if (normalized)
                  result ~= fromCenter(output[0, i, 0] * inputW, output[0, i, 1] * inputH, output[0, i, 2] * inputW, output[0, i, 3] * inputH, cast(size_t)output[0, i, 5], output[0, i, 4]);
               else
                  result ~= Detection(output[0, i, 0], output[0, i, 1], output[0, i, 2], output[0, i, 3], cast(int)output[0, i, 5], output[0, i, 4]);
            }
            break;
      }

      return result;
   }

   private void infer(InputSlice)(auto ref InputSlice impr, out float* outPtr, out long[3] outDims, out size_t ecount0)
   {
      import core.stdc.stdlib : malloc, free;

      if(output_tensors[0] !is null){
         ort.ReleaseValue(output_tensors[0]);
         output_tensors[0] = null;
      }

      OrtValue*[1] input_tensor;

      long[4] in1 = [1, 3, inputH, inputW];

      size_t input_tensor_size = inputH * inputW * 3;

      ort.CreateTensorWithDataAsOrtValue
      (
         memory_info, cast(void*)impr.ptr,
         input_tensor_size * float.sizeof, in1.ptr, 4,
         ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
         &input_tensor[0]
      ).validate();

      scope (exit) ort.ReleaseValue(input_tensor[0]);

      int is_tensor;
      ort.IsTensor(input_tensor[0], &is_tensor).validate();
      assert(is_tensor);

      ort.Run
      (
         session, null,
         &inputName, input_tensor.ptr, 1,
         &outputName, 1, output_tensors.ptr
      ).validate();

      ort.GetTensorMutableData(output_tensors[0], cast(void**)&outPtr).validate();
      ort.IsTensor(output_tensors[0], &is_tensor).validate();
      assert(is_tensor);

      OrtTensorTypeAndShapeInfo* sh0;

      ort.GetTensorTypeAndShape(output_tensors[0], &sh0).validate();
      scope(exit) ort.ReleaseTensorTypeAndShapeInfo(sh0);

      ort.GetTensorShapeElementCount(sh0, &ecount0).validate();

      size_t dcount0;
      ort.GetDimensionsCount(sh0, &dcount0).validate();

      long[] dims0 = (cast(long*)malloc(dcount0 * long.sizeof))[0..dcount0];
      ort.GetDimensions(sh0, dims0.ptr, dcount0).validate();
      outDims = [dims0[0], dims0[1], dims0[2]];
      free(cast(void*)dims0.ptr);
   }

   // Scale the picture to fit the model input, pad with gray and convert to a CHW float tensor
   float[] letterBoxAndPreprocess(Pixbuf img, out float scale)
   {
      import std.algorithm.comparison : min, max;
      import gdkpixbuf.c.types : GdkInterpType;

      size_t w = inputW;
      size_t h = inputH;

      auto iw = img.getWidth();
      auto ih = img.getHeight();
      scale = min((cast(float)w)/iw, (cast(float)h)/ih);
      // At least one pixel, even for very thin pictures
      auto nw = max(1, cast(int)(iw*scale));
      auto nh = max(1, cast(int)(ih*scale));

      auto tensor = new float[3 * h * w];
      tensor[] = 128.0f / 255.0f;

      // FFmpeg's libswscale (if installed) scales and writes the floats in one pass
      import scaler : Swscale;
      auto src = cast(ubyte[])img.getPixelsWithLength();
      if (Swscale.scaleToPlanarFloat(src.ptr, iw, ih, img.getRowstride(), img.getNChannels(), nw, nh,
            tensor.ptr, tensor.ptr + h * w, tensor.ptr + 2 * h * w, cast(int)w))
         return tensor;

      // GdkPixbuf does the resize (in C, way faster than doing it here)
      auto resized = img.scaleSimple(nw, nh, GdkInterpType.BILINEAR);
      scope(exit) resized.unref();

      // Rows may be padded and there may be an alpha channel
      auto pixels = cast(ubyte[])resized.getPixelsWithLength();
      auto channels = resized.getNChannels();
      auto rowstride = resized.getRowstride();

      foreach (y; 0 .. nh)
      {
         auto row = pixels[y * rowstride .. $];
         foreach (x; 0 .. nw)
         {
            auto p = row[x * channels .. x * channels + 3];
            tensor[0 * h * w + y * w + x] = p[0] / 255.0f;
            tensor[1 * h * w + y * w + x] = p[1] / 255.0f;
            tensor[2 * h * w + y * w + x] = p[2] / 255.0f;
         }
      }

      return tensor;
   }

}

private void validate(OrtStatus* status)
{
   if (status)
   {

      auto msg = AI.ort.GetErrorMessage(status).to!string;
      AI.ort.ReleaseStatus(status);
      throw new Exception(msg);
   }
}


