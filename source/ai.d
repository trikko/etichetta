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

   private
   {
      static immutable const(char)*[1] input_node_names = ["images".ptr];
      static immutable const(char)*[1] output_node_names = ["output0"];

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

      inputH = input_dims[3];
      inputW = input_dims[2];

      if (input_dims[1] != 3)
      {
         warning("Only rgb images are supported as input");
         return false;
      }

      debug info("Input shape: ", inputW, "x", inputH);

      modelFile = file;
      return true;
   }

   Rectangle[] boxes(string file)
   {
      assert(hasAI);

      import mir.algorithm.iteration : minIndex, maxIndex;
      import picture : Picture;
      assert(session !is null);

      Slice!(ubyte*, 3) imSlice = (cast(ubyte[])Picture.pixbuf.getPixelsWithLength()).sliced(Picture.height, Picture.width, 3);

      float scale;
      auto impr = letterBoxAndPreprocess(imSlice, scale);//preprocess(imSlice);

      scope float* outPtr;
      long[3] outDims;
      size_t numberOfelements;

      infer(impr, outPtr, outDims, numberOfelements);

      scope Slice!(float*, 3) outSlice = outPtr[0..numberOfelements].sliced(outDims[0], outDims[1], outDims[2]);

      import picture : Picture;
      Rectangle[] boxes = Picture.rects.dup;

      size_t unknown = 0;

      foreach (i; 0 .. outSlice.shape[2]) {
         auto classProbabilities = outSlice[0, 4 .. $, i];

         auto maxClassLoc = classProbabilities.maxIndex[0];
         auto maxScore = classProbabilities[maxClassLoc];

         if (maxScore > minConfidence) {

            // We don't have this class in the gui
            if (cast(int)maxClassLoc !in labelsMap)
            {
               unknown++;
               continue;
            }

            // Object detected with confidence higher than the threshold
            // Extract bounding box coordinates
            auto width = outSlice[0, 2, i]  ;
            auto height = outSlice[0, 3, i] ;

            auto x = outSlice[0, 0, i] - 0.5f * width;
            auto y = outSlice[0, 1, i] - 0.5f * height;

            // only one scale value is enough with a letterbox image.
            auto candidate = Rectangle(Point(x/scale/imSlice.shape[1], y/scale/imSlice.shape[0]), Point((x+width)/scale/imSlice.shape[1], (y+height)/scale/imSlice.shape[0]), labelsMap[cast(int)maxClassLoc], maxScore);

            bool toAdd = true;

            string matches;
            foreach(idx, b; boxes)
            {
               // Check if candidate and b intersect

               bool intersect = (
                  !(candidate.p2.x < b.p1.x || candidate.p1.x > b.p2.x) &&
                  !(candidate.p2.y < b.p1.y || candidate.p1.y > b.p2.y)
               );

               if (!intersect)
                  continue;

               auto allx = [b.p1.x, b.p2.x, candidate.p1.x, candidate.p2.x].sort;
               auto ally = [b.p1.y, b.p2.y, candidate.p1.y, candidate.p2.y].sort;

               auto leftX = allx[1] - allx[0];
               auto intersectX = allx[2] - allx[1];
               auto rightX = allx[3] - allx[2];

               auto leftY = ally[1] - ally[0];
               auto intersectY = ally[2] - ally[1];
               auto rightY = ally[3] - ally[2];

               // Are they the same box?
               if (
                  b.label == candidate.label &&
                  leftX/intersectX < 1-maxOverlapping && rightX/intersectX < 1-maxOverlapping &&
                  leftY/intersectY <1-maxOverlapping && rightY/intersectY < 1-maxOverlapping
               )
               {
                  if(b.score < candidate.score)
                        boxes[idx] = candidate;

                  toAdd = false;
                  break;
               }

            }

            if (toAdd)
               boxes ~= candidate;

         }
      }

      return boxes[Picture.rects.length..$];
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
         ["images".ptr].ptr, input_tensor.ptr, 1,
         ["output0".ptr].ptr, 1, output_tensors.ptr
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


