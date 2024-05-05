module picture;

import std;
import common;
import viewport;
import gdk.Pixbuf;

import app : currentWorkingDirectory, resetZoom;
import bindings : canvas, mnuZoomOnExit;


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

		// Get the filename without ext
		auto filename = baseName(Picture.list[Picture.index]).stripExtension ~ ".txt";
		auto labels = buildPath(currentWorkingDirectory, "labels", filename);

		rects.length = 0;

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


	void save()
	{
		auto filename = baseName(Picture.list[Picture.index]).stripExtension ~ ".txt";
		auto labels = buildPath(currentWorkingDirectory, "labels", filename);
		auto f = File(labels, "w+");

		info("Saving file (", Picture.rects.length , " lines): ", filename);

		foreach(idx, r; rects)
		{
			auto cx = (r.p1.x + r.p2.x) / 2;
			auto cy = (r.p1.y + r.p2.y) / 2;
			auto w = r.p2.x - r.p1.x;
			auto h = r.p2.y - r.p1.y;

			auto line = format("%d %.20f %.20f %.20f %.20f", r.label, cx, cy, w, h);
			f.writeln(line);
		}
	}

}