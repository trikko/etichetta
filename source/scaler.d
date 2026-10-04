/*
Copyright (c) 2026 Andrea Fontana

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

module scaler;

import std.format : format;
import std.logger : info;

// FFmpeg's libswscale, loaded at runtime if installed. It scales the picture and writes the
// float tensor in one pass, about twice as fast as GdkPixbuf. Without it we use GdkPixbuf.
struct Swscale
{
   static:

   bool available() { return sws_scale !is null; }
   string versionString;   // e.g. "9.1.102"

   // Scale a RGB/RGBA picture into planar float RGB (0..1), written at the top-left of each plane.
   // planes: R, G, B planes of the tensor, each planeStride floats per row.
   bool scaleToPlanarFloat(const(ubyte)* src, int srcW, int srcH, int srcStride, int channels,
                           int dstW, int dstH, float* r, float* g, float* b, int planeStride)
   {
      if (!available) return false;

      // The context depends only on sizes and formats: keep it while they don't change
      auto key = [srcW, srcH, channels, dstW, dstH];
      if (key != contextKey)
      {
         if (context !is null) sws_freeContext(context);
         context = sws_getContext(srcW, srcH, channels == 4 ? fmtRGBA : fmtRGB24, dstW, dstH, fmtGBRPF32, SWS_AREA, null, null, null);
         contextKey = key;
      }

      if (context is null) return false;

      const(ubyte)*[4] srcPlanes = [src, null, null, null];
      int[4] srcStrides = [srcStride, 0, 0, 0];

      // GBRP order: planes are G, B, R
      ubyte*[4] dstPlanes = [cast(ubyte*)g, cast(ubyte*)b, cast(ubyte*)r, null];
      int[4] dstStrides = [planeStride * cast(int)float.sizeof, planeStride * cast(int)float.sizeof, planeStride * cast(int)float.sizeof, 0];

      return sws_scale(context, srcPlanes.ptr, srcStrides.ptr, 0, srcH, dstPlanes.ptr, dstStrides.ptr) == dstH;
   }

   void load()
   {
      // Library names change with FFmpeg major versions: try the matching pairs (swscale N needs
      // avutil N+51), newest first. Mixing versions could give wrong pixel format ids.
      version(Windows)
      {
         import core.sys.windows.windows : LoadLibraryA, GetProcAddress;
         alias swName = (int v) => format("swscale-%d.dll", v);
         alias avName = (int v) => format("avutil-%d.dll", v + 51);
         alias open = (string n) => cast(void*)LoadLibraryA((n ~ "\0").ptr);
         alias sym = (void* h, string s) => cast(void*)GetProcAddress(h, (s ~ "\0").ptr);
      }
      else
      {
         import core.sys.posix.dlfcn : dlopen, dlsym, RTLD_NOW;
         version(OSX)
         {
            alias swName = (int v) => format("libswscale.%d.dylib", v);
            alias avName = (int v) => format("libavutil.%d.dylib", v + 51);
         }
         else
         {
            alias swName = (int v) => format("libswscale.so.%d", v);
            alias avName = (int v) => format("libavutil.so.%d", v + 51);
         }
         alias open = (string n) => dlopen((n ~ "\0").ptr, RTLD_NOW);
         alias sym = (void* h, string s) => dlsym(h, (s ~ "\0").ptr);
      }

      void* sw, av;
      foreach_reverse (v; 5 .. 13)
      {
         sw = open(swName(v));
         if (sw is null) continue;

         av = open(avName(v));
         if (av !is null) break;
      }

      if (sw is null || av is null)
      {
         info("FFmpeg libswscale not found, scaling with GdkPixbuf");
         return;
      }

      auto getContext = cast(typeof(sws_getContext)) sym(sw, "sws_getContext");
      auto scale = cast(typeof(sws_scale)) sym(sw, "sws_scale");
      auto freeContext = cast(typeof(sws_freeContext)) sym(sw, "sws_freeContext");
      auto isSupportedOutput = cast(int function(int) nothrow @nogc) sym(sw, "sws_isSupportedOutput");
      auto swVersion = cast(uint function() nothrow @nogc) sym(sw, "swscale_version");
      auto pixFmt = cast(int function(const(char)*) nothrow @nogc) sym(av, "av_get_pix_fmt");

      if (getContext is null || scale is null || freeContext is null || isSupportedOutput is null || swVersion is null || pixFmt is null)
      {
         info("FFmpeg libswscale is incomplete, scaling with GdkPixbuf");
         return;
      }

      // Pixel format ids may change between versions: ask them by name
      fmtRGB24 = pixFmt("rgb24");
      fmtRGBA = pixFmt("rgba");
      fmtGBRPF32 = pixFmt("gbrpf32le");

      if (fmtRGB24 < 0 || fmtRGBA < 0 || fmtGBRPF32 < 0 || !isSupportedOutput(fmtGBRPF32))
      {
         info("FFmpeg libswscale can't write float pictures, scaling with GdkPixbuf");
         return;
      }

      auto v = swVersion();
      versionString = format("%d.%d.%d", v >> 16, (v >> 8) & 0xff, v & 0xff);

      sws_getContext = getContext;
      sws_freeContext = freeContext;
      sws_scale = scale;

      info("Scaling with FFmpeg libswscale ", versionString);
   }

   private
   {
      enum SWS_AREA = 32;   // Area averaging: right choice when shrinking a lot

      struct SwsContext;
      extern(C) nothrow @nogc
      {
         __gshared SwsContext* function(int, int, int, int, int, int, int, void*, void*, const(double)*) sws_getContext;
         __gshared int function(SwsContext*, const(ubyte*)*, const(int)*, int, int, const(ubyte*)*, const(int)*) sws_scale;
         __gshared void function(SwsContext*) sws_freeContext;
      }

      int fmtRGB24, fmtRGBA, fmtGBRPF32;

      SwsContext* context;
      int[] contextKey;
   }
}
