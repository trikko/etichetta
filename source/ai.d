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

import dcv.core;

import mir.ndslice, mir.rc;
import mir.appender;

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
         hasAI = true;
      }
      else warning("Can't load onnx libraries");

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

   }

   void unload()
   {
      // Release resourece from previous session
      if (session !is null) ort.ReleaseSession(session);
      if (memory_info !is null) ort.ReleaseMemoryInfo(memory_info);

      labelsFile = "";
      modelFile = "";

      labels = null;
      labelsMap = null;
   }

   bool load(string file, string labels, string provider="CPU")
   {
      assert(hasAI);
      modelFile = "";

      import std.string : toStringz;

      OrtSessionOptions* session_options;
      bool sessionCreated = false;

      // Release resourece from previous session
      if (session !is null) ort.ReleaseSession(session);
      if (memory_info !is null) ort.ReleaseMemoryInfo(memory_info);

      // Try loading the model
      try
      {
         ort.CreateSessionOptions(&session_options).validate();
         scope(exit) ort.ReleaseSessionOptions(session_options);

         ort.SetIntraOpNumThreads(session_options, 4);
         ort.SetSessionLogSeverityLevel(session_options, 4);
         ort.SetSessionGraphOptimizationLevel(session_options, GraphOptimizationLevel.ORT_ENABLE_ALL);
         ort.SetSessionExecutionMode(session_options, ExecutionMode.ORT_PARALLEL);

         version(linux)    ort.CreateSession(env, file.toStringz, session_options, &session).validate();
         version(windows)  ort.CreateSession(env, cast(ushort*)file.toStringz, session_options, &session).validate();

         sessionCreated = true;

         foreach(available; availableExecProviders)
         {
            if (available[0] == "CPU" || available[0] == provider)
            {
               try { available[1](session_options, 0).validate(); info("PROVIDER SELECTED: ", available[0]); break; }
               catch (Exception e) { warning( "Error loading provider "~ provider[0] ~ ": " ~ e.msg); }
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
         if (sessionCreated) ort.ReleaseSession(session);
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

      import mir.algorithm.iteration : minIndex, maxIndex;
      import picture : Picture;
      assert(session !is null);

      // Pixbuf rows may be padded and may have an alpha channel: copy to a packed RGB buffer
      auto pb = Picture.pixbuf;
      auto pixels = cast(ubyte[])pb.getPixelsWithLength();
      auto channels = pb.getNChannels();
      auto rowstride = pb.getRowstride();

      auto rgb = new ubyte[Picture.width * Picture.height * 3];
      foreach (y; 0 .. Picture.height)
         foreach (x; 0 .. Picture.width)
            rgb[(y * Picture.width + x) * 3 .. (y * Picture.width + x) * 3 + 3] = pixels[y * rowstride + x * channels .. y * rowstride + x * channels + 3];

      Slice!(ubyte*, 3) imSlice = rgb.sliced(Picture.height, Picture.width, 3);

      float scale;
      auto impr = letterBoxAndPreprocess(imSlice, scale);//preprocess(imSlice);

      import core.thread;
      import glib.Idle;

      import picture : Picture;

      scope float* outPtr;
      long[3] outDims;
      size_t numberOfelements;

      infer(impr, outPtr, outDims, numberOfelements);
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
         candidates ~= Rectangle(Point(d.x1/scale/imSlice.shape[1], d.y1/scale/imSlice.shape[0]), Point(d.x2/scale/imSlice.shape[1], d.y2/scale/imSlice.shape[0]), labelsMap[d.cls], d.score);
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

   Slice!(RCI!float, 3) letterBoxAndPreprocess(InputSlice)(InputSlice img, out float scale){
      import std.algorithm.comparison : min;
      import dcv.imgproc : resize;
      static assert(InputSlice.N == 3, "only RGB color images are supported");

      size_t w = inputW;
      size_t h = inputH;

      auto iw = img.shape[1];
      auto ih = img.shape[0];
      scale = min((cast(float)w)/iw, (cast(float)h)/ih);
      auto nw = cast(int)(iw*scale);
      auto nh = cast(int)(ih*scale);

      auto resized = resize(img, [nh, nw]);

      auto boxed_image = rcslice!float([h, w, 3], 128.0f); // allocates
      boxed_image[0..nh, 0..nw, 0..$] = resized[0..nh, 0..nw, 0..$].as!float; // assign values from a lazy iter

      auto image_data_t = (boxed_image / 255.0f).transposed!(2, 0, 1); // lazy

      return image_data_t.rcslice; // allocates from the lazy slice

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


