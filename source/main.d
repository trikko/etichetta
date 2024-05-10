/*
Copyright (c) 2024 Andrea Fontana

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

module main;

import std.file : write, tempDir, exists, mkdirRecurse, rmdirRecurse;
import std.path : buildPath;
import std.logger : info;

import gtk.Main;

import gui : GUI;
import picture : Picture;
import widgets : Widgets;
import ai : AI;

import common;

int mainImpl(string[] args)
{
	import imports;

	// Write example files to a temp dir
	auto tmpDir = buildPath(tempDir(), "etichetta_example");
	auto tmpImagesDir = buildPath(tmpDir, "images");
	auto tmpLabelsDir = buildPath(tmpDir, "labels");

	try { rmdirRecurse(tmpDir); } catch (Exception e) { }

	if (!exists(tmpDir)) mkdirRecurse(tmpDir);
	if (!exists(tmpImagesDir)) mkdirRecurse(tmpImagesDir);
	if (!exists(tmpLabelsDir)) mkdirRecurse(tmpLabelsDir);

	write(buildPath(tmpDir, "classes.txt"), CLASSES);
	write(buildPath(tmpLabelsDir, "example_01.txt"), LABELS);
	write(buildPath(tmpImagesDir, "example_01.jpg"), EXAMPLES[0]);
	write(buildPath(tmpImagesDir, "example_02.jpg"), EXAMPLES[1]);

	// Delete temp dir on exit
	scope(exit) { rmdirRecurse(tmpDir); info("Example files deleted."); }

	info("Example files written to: ", tmpDir);

	import gtkd.Loader;

	Linker.dumpLoadLibraries();
	Linker.dumpFailedLoads();

	// Initialize the application
	Main.init(args);
	AI.reinit();

	Widgets.reinit();
	GUI.reinit();

	workingDirectory = tmpDir;
	Picture.reinit();

	Main.run();

	return 0;
}

version(Windows)
{
	pragma(lib, "user32");
	pragma(lib, "gdi32");
}

// IGNORED, for now.
version(none)
{
	pragma(lib, "user32");
	pragma(lib, "gdi32");

   // Copy/Pasted from DWiki
   // It calls winmain to avoid terminal popup.
   import core.runtime;
   import core.sys.windows.windows;
	import std.string : toStringz;

   extern (Windows)
   int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
   {
      int result;

		// Windows do not like stderr to be used in gui mode
		import std.logger : LogLevel, globalLogLevel;
		globalLogLevel = LogLevel.off;

      try
      {
         Runtime.initialize();
         result = mainImpl([]);
         Runtime.terminate();
      }
      catch (Throwable e)
      {
         MessageBoxA(null, e.toString().toStringz(), null,  MB_ICONEXCLAMATION);
         result = 0;
      }

      return result;
   }
}

// Other systems.
else int main(string[] args) { return mainImpl(args); }