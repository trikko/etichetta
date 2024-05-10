module setup;

import std;

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

      onnxruntime = "https://github.com/microsoft/onnxruntime/releases/download/v1.17.3/onnxruntime-win-x64-1.17.3.zip";
   }
   else onnxruntime = "https://github.com/microsoft/onnxruntime/releases/download/v1.17.3/onnxruntime-linux-x64-1.17.3.tgz";

   info(" * Downloading onnx");
   auto tmpDownloadPath = buildPath(tempDir, "etichetta-deps-onnx");
   download(onnxruntime, tmpDownloadPath);

   info(" * Unpacking onnx");

   version(Windows)
   {
      auto zip = new ZipArchive(read(tmpDownloadPath));

      foreach (string name, ArchiveMember am; zip.directory)
      {

         auto dest = buildPath("ext", name).replace("onnxruntime-win-x64-1.17.3", "onnx");
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

   }
   else
   {
      executeShell("tar xf " ~ tmpDownloadPath ~ " -C ext/ && mv ext/onnx* ext/onnx" );
      info(" * Installing runtime");
      executeShell("sudo cp ext/onnx/lib/libonnxruntime_* /usr/local/lib ; sudo cp ext/onnx/lib/libonnxruntime.so.1.* /usr/local/lib ; sudo ldconfig");
   }

   info("DONE!");


}
