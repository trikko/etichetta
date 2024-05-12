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

module picture;

import std;
import common;
import widgets;
import gui : GUI;

import gdk.Pixbuf;

struct Picture
{

	struct ViewPort
	{
		static:

		Pixbuf	pixbuf;

		Point		roiTopLeft;			// In the picture coords space
		Point		roiBottomRight;	// In the picture coords space

		int		width;
		int		height;

		double	scale = 1.0;			// Scale factor: 2.0 means that the image is zoomed 2x.
		bool		invalidated = true;	// If true, the rendered pixbuf must be regenerated

		// Center the image in the viewport if image is smaller than the viewport
		int		offsetX = 0;
		int 		offsetY = 0;

		// Create a pixbuf from the current one. The pixbuf is cropped and scaled to fit the viewport
		Pixbuf view()
		{
			assert(Picture.pixbuf !is null);

			// Cache the result
			static Pixbuf result;

			if (!invalidated)
				return result;


			if (pixbuf !is null)
				pixbuf.unref();

			// Calculate the crop area and expand it to fit the viewport proportions
			double minCropW = roiBottomRight.x - roiTopLeft.x;
			double minCropH = roiBottomRight.y - roiTopLeft.y;

			double vpScale = 1.0 * width / height;

			double adjustedCropW = minCropW;
			double adjustedCropH = minCropW / vpScale;

			if (adjustedCropH < minCropH)
			{
				adjustedCropH = minCropH;
				adjustedCropW = minCropH * vpScale;
			}

			// Expand the crop area to fit the right proportions
			roiBottomRight.x += (adjustedCropW - minCropW) / 2;
			roiBottomRight.y += (adjustedCropH - minCropH) / 2;

			roiTopLeft.x -= (adjustedCropW - minCropW) / 2;
			roiTopLeft.y -= (adjustedCropH - minCropH) / 2;

			// Check bounds
			roiTopLeft.x = max(roiTopLeft.x, 0);
			roiTopLeft.y = max(roiTopLeft.y, 0);

			roiBottomRight.x = min(roiBottomRight.x, Picture.width);
			roiBottomRight.y = min(roiBottomRight.y, Picture.height);

			// Crop the original picture
			Pixbuf cropped = Picture.pixbuf.newSubpixbuf(
				cast(int)roiTopLeft.x,
				cast(int)roiTopLeft.y,
				cast(int)(roiBottomRight.x - roiTopLeft.x),
				cast(int)(roiBottomRight.y - roiTopLeft.y)
			);

			// Scale cropped to fit the viewport
			double scaledW = cast(double)(cropped.getWidth) / width;
			double scaledH = cast(double)(cropped.getHeight) / height;

			scale = 1.0 / max(scaledW, scaledH);

			// Cache the result. If it's an upscale, use bilinear interpolation, otherwise use nearest. We want to see the pixels!
			result = cropped.scaleSimple(
				cast(int)(cropped.getWidth * scale),
				cast(int)(cropped.getHeight * scale),
				scale < 1 ? InterpType.BILINEAR : InterpType.NEAREST
			);

			offsetX = (width - result.getWidth) / 2;
			offsetY = (height - result.getHeight) / 2;

			invalidated = false;
			return result;
		}
	}

	static:

   string[] list;

	long 		index	= 0;
	int 		width;
	int 		height;
	Pixbuf 	pixbuf;

	Rectangle[] rects;
	Rectangle[][] history; // Track the history of the annotations

	size_t historyIndex = 0;

	string current() { return list[index]; }

	void historyBack()
	{
		if (historyIndex == 0)
			return;

		historyIndex--;
		rects = history[historyIndex].dup;

		GUI.updateHistoryMenu();
	}

	void historyForward()
	{
		if (historyIndex == history.length - 1)
			return;

		historyIndex++;
		rects = history[historyIndex].dup;

		GUI.updateHistoryMenu();
	}

   void historyCommit()
	{
		// Remove the future
		history.length = historyIndex + 1;

		// Add the new state
		history ~= rects.dup;
		historyIndex++;

		GUI.updateHistoryMenu();
	}


	void nextRect()
	{
		if (rects.length < 2) return;
		rects = rects[1 .. $] ~ rects[0];
	}

	void prevRect()
	{
		if (rects.length < 2) return;
		rects = rects[$-1 .. $] ~ rects[0 .. $-1];
	}

	void cycle(bool forward, bool toAnnotate = false)
	{
		assert(list.length > 0);

		int delta = forward ? 1 : -1;

		Picture.ViewPort.invalidated = true;
		long curIndex = index;

		while(true)
		{
			index += delta;

			if (index < 0) index = list.length - 1;
			else if (index >= list.length) index = 0;

			if (toAnnotate)
				readAnnotations();

			if (!toAnnotate || Picture.rects.length == 0)
			{
				loadCurrent();
				break;
			}

			if (index == curIndex)
				break;
		}
	}

	void next(bool toAnnotate = false) { cycle(true, toAnnotate); }
	void prev(bool toAnnotate = false) { cycle(false, toAnnotate); }

	void loadCurrent()
	{
		assert(list.length > 0);

		if (pixbuf !is null)
			pixbuf.unref();

		pixbuf = new Pixbuf(current);
		width = pixbuf.getWidth;
		height = pixbuf.getHeight;

		readAnnotations();

		if (Picture.ViewPort.roiTopLeft.x > Picture.width) Picture.ViewPort.roiTopLeft.x = 0;
		if (Picture.ViewPort.roiTopLeft.y > Picture.height) Picture.ViewPort.roiTopLeft.y = 0;

		if (Picture.ViewPort.roiBottomRight.x > Picture.width) Picture.ViewPort.roiBottomRight.x = Picture.width;
		if (Picture.ViewPort.roiBottomRight.y > Picture.height) Picture.ViewPort.roiBottomRight.y = Picture.height;

		Picture.ViewPort.invalidated = true;

		// Check if mnuZoomOnExit is checked
		if (!mnuZoomOnExit.getActive)
			GUI.resetZoom();

		status = State.EDITING;
		canvas.queueDraw();
	}

	void readAnnotations()
	{
		// Clear rects
		rects.length = 0;

		// Get the filename without ext
		auto filename = baseName(current).stripExtension ~ ".txt";
		auto labels = buildPath(workingDirectory, "labels", filename);

		if (exists(labels))
		{
			foreach(l; File(labels).byLine.filter!(a => a.length > 0))
			{
				auto parts = l.chomp.split(" ");
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

		history = [rects.dup];
		historyIndex = 0;
		GUI.updateHistoryMenu();
	}

	void writeAnnotations()
	{
		auto filename = baseName(current).stripExtension ~ ".txt";
		auto labels = buildPath(workingDirectory, "labels", filename);
		auto f = File(labels, "w+");

		info("Saving file (", rects.length, " lines): ", filename);

		foreach(idx, r; rects)
		{
			auto cx = (r.p1.x + r.p2.x) / 2;
			auto cy = (r.p1.y + r.p2.y) / 2;
			auto w = r.p2.x - r.p1.x;
			auto h = r.p2.y - r.p1.y;

			auto line = format("%d %.6f %.6 %.6f %.6f", r.label, cx, cy, w, h);
			f.writeln(line);
		}

		f.close();

		historyCommit();
	}

	bool readPictures()
	{
		list.length = 0;

		foreach(f; dirEntries(buildPath(workingDirectory, "images"), SpanMode.shallow))
		{
			auto ext = extension(f).toLower();
			if (ext != ".png" && ext != ".jpg" && ext != ".jpeg")
			{
				warning("Skipping file: ", f);
				continue;
			}
			list ~= f;
		}

		// Load the first one
		index = 0;
		loadCurrent();

		Picture.ViewPort.invalidated = true;
		status = State.EDITING;
		return true;
	}

	void reinit()
	{
		tryLoadPicture();
		addWorkingDirectoryChangeCallback( (s) { tryLoadPicture(); } );
	}

	private void tryLoadPicture()
	{
		import gtk.Main;

		if (!readPictures())
		{
			error("Quitting: no pictures available on ", workingDirectory);
			Main.quit();
			return;
		}
	}
}
