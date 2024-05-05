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

import std;
import std.digest.crc;

import gtk.Main;

import gui;
import viewport;
import picture;
import common;

private string workingDirectory;

version(Windows)
{
	pragma(lib, "user32")

   // Copy/Pasted from DWiki
   // It calls winmain to avoid terminal popup.
   import core.runtime;
   import core.sys.windows.windows;

   extern (Windows)
   int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
   {
      int result;

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


int mainImpl(string[] args)
{
	import gtk.Settings;
	import gtk.Builder;

	workingDirectory = buildPath(dirName(args[0]), "example");
   Main.init(args);

	initGUI();

	import imports;

	auto tmpDir = buildPath(tempDir(), "etichetta_example");
	auto tmpImagesDir = buildPath(tmpDir, "images");
	auto tmpLabelsDir = buildPath(tmpDir, "labels");

	try { rmdirRecurse(tmpDir); } catch (Exception e) { }

	if (!exists(tmpDir)) mkdirRecurse(tmpDir);
	if (!exists(tmpImagesDir)) mkdirRecurse(tmpImagesDir);
	if (!exists(tmpLabelsDir)) mkdirRecurse(tmpLabelsDir);

	std.file.write(buildPath(tmpDir, "classes.txt"), CLASSES);
	std.file.write(buildPath(tmpLabelsDir, "example_01.txt"), LABELS);
	std.file.write(buildPath(tmpImagesDir, "example_01.jpg"), EXAMPLES[0]);
	std.file.write(buildPath(tmpImagesDir, "example_02.jpg"), EXAMPLES[1]);

	// Delete temp dir on exit
	scope(exit) { rmdirRecurse(tmpDir); }

	loadProject(tmpDir);

	addStatusCallback( (s) { points.length = 0; } );
	Main.run();
	return 0;
}


void loadProject(string dir)
{
	workingDirectory = dir;

	if (!readPicturesDir())
	{
		error("Quitting: no pictures available on ", workingDirectory);
		Main.quit();
		return;
	}

	if (!readLabels())
		warning("No labels.txt or classes.txt found. Labels text will be not available.");
}

bool readLabels()
{
	labels.length = 0;

	string file = buildPath(workingDirectory, "labels.txt");
	if (!exists(file)) file = buildPath(workingDirectory, "classes.txt");

	if (!exists(file))
		return false;

	labels = [""] ~ readText(file).splitter("\n").filter!(a => a.length > 0).map!(x => x.strip).array;
	return true;
}

auto readAnnotations(string picture)
{
	Rectangle[] rects;

	// Get the filename without ext
	auto filename = baseName(picture).stripExtension ~ ".txt";
	auto labels = buildPath(workingDirectory, "labels", filename);

	if (exists(labels))
	{
		foreach(l; File(labels).byLine.filter!(a => a.length > 0))
		{
			auto parts = l.split(" ");
			if (parts.length < 5)
				continue;

			Rectangle r;
			double cx = parts[1].to!double;
			double cy = parts[2].to!double;
			r.p1.x = cx - parts[3].to!double / 2;
			r.p1.y = cy - parts[4].to!double / 2;
			r.p2.x = r.p1.x + parts[3].to!double;
			r.p2.y = r.p1.y + parts[4].to!double;

			r.label = parts[0].to!int;
			rects ~= r;
		}
	}

	return rects;
}

void writeAnnotations(string picture, Rectangle[] rects)
{
	auto filename = baseName(picture).stripExtension ~ ".txt";
	auto labels = buildPath(workingDirectory, "labels", filename);
	auto f = File(labels, "w+");

	info("Saving file (", rects.length, " lines): ", filename);

	foreach(idx, r; rects)
	{
		auto cx = (r.p1.x + r.p2.x) / 2;
		auto cy = (r.p1.y + r.p2.y) / 2;
		auto w = r.p2.x - r.p1.x;
		auto h = r.p2.y - r.p1.y;

		auto line = format("%d %.20f %.20f %.20f %.20f", r.label, cx, cy, w, h);
		f.writeln(line);
	}

	f.close();
}

bool readPicturesDir()
{
	Picture.list.length = 0;

	foreach(f; dirEntries(buildPath(workingDirectory, "images"), SpanMode.shallow))
	{
		auto ext = extension(f).toLower();
		if (ext != ".png" && ext != ".jpg" && ext != ".jpeg")
		{
			warning("Skipping file: ", f);
			continue;
		}
		Picture.list ~= f;
	}

	if (Picture.list.length == 0)
	{
		import gtk.MessageDialog;
		auto error = new MessageDialog(mainWindow, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.CLOSE, "The selected directory does not contain images");
		error.setModal(true);
		error.run();
		return false;
	}

	// Load the first one
	Picture.index = 0;
	Picture.reload();

	ViewPort.invalidated = true;
	status = State.EDITING;
	return true;
}





