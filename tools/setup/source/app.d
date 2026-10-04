module setup;

import std;

// onnxruntime and its WebGPU plugin (GPU acceleration through Vulkan, Direct3D 12 or Metal)
immutable ORT_VERSION = "1.30.0";
immutable WEBGPU_WHEEL_LINUX = "https://files.pythonhosted.org/packages/c1/96/2a18a45079250afcd825687aef2895de266d5abc1cff9f52d2dede7598f2/onnxruntime_ep_webgpu-0.4.0-py3-none-manylinux_2_28_x86_64.whl";
immutable WEBGPU_WHEEL_WINDOWS = "https://files.pythonhosted.org/packages/d7/a4/c98a9e9433b3eeb576977b26c5c1cd0364f15ba9d198bb16101e7563ab06/onnxruntime_ep_webgpu-0.4.0-py3-none-win_amd64.whl";

void main()
{
   // Move inside the deployment dir
   chdir(buildPath(dirName(thisExePath), "..", ".."));

   try { rmdirRecurse("ext/onnx"); } catch (Exception e) { }
   try { rmdirRecurse("output/bin"); } catch (Exception e) { }

   string onnxruntime;

   version(Windows)
   {
      // Extract file "window-redist" inside "windows" folder if not already extracted
      auto canary = buildPath("output", "bin", "libgtk-3-0.dll");
      if (!exists(canary))
      {
         info(" * Unzipping GTK+ runtimes...");

         auto zip = new ZipArchive(read("ext/gtk-runtime-windows.zip"));

         foreach (string name, ArchiveMember am; zip.directory)
         {
            auto dest = buildPath("output", name);
            auto dir = dirName(dest);

            if (dest.endsWith("/") || dest.endsWith("\\"))
            {
               mkdirRecurse(dir);
               continue;
            }
            else if (!exists(dir)) mkdirRecurse(dir);

            std.file.write(dest, zip.expand(am));
         }
      }

      onnxruntime = "https://github.com/microsoft/onnxruntime/releases/download/v" ~ ORT_VERSION ~ "/onnxruntime-win-x64-" ~ ORT_VERSION ~ ".zip";
   }
   else onnxruntime = "https://github.com/microsoft/onnxruntime/releases/download/v" ~ ORT_VERSION ~ "/onnxruntime-linux-x64-" ~ ORT_VERSION ~ ".tgz";

   info(" * Downloading onnx");
   auto tmpDownloadPath = buildPath(tempDir, "etichetta-deps-onnx");
   download(onnxruntime, tmpDownloadPath);

   info(" * Unpacking onnx");

   version(Windows)
   {
      auto zip = new ZipArchive(read(tmpDownloadPath));

      foreach (string name, ArchiveMember am; zip.directory)
      {

         auto dest = buildPath("ext", name).replace("onnxruntime-win-x64-" ~ ORT_VERSION, "onnx");
         auto dir = dirName(dest);

         if (dest.endsWith("/") || dest.endsWith("\\"))
         {
            mkdirRecurse(dir);
            continue;
         }
         else if (!exists(dir)) mkdirRecurse(dir);
         std.file.write(dest, zip.expand(am));

         if (name.endsWith(".dll"))
            std.file.write(buildPath("output", "bin", baseName(name)), zip.expand(am));
      }

      installWebGPU(WEBGPU_WHEEL_WINDOWS, [buildPath("ext", "onnx", "lib"), buildPath("output", "bin")]);
   }
   else
   {
      executeShell("tar xf " ~ tmpDownloadPath ~ " -C ext/ && mv ext/onnx* ext/onnx" );
      installWebGPU(WEBGPU_WHEEL_LINUX, [buildPath("ext", "onnx", "lib")]);
      info(" * Installing runtime");
      executeShell("sudo cp ext/onnx/lib/libonnxruntime_* /usr/local/lib ; sudo cp ext/onnx/lib/libonnxruntime.so.1.* /usr/local/lib ; sudo ldconfig");
   }

   info("DONE!");


}

// The WebGPU plugin is published only as a Python wheel (a zip file): extract its libraries
void installWebGPU(string url, string[] destinations)
{
   info(" * Downloading WebGPU plugin");
   auto tmp = buildPath(tempDir, "etichetta-deps-webgpu.whl");
   download(url, tmp);

   auto zip = new ZipArchive(read(tmp));

   foreach (string name, ArchiveMember am; zip.directory)
   {
      if (!name.startsWith("onnxruntime_ep_webgpu/") || !(name.endsWith(".so") || name.endsWith(".dll") || name.endsWith(".dylib")))
         continue;

      foreach (dest; destinations)
      {
         mkdirRecurse(dest);
         std.file.write(buildPath(dest, baseName(name)), zip.expand(am));
      }
   }
}
