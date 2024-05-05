module actions;

import std;
import app;
import bindings;
import gdk.Event, gtk.Widget,gtk.FileChooserDialog, gtk.Main;
import gdk.Pixbuf, cairo.Context, gdk.Keysyms, gdk.Cairo;

import common;
import picture;
import viewport;

Rectangle calculateBoundingBox(in Point[] points)
{
	Rectangle r;

	foreach(p; points)
	{
		if (p.x < r.p1.x) r.p1.x = p.x;
		if (p.y < r.p1.y) r.p1.y = p.y;
		if (p.x > r.p2.x) r.p2.x = p.x;
		if (p.y > r.p2.y) r.p2.y = p.y;
	}

	return r;
}

void confirmAnnotation()
{
	if (status != State.DRAWING || points.length < 2)
		return;

	Rectangle r = calculateBoundingBox(points);

	// Just an extra check, the points should be already inside the picture
	Point p1 = Point(min(1,max(r.p1.x, 0)), min(1,max(r.p1.y, 0)));
	Point p2 = Point(min(1,max(r.p2.x, 0)), min(1,max(r.p2.y, 0)));

	if (p1.x == p2.x || p1.y == p2.y)
		return;

	r.p1 = p1;
	r.p2 = p2;
	r.label = label;
	Picture.rects = r ~ Picture.rects;
	Picture.save();
}

void actionSearchLabel(string text)
{
	import gtk.TreeIter;

	int intColorFromIndex(size_t idx)
	{
		auto color = defaultLabelColors[idx % defaultLabelColors.length];
		return cast(int)(255*color[0]) << 24 | cast(int)(255*color[1]) << 16 | cast(int)(255*color[2]) << 8 | 0xFF;
	}

	void appendFromIndex(size_t idx)
	{
		TreeIter top = store.createIter();

		auto pb = new Pixbuf(GdkColorspace.RGB, false, 8, 16, 16);
		pb.fill(intColorFromIndex(idx));
		store.setValue(top, 0, pb);

		if (idx < labels.length && idx > 0) store.setValue(top, 1, labels[idx].toUpper);
		else store.setValue(top, 1, "<label not defined>");

		store.setValue(top, 2, idx);

		store.append(top);
	}

	store.clear();

	bool found = false;

	if (text.empty) foreach(idx; 1 .. labels.length) appendFromIndex(idx); // Show all if search is empty
	else if (text.all!isDigit) appendFromIndex(text.to!size_t);	// Show the label if the search is a number
	else
	{
		bool[size_t] added;

		// First check for exact matches
		foreach(idx, label; labels)
		{
			if (label.toLower == text.toLower)
			{
				appendFromIndex(idx);
				added[idx] = true;
				break;
			}
		}

		Tuple!(size_t, string)[] sortedByLength;

		foreach(idx, label; labels)
			if (idx > 0)
				sortedByLength ~= tuple(idx, label.toLower);

		sortedByLength = sortedByLength.sort!((a, b) => a[1].length < b[1].length).array;

		// Then check for startsWith
		foreach(item; sortedByLength)
		{
			auto idx = item[0];
			auto label = item[1];

			if (idx in added) continue;

			if (label.startsWith(text.toLower))
			{
				appendFromIndex(idx);
				added[idx] = true;
			}
		}

		// Then check for contains
		foreach(item; sortedByLength)
		{
			auto idx = item[0];
			auto label = item[1];

			if (idx in added) continue;

			if (label.canFind(text.toLower))
			{
				appendFromIndex(idx);
				added[idx] = true;
			}
		}

		// Then check for regex
		foreach(item; sortedByLength)
		{

			auto idx = item[0];
			auto label = item[1];

			if (idx in added) continue;

			string expr;
			foreach(c; text)
			{
				expr ~= `\x` ~ format("%02x", cast(ubyte)(std.ascii.toLower(c)));
				expr ~= ".*";
			}

			expr = expr[0 .. $-2];

			if(label.match(regex(expr)))
			{
				appendFromIndex(idx);
				added[idx] = true;
			}
		}
	}

	// Select the first item in the list
	TreeIter selected;
	store.getIterFirst(selected);

	if (selected.userData !is null)
		lstLabels.getSelection().selectIter(selected);

}

bool actionOpenDir(Event e, Widget w)
{
	// Let user choose a directory
	auto dialog = new FileChooserDialog("Choose a directory", mainWindow, FileChooserAction.SELECT_FOLDER, ["Cancel", "Open"], [ResponseType.CANCEL, ResponseType.ACCEPT]);
	dialog.setModal(true);
	dialog.setTransientFor(mainWindow);
	dialog.setSelectMultiple(false);

	scope(exit) dialog.destroy();

	if (dialog.run() == ResponseType.ACCEPT)
	{
		// Folder must contain images and labels
		if(!exists(buildPath(dialog.getFilename, "images")) || !exists(buildPath(dialog.getFilename, "labels")))
		{
			import gtk.MessageDialog;
			auto error = new MessageDialog(mainWindow, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.CLOSE, "The selected directory does not contain folders 'images' and 'labels'");
			error.setModal(true);
			error.run();
			error.destroy();
			return true;
		}

		// If keeping zoom on exit is not active, reset the viewport
		if (!mnuZoomOnExit.getActive)
			resetZoom();

		currentWorkingDirectory = dialog.getFilename;
		if (!readPicturesDir())
		{
			Main.quit();
			return true;
		}

		readLabels();
	}

	return true;
}

void actionToggleGuides()
{
	showGuides = !showGuides;

	mnuGuides.setActive(showGuides);
	canvas.queueDraw();
}

void actionPictureCycling(bool forward, bool toAnnotate = false)
{
	isGrabbing = false;
	confirmAnnotation();
	if (forward) Picture.next(toAnnotate);
	else Picture.prev(toAnnotate);
}

void actionChangeLabel(uint labelIdx)
{
	label = labelIdx;

	if (status == status.EDITING && Picture.rects.length > 0)
	{
		Picture.rects[0].label = labelIdx;
		Picture.save();
	}

	canvas.queueDraw();
}

void actionStartDrawing(bool force = false)
{
	isGrabbing = false;

	if (status == State.DRAWING)
		confirmAnnotation();

	if (!force && points.length <= 1 && status == State.DRAWING) status = State.EDITING;
	else status = State.DRAWING;

	points.length = 0;
	mnuUndo.setSensitive(false);
	canvas.queueDraw();
}

void actionEditingMode()
{
	isGrabbing = false;

	status = State.EDITING;
	canvas.queueDraw();
}

void actionDeleteRect()
{
	if (status == State.EDITING && Picture.rects.length > 0 && !isGrabbing)
	{
		Picture.rects = Picture.rects[1 .. $];
		Picture.save();
		canvas.queueDraw();
	}

	if (Picture.rects.length == 0)
		mnuDeleteAnnotation.setSensitive(false);

}

void actionUndoLastPoint()
{
	if (points.length > 0)
		points.length = points.length - 1;

	mnuUndo.setSensitive(points.length > 0);

	canvas.queueDraw();
}

void actionStartZoomDrawing()
{
	isZooming = true;
	zoomLines.length = 0;
}

void actionToggleZoom()
{
	if (!isZoomedIn && status == State.EDITING)
	{
		if(Picture.rects.length > 0)
		{
			auto r = Picture.rects[0];

			r.p1.x *= Picture.width;
			r.p1.y *= Picture.height;

			r.p2.x *= Picture.width;
			r.p2.y *= Picture.height;

			zoomToArea(r.p1, r.p2, 0.4);
			return;
		}
	}
	else if (status == State.DRAWING)
	{
		static Rectangle lastRect;

		Rectangle r;

		if(points.length > 1)
		{
			r = calculateBoundingBox(points);

			r.p1.x *= Picture.width;
			r.p1.y *= Picture.height;
			r.p2.x *= Picture.width;
			r.p2.y *= Picture.height;
		}

		if (r != lastRect)
		{
			zoomToArea(r.p1, r.p2, 0.4);
			lastRect = r;
			return;
		}
	}

	resetZoom();
}

void actionAnnotationCycling(bool forward)
{
	if (Picture.rects.length == 0 || status == State.DRAWING)
		return;

	if (isZoomedIn)
	{
		if (forward) Picture.nextRect();
		else Picture.prevRect();
	}

	auto r = Picture.rects[0];
	r.p1.x *= Picture.width;
	r.p1.y *= Picture.height;
	r.p2.x *= Picture.width;
	r.p2.y *= Picture.height;

	zoomToArea(r.p1, r.p2, 0.4);

}



// Handle key press events and map them to actions
bool onKeyPress(Event e, Widget w)
{

	uint key = e.key().keyval;

	switch (key)
	{
      case GdkKeysyms.GDK_Return:
         if (status == State.DRAWING)
         {
            confirmAnnotation();
            actionEditingMode();
         }
         break;

		case GdkKeysyms.GDK_Right, GdkKeysyms.GDK_Left:
			actionPictureCycling(key == GdkKeysyms.GDK_Right, e.key().state == ModifierType.CONTROL_MASK);
			break;

		case GdkKeysyms.GDK_0: .. case GdkKeysyms.GDK_9:
			actionChangeLabel(key - GdkKeysyms.GDK_0);
			break;

		case GdkKeysyms.GDK_space:
			actionStartDrawing();
			break;

		case GdkKeysyms.GDK_Escape:
			actionEditingMode();
			break;

		case GdkKeysyms.GDK_d, GdkKeysyms.GDK_D, GdkKeysyms.GDK_Delete, GdkKeysyms.GDK_BackSpace:
			actionDeleteRect();
			break;

		case GdkKeysyms.GDK_g, GdkKeysyms.GDK_G:
			actionToggleGuides();
			break;

		case GdkKeysyms.GDK_l, GdkKeysyms.GDK_L:
			search.setText("");
			actionSearchLabel("");
			wndLabels.showAll();
			break;

		case GdkKeysyms.GDK_z, GdkKeysyms.GDK_Z:
			if (e.key().state == ModifierType.CONTROL_MASK && status == State.DRAWING) actionUndoLastPoint();
			else actionToggleZoom();
			break;

		case GdkKeysyms.GDK_n, GdkKeysyms.GDK_N, GdkKeysyms.GDK_p, GdkKeysyms.GDK_P:
			actionAnnotationCycling(key == GdkKeysyms.GDK_n || key == GdkKeysyms.GDK_N);
			break;

		case GdkKeysyms.GDK_Control_L:
			actionStartZoomDrawing();
			break;

		default:
			debug info("KeyPressed not handled: ", key);
			break;
	}

	return true;
}

// Draw the current cropped pixbuf on the current image widget
bool onDraw(Context w, Widget e)
{
	Point normalizedToViewPort(Point p)
	{
		return Point(
			((p.x * Picture.width) - ViewPort.roiTopLeft.x) * ViewPort.scale,
			((p.y * Picture.height) - ViewPort.roiTopLeft.y) * ViewPort.scale
		);
	}

	// Get the current widget size
	int widgetWidth, widgetHeight;

	widgetHeight = e.getAllocatedHeight();
	widgetWidth = e.getAllocatedWidth();

	if (ViewPort.width != widgetWidth || ViewPort.height != widgetHeight)
		ViewPort.invalidated = true;

	ViewPort.width = widgetWidth;
	ViewPort.height = widgetHeight;

	// Get the current pixbuf
	auto currentPixbuf = ViewPort.view();

	//setSourceColor(w, new Color(50,50,50));
	w.setSourceRgb(0.2, 0.2, 0.2);
	w.rectangle(0, 0, widgetWidth, widgetHeight);
	w.fill();

	// Set the current pixbuf as source for the drawing context
	setSourcePixbuf(w, currentPixbuf, ViewPort.offsetX, ViewPort.offsetY);

	// Draw the image
	w.paint();

	// Draw all rects
	foreach(idx, r; Picture.rects)
	{

		if (status == State.EDITING && idx == 0) w.setDash([5, 5], 0);
		else w.setDash([], 0);

		w.setSourceRgba(defaultLabelColors[r.label][0], defaultLabelColors[r.label][1], defaultLabelColors[r.label][2], 0.8);

		auto rp1 = normalizedToViewPort(r.p1);
		auto rp2 = normalizedToViewPort(r.p2);

		w.rectangle(
			ViewPort.offsetX + rp1.x,
			ViewPort.offsetY + rp1.y,
			(rp2.x - rp1.x),
			(rp2.y - rp1.y)
		);

		w.stroke();

		w.setDash([], 0);

		// Draw handles on corner and one on center
		if (status == State.EDITING && idx == 0)
		{
			Point[] corners = [r.p1, Point(r.p2.x, r.p1.y), r.p2, Point(r.p1.x, r.p2.y)];

			foreach(c; corners)
			{
				auto cn = normalizedToViewPort(c);
				// Draw a white circle as handle
				//setSourceColor(w, new Color(255,255,255));
				w.arc(
					ViewPort.offsetX + cn.x,
					ViewPort.offsetY + cn.y,
					5, 0, 2*PI
				);

				w.stroke();
			}


			// Draw rect in middle of the sides
			Point[] sides = [Point((r.p1.x + r.p2.x) / 2, r.p1.y), Point(r.p2.x, (r.p1.y + r.p2.y) / 2), Point((r.p1.x + r.p2.x) / 2, r.p2.y), Point(r.p1.x, (r.p1.y + r.p2.y) / 2)];

			foreach(s; sides)
			{
				auto sn = normalizedToViewPort(s);
				// Draw a white circle as handle
				//setSourceColor(w, new Color(255,255,255));
				w.arc(
					ViewPort.offsetX + sn.x,
					ViewPort.offsetY + sn.y,
					3, 0, 2 * PI
				);
				w.fill();
			}

			// Draw a rect in the center
			Point center = normalizedToViewPort(Point((r.p1.x + r.p2.x) / 2, (r.p1.y + r.p2.y) / 2));
			w.arc(
				ViewPort.offsetX + center.x,
				ViewPort.offsetY + center.y,
				5, 0, 2 * PI
			);
			w.stroke();

			// Draw a small label under the rect
			if (r.label > 0 && r.label < labels.length)
			{
				auto xx1 = normalizedToViewPort(r.p1);
				auto xx2 = normalizedToViewPort(r.p2);

				w.setFontSize(10);
				w.moveTo(ViewPort.offsetX + xx1.x, ViewPort.offsetY + xx2.y + 18);
				w.showText(labels[r.label]);
			}


		}
	}

	if (isZooming && zoomLines.length > 1)
	{
		w.setSourceRgba(1,1,1,0.5);
		w.setLineWidth(4);

		w.moveTo(ViewPort.offsetX + zoomLines[0].x, ViewPort.offsetY + zoomLines[0].y);

		foreach(z; zoomLines[1..$])
		{
			w.lineTo(ViewPort.offsetX+z.x, ViewPort.offsetY+z.y);

		}
		w.stroke();
	}


	if (status == State.DRAWING)
	{
		w.setDash([10,5,2,5], 0);
		w.setLineWidth(2);

	 	// Get the boundingbox of the points
		Rectangle r = calculateBoundingBox(points);

		auto rp1 = normalizedToViewPort(r.p1);
		auto rp2 = normalizedToViewPort(r.p2);

		w.setSourceRgb(0.2, 0.2, 0.2);
		w.rectangle(
			ViewPort.offsetX + rp1.x + 2,
			ViewPort.offsetY + rp1.y + 2,
			(rp2.x - rp1.x),
			(rp2.y - rp1.y)
		);
		w.stroke();

		// Draw the bounding box

		w.setSourceRgba(defaultLabelColors[label][0], defaultLabelColors[label][1], defaultLabelColors[label][2], 0.8);
		w.rectangle(
			ViewPort.offsetX + rp1.x,
			ViewPort.offsetY + rp1.y,
			(rp2.x - rp1.x),
			(rp2.y - rp1.y)
		);

		w.stroke();

		foreach(p; points)
		{
			auto pv = normalizedToViewPort(p);

			// Draw a point adjusting coords to the zoom
			w.arc
			(
				ViewPort.offsetX + pv.x,
				ViewPort.offsetY + pv.y,
				5, 0, 2 * PI
			);
			w.fill();
		}

		// Draw a small label under the rect
		if (r.label > 0 && r.label < labels.length)
		{
			auto xx1 = normalizedToViewPort(r.p1);
			auto xx2 = normalizedToViewPort(r.p2);

			w.setFontSize(10);
			w.moveTo(ViewPort.offsetX + xx1.x, ViewPort.offsetY + xx2.y + 18);
			w.showText(labels[r.label]);
		}

		if (showGuides)
		{
			w.setSourceRgb(1,1,1);
			w.setLineWidth(1);
			w.setDash([10,10], 0);

			w.moveTo(0, lastMouseCoords.y);
			w.lineTo(lastMouseCoords.x-16, lastMouseCoords.y);
			w.stroke();

			w.moveTo(lastMouseCoords.x + 16, lastMouseCoords.y);
			w.lineTo(ViewPort.width, lastMouseCoords.y);
			w.stroke();

			w.moveTo(lastMouseCoords.x, 0);
			w.lineTo(lastMouseCoords.x, lastMouseCoords.y-16);
			w.stroke();

			w.moveTo(lastMouseCoords.x, lastMouseCoords.y + 16);
			w.lineTo(lastMouseCoords.x, ViewPort.height);
			w.stroke();

		}

	}

	return true;

}


bool onClick(Event e, Widget w)
{
	// Ignore the double click!
	if(e.button().type != GdkEventType.BUTTON_PRESS)
		return true;

	// Get the current coords
	Point coords;
	e.getCoords(coords.x, coords.y);

	// Translate the coords using offset and zoom factor
	coords.x -= ViewPort.offsetX;
	coords.y -= ViewPort.offsetY;

	coords.x =  (coords.x / ViewPort.scale) + ViewPort.roiTopLeft.x;
	coords.y =  (coords.y / ViewPort.scale) + ViewPort.roiTopLeft.y;

	auto normalized = Point(coords.x / Picture.width, coords.y / Picture.height);

	if (status == State.DRAWING)
	{
		if (normalized.x < 0) normalized.x = 0;
		if (normalized.x > 1) normalized.x = 1;
		if (normalized.y < 0) normalized.y = 0;
		if (normalized.y > 1) normalized.y = 1;

		mnuUndo.setSensitive(true);
		points ~= normalized;
		canvas.queueDraw();
	}
	else if (status == State.EDITING)
	{
		if (isGrabbing)
		{
			isGrabbing = false;
			grabIndex = -1;

			// Sort p1 and p2
			Point p1 = Point(min(Picture.rects[0].p1.x, Picture.rects[0].p2.x), min(Picture.rects[0].p1.y, Picture.rects[0].p2.y));
			Point p2 = Point(max(Picture.rects[0].p1.x, Picture.rects[0].p2.x), max(Picture.rects[0].p1.y, Picture.rects[0].p2.y));

			p1 = Point(min(1,max(p1.x, 0)), min(1,max(p1.y, 0)));
			p2 = Point(min(1,max(p2.x, 0)), min(1,max(p2.y, 0)));

			Picture.rects[0].p1 = p1;
			Picture.rects[0].p2 = p2;

			bool isOutside = p1.x == p2.x || p1.y == p2.y;

			if (isOutside)
			{
				Picture.rects = Picture.rects[1 .. $];
				Picture.save();
			}
			else Picture.save();

			canvas.queueDraw();
			mainWindow.setCursor(standard);
			return true;
		}

		// Check if mouse is over an angle of the first rect
		if (Picture.rects.length > 0)
		{
			auto r = Picture.rects[0];
			Point[] corners = [r.p1, Point(r.p2.x, r.p1.y), r.p2, Point(r.p1.x, r.p2.y)];

			foreach(idx, c; corners)
			{
				if (abs(c.x - normalized.x) < 0.01 && abs(c.y - normalized.y) < 0.01)
				{
					isGrabbing = true;
					grabIndex = cast(int)idx;
					mainWindow.setCursor(editing);
					return true;
				}
			}

			// Check if mouse is over the center of the first rect
			Point center = Point((r.p1.x + r.p2.x) / 2, (r.p1.y + r.p2.y) / 2);
			if (abs(center.x - normalized.x) < 0.01 && abs(center.y - normalized.y) < 0.01)
			{
				isGrabbing = true;
				grabIndex = 4;
				mainWindow.setCursor(handClosed);
				return true;
			}

			// Check if mouse is over the sides of the first rect
			Point[] sides = [Point((r.p1.x + r.p2.x) / 2, r.p1.y), Point(r.p2.x, (r.p1.y + r.p2.y) / 2), Point((r.p1.x + r.p2.x) / 2, r.p2.y), Point(r.p1.x, (r.p1.y + r.p2.y) / 2)];

			foreach(idx, s; sides)
			{
				if (abs(s.x - normalized.x) < 0.01 && abs(s.y - normalized.y) < 0.01)
				{
					isGrabbing = true;
					grabIndex = cast(int)idx+5;
					mainWindow.setCursor(editing);
					return true;
				}
			}
		}

		// Search for the rect that contains the point
		foreach(idx, r; Picture.rects)
		{
			if (normalized.x > r.p1.x  && normalized.x < r.p2.x && normalized.y > r.p1.y && normalized.y < r.p2.y)
			{
				auto selected = r;

				if (idx != 0)
				{
					auto first = Picture.rects[0];
					Picture.rects = selected ~ Picture.rects[1 .. idx] ~ Picture.rects[idx + 1 .. $] ~ first;
				}
				else continue;

				canvas.queueDraw();
				break;
			}
		}
	}

	return true;
}

bool onMotion(Event e, Widget w)
{
	// Get the current coords (int the widget space)
	Point coords;
	e.getCoords(coords.x, coords.y);

	lastMouseCoords = coords;

	coords.x -= ViewPort.offsetX;
	coords.y -= ViewPort.offsetY;

	if (isZooming)
	{

		zoomLines ~= Point(coords.x, coords.y);
		canvas.queueDraw();
		return true;
	}

	coords.x = (coords.x/ViewPort.scale + ViewPort.roiTopLeft.x);
	coords.y = (coords.y/ViewPort.scale + ViewPort.roiTopLeft.y);

	if (status == State.EDITING)
	{

		auto normalized = Point(coords.x / Picture.width, coords.y / Picture.height);

		if (isGrabbing)
		{
			assert(grabIndex >= 0 && grabIndex <= 8);

			// Move top left corner
			if (grabIndex == 0) { Picture.rects[0].p1 = normalized; }
			else if (grabIndex == 2) { Picture.rects[0].p2 = normalized; }
			else if (grabIndex == 1)
			{
				Picture.rects[0].p2.x = normalized.x;
				Picture.rects[0].p1.y = normalized.y;
			}
			else if (grabIndex == 3)
			{
				Picture.rects[0].p1.x = normalized.x;
				Picture.rects[0].p2.y = normalized.y;
			}
			else if (grabIndex == 4)
			{
				Point center = Point((Picture.rects[0].p1.x + Picture.rects[0].p2.x) / 2, (Picture.rects[0].p1.y + Picture.rects[0].p2.y) / 2);
				Point delta = Point(normalized.x - center.x, normalized.y - center.y);
				Picture.rects[0].p1.x += delta.x;
				Picture.rects[0].p1.y += delta.y;
				Picture.rects[0].p2.x += delta.x;
				Picture.rects[0].p2.y += delta.y;
			}
			else if (grabIndex == 5) Picture.rects[0].p1.y = normalized.y;
			else if (grabIndex == 6) Picture.rects[0].p2.x = normalized.x;
			else if (grabIndex == 7) Picture.rects[0].p2.y = normalized.y;
			else if (grabIndex == 8) Picture.rects[0].p1.x = normalized.x;

			canvas.queueDraw();

			return true;
		}

		// Check if mouse is over an angle of the first rect
		if (Picture.rects.length > 0)
		{
			auto r = Picture.rects[0];
			Point[] corners = [r.p1, Point(r.p2.x, r.p1.y), r.p2, Point(r.p1.x, r.p2.y)];

			foreach(idx, c; corners)
			{
				if (abs(c.x - normalized.x) < 0.01 && abs(c.y - normalized.y) < 0.01)
				{
					mainWindow.setCursor(directions[idx*2]);
					return true;
				}
			}

			// Check if mouse is over the center of the first rect
			Point center = Point((r.p1.x + r.p2.x) / 2, (r.p1.y + r.p2.y) / 2);
			if (abs(center.x - normalized.x) < 0.01 && abs(center.y - normalized.y) < 0.01)
			{
				mainWindow.setCursor(hand);
				return true;
			}

			// Check if mouse is over the sides of the first rect
			Point[] sides = [Point((r.p1.x + r.p2.x) / 2, r.p1.y), Point(r.p2.x, (r.p1.y + r.p2.y) / 2), Point((r.p1.x + r.p2.x) / 2, r.p2.y), Point(r.p1.x, (r.p1.y + r.p2.y) / 2)];

			foreach(idx, s; sides)
			{
				if (abs(s.x - normalized.x) < 0.01 && abs(s.y - normalized.y) < 0.01)
				{
					mainWindow.setCursor(directions[1+idx*2]);
					return true;
				}
			}
		}

		mainWindow.setCursor(standard);
	}
	else if (showGuides) canvas.queueDraw();

	return true;
}

bool onKeyRelease(Event e, Widget w)
{
	if (e.key().keyval == GdkKeysyms.GDK_Control_L)
	{
		isZooming = false;

		// User didn't actually move the mouse
		if (zoomLines.length < 2)
		{
			zoomLines.length = 0;
			canvas.queueDraw();
			return true;
		}

		// Get the boundibg box of the lines
		Rectangle r = calculateBoundingBox(zoomLines);

		// Set zoom to fit the bounding box + 5% padding
		zoomLines.length = 0;
		zoomToViewPortArea(r.p1, r.p2, 0.05);
	}

	return true;
}