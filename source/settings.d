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

module settings;

import std.file, std.path, std.string, std.algorithm, std.array;
import std.logger : warning;

// User preferences, saved as key=value lines in the user config dir
// (~/.config/etichetta/settings.ini, %LOCALAPPDATA%\etichetta\settings.ini, ...)
struct Settings
{
   static:

   private string[string] values;
   private bool loaded = false;

   string get(string key, string defaultValue)
   {
      load();
      return values.get(key, defaultValue);
   }

   void set(string key, string value)
   {
      load();
      values[key] = value;

      try
      {
         mkdirRecurse(dirName(file));
         std.file.write(file, values.byKeyValue.map!(kv => kv.key ~ "=" ~ kv.value ~ "\n").join);
      }
      catch (Exception e) { warning("Can't save settings: ", e.msg); }
   }

   private string file()
   {
      import glib.Util : Util;
      return buildPath(Util.getUserConfigDir(), "etichetta", "settings.ini");
   }

   private void load()
   {
      if (loaded) return;
      loaded = true;

      if (!exists(file)) return;

      try
      {
         foreach (line; readText(file).splitLines)
         {
            auto pos = line.indexOf('=');
            if (pos > 0) values[line[0 .. pos].strip] = line[pos + 1 .. $].strip;
         }
      }
      catch (Exception e) { warning("Can't read settings: ", e.msg); }
   }
}
