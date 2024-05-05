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
import viewport;
import gdk.Pixbuf;

import main : readAnnotations, writeAnnotations;
import gui : canvas, mnuZoomOnExit, resetZoom;

struct Picture
{
	static:

   string[] list;

	long 		index	= 0;
	int 		width;
	int 		height;
	Pixbuf 	pixbuf;

	Rectangle[] rects;

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
		assert(Picture.list.length > 0);

		int delta = forward ? 1 : -1;

		ViewPort.invalidated = true;
		long curIndex = index;

		while(true)
		{
			index += delta;

			if (index < 0) index = Picture.list.length - 1;
			else if (index >= Picture.list.length) index = 0;

			reload();

			if (!toAnnotate || Picture.rects.length == 0)
				break;

			if (index == curIndex)
				break;
		}
	}

	void next(bool toAnnotate = false) { cycle(true, toAnnotate); }
	void prev(bool toAnnotate = false) { cycle(false, toAnnotate); }

	void reload()
	{
		assert(Picture.list.length > 0);

		if (pixbuf !is null)
			pixbuf.unref();

		pixbuf = new Pixbuf(Picture.list[Picture.index]);
		width = pixbuf.getWidth;
		height = pixbuf.getHeight;

		rects = readAnnotations(Picture.list[Picture.index]);

		if (ViewPort.roiTopLeft.x > Picture.width) ViewPort.roiTopLeft.x = 0;
		if (ViewPort.roiTopLeft.y > Picture.height) ViewPort.roiTopLeft.y = 0;

		if (ViewPort.roiBottomRight.x > Picture.width) ViewPort.roiBottomRight.x = Picture.width;
		if (ViewPort.roiBottomRight.y > Picture.height) ViewPort.roiBottomRight.y = Picture.height;

		ViewPort.invalidated = true;

		// Check if mnuZoomOnExit is checked
		if (!mnuZoomOnExit.getActive)
			resetZoom();

		status = State.EDITING;
		canvas.queueDraw();
	}

	void save() { writeAnnotations(Picture.list[Picture.index], Picture.rects); }

}