#!/usr/bin/env dub
/+ dub.sdl:
    name "unpacker"
+/

import std.file : exists, read, write, mkdirRecurse, isDir, thisExePath, chdir;
import std.zip;
import std.path : buildPath, dirName;
import std.algorithm : endsWith;

void main()
{
   // Move inside the deployment dir
   chdir(dirName(thisExePath));

   // Extract file "window-redist" inside "windows" folder if not already extracted
   auto canary = buildPath("windows", "bin", "libgtk-3-0.dll");

   if (exists(canary))
      return;

   auto zip = new ZipArchive(read("windows-redist.zip"));

   foreach (string name, ArchiveMember am; zip.directory)
   {
      auto dest = buildPath("windows",name);
      auto dir = dirName(dest);

      if (dest.endsWith("/") || dest.endsWith("\\"))
      {
         mkdirRecurse(dir);
         continue;
      }
      else if (!exists(dir)) mkdirRecurse(dir);

      write(dest, am.expandedData);
   }
}