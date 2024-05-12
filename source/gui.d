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

module gui;


import std;

import common;
import picture;
import widgets;

import gtk.Main, gtk.TreeStore, gtk.Widget, gtk.CellRendererText, gtk.CellRendererPixbuf, gtk.FileChooserDialog;
import gdk.Cursor, gdk.Event, gdk.Keysyms, gdk.Pixbuf;
import gdk.Cairo : setSourcePixbuf;

import cairo.Context;

struct GUI
{
	static:

	TreeStore			store;

	string[]			labels;

	Point[] 			zoomLines;
	bool				isZooming = false;

	bool isGrabbing = false;
	bool showGuides = false;
	int  grabIndex = -1;

	Cursor standard;
	Cursor pencil;
	Cursor hand;
	Cursor handClosed;
	Cursor editing;
	Cursor[] directions;

	Point				lastMouseCoords;
	Point[] 			points;
	int				label = 0;

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
		if (status != State.ANNOTATING || points.length < 2)
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
		r.score = float.max;
		Picture.rects = r ~ Picture.rects;

		Picture.writeAnnotations();
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

			if (idx < labels.length) store.setValue(top, 1, labels[idx].toUpper);
			else store.setValue(top, 1, "<label not defined>");

			store.setValue(top, 2, idx);

			store.append(top);
		}

		store.clear();

		if (text.empty) foreach(idx; 0 .. labels.length) appendFromIndex(idx); // Show all if search is empty
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

	bool actionOpenDir()
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

			workingDirectory = dialog.getFilename;
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
		confirmAnnotation();
		actionEditingMode();

		if (forward) Picture.next(toAnnotate);
		else Picture.prev(toAnnotate);
	}

	void actionChangeLabel(uint labelIdx)
	{
		label = labelIdx;

		if (status == status.EDITING && Picture.rects.length > 0)
		{
			Picture.rects[0].label = labelIdx;
			Picture.rects[0].score = float.max;
			Picture.writeAnnotations();
		}

		canvas.queueDraw();
	}

	void actionStartDrawing(bool force = false)
	{
		isGrabbing = false;

		if (status == State.ANNOTATING)
			confirmAnnotation();

		if (!force && points.length <= 1 && status == State.ANNOTATING) status = State.EDITING;
		else status = State.ANNOTATING;

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
			Picture.writeAnnotations();
			canvas.queueDraw();
		}

		if (Picture.rects.length == 0)
			mnuDeleteAnnotation.setSensitive(false);

	}

	void actionUndo()
	{
		if (status == State.ANNOTATING)
		{
			if (points.length > 0)
				points.length = points.length - 1;

			mnuUndo.setSensitive(points.length > 0);
		}
		else Picture.historyBack();

		canvas.queueDraw();
	}

	void actionRedo()
	{
		if (status == State.EDITING)
		{
			Picture.historyForward();
			canvas.queueDraw();
		}
	}

	void actionStartZoomDrawing()
	{
		isZooming = true;
		zoomLines.length = 0;
	}

	void actionToggleZoom()
	{
		if (status == State.EDITING)
		{
			if (isZoomedIn) resetZoom();
			else if(Picture.rects.length > 0)
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
		else if (status == State.ANNOTATING)
		{
			static Rectangle lastRect;

			immutable hasBox = points.length > 1;
			Rectangle r;

			if(hasBox)
			{
				r = calculateBoundingBox(points);

				r.p1.x *= Picture.width;
				r.p1.y *= Picture.height;
				r.p2.x *= Picture.width;
				r.p2.y *= Picture.height;
			}

			immutable zoomIn =
				(!isZoomedIn && hasBox) ||	// Zoom in if there is a box and we are not zoomed in
				(isZoomedIn && hasBox && lastRect != r); // Zoom in if the box changed

			if (zoomIn)
			{
				zoomToArea(r.p1, r.p2, 0.4);
				lastRect = r;
			}
			else if (isZoomedIn)
				resetZoom();	// Reset zoom if we are zoomed in

		}

	}

	void actionAnnotationCycling(bool forward)
	{
		if (Picture.rects.length == 0 || status == State.ANNOTATING)
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

	void actionShowAISettings()
	{
		import ai: AI;

		if (!AI.hasAI)
		{
			showMissingAIError();
			return;
		}

		fileAILabels.setCurrentName(AI.labelsFile);
		fileAIModel.setCurrentName(AI.modelFile);

		chkAIGpu.setActive = false;
		btnAIOk.setSensitive(true);
		btnAIOk.setLabel("Load");

		adjConfidence.setValue(60);
		adjOverlapping.setValue(90);
		wndAI.showAll();
	}

	void showMissingAIError()
	{
		import gtk.MessageDialog;
		auto error = new MessageDialog(mainWindow, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.CLOSE, "I can't load the AI module.\nDo you have the AI library ONNX installed?\n\nPlease check the README.md for more information.");
		error.setModal(true);
		error.run();
		error.destroy();
	}


	// Handle key press events and map them to actions
	bool onKeyPress(Event e, Widget w)
	{

		uint key = e.key().keyval;
		bool isCtrlPressed = ((e.key().state & ModifierType.CONTROL_MASK) == ModifierType.CONTROL_MASK) || ((e.key().state & cast(GdkModifierType)268435472) == cast(GdkModifierType)268435472);

		switch (key)
		{
			case GdkKeysyms.GDK_a, GdkKeysyms.GDK_A:

				import ai : AI;

				if (status == State.ANNOTATING) break;
				else if (!AI.hasModel) actionShowAISettings();
				else
				{
					auto airects = AI.boxes(Picture.current);
					Picture.rects ~= airects;
					Picture.historyCommit();
					confirmAnnotation();
					canvas.queueDraw();
				}

				break;
			case GdkKeysyms.GDK_Return:
				if (status == State.ANNOTATING)
				{
					confirmAnnotation();
					actionEditingMode();
				}
				break;

			case GdkKeysyms.GDK_Right, GdkKeysyms.GDK_Left:
				actionPictureCycling(key == GdkKeysyms.GDK_Right, isCtrlPressed);
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
				if (isCtrlPressed) actionUndo();
				else actionToggleZoom();
				break;

			case GdkKeysyms.GDK_y, GdkKeysyms.GDK_Y:
				if (isCtrlPressed) actionRedo();
				else actionToggleZoom();
				break;

			case GdkKeysyms.GDK_n, GdkKeysyms.GDK_N, GdkKeysyms.GDK_p, GdkKeysyms.GDK_P:
				actionAnnotationCycling(key == GdkKeysyms.GDK_n || key == GdkKeysyms.GDK_N);
				break;

			case GdkKeysyms.GDK_Shift_L:
				actionStartZoomDrawing();
				break;

			case GdkKeysyms.GDK_F5:
				reloadDirectory();
				break;

			default:
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
				((p.x * Picture.width) - Picture.ViewPort.roiTopLeft.x) * Picture.ViewPort.scale,
				((p.y * Picture.height) - Picture.ViewPort.roiTopLeft.y) * Picture.ViewPort.scale
			);
		}

		// Get the current widget size
		int widgetWidth, widgetHeight;

		widgetHeight = e.getAllocatedHeight();
		widgetWidth = e.getAllocatedWidth();

		if (Picture.ViewPort.width != widgetWidth || Picture.ViewPort.height != widgetHeight)
			Picture.ViewPort.invalidated = true;

		Picture.ViewPort.width = widgetWidth;
		Picture.ViewPort.height = widgetHeight;

		// Get the current pixbuf
		auto currentPixbuf = Picture.ViewPort.view();

		//setSourceColor(w, new Color(50,50,50));
		w.setSourceRgb(0.2, 0.2, 0.2);
		w.rectangle(0, 0, widgetWidth, widgetHeight);
		w.fill();

		// Set the current pixbuf as source for the drawing context
		setSourcePixbuf(w, currentPixbuf, Picture.ViewPort.offsetX, Picture.ViewPort.offsetY);

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
				Picture.ViewPort.offsetX + rp1.x,
				Picture.ViewPort.offsetY + rp1.y,
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
						Picture.ViewPort.offsetX + cn.x,
						Picture.ViewPort.offsetY + cn.y,
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
						Picture.ViewPort.offsetX + sn.x,
						Picture.ViewPort.offsetY + sn.y,
						3, 0, 2 * PI
					);
					w.fill();
				}

				// Draw a rect in the center
				Point center = normalizedToViewPort(Point((r.p1.x + r.p2.x) / 2, (r.p1.y + r.p2.y) / 2));
				w.arc(
					Picture.ViewPort.offsetX + center.x,
					Picture.ViewPort.offsetY + center.y,
					5, 0, 2 * PI
				);
				w.stroke();

				// Draw a small label under the rect
				if (r.label < labels.length)
				{
					string text = labels[r.label];
					if (r.score != float.max)
						text ~= format(" (%2.2f%%)", 100*r.score);

					cairo_text_extents_t te;
					w.setFontSize(10);
					w.textExtents(text, &te);
					w.rectangle(Picture.ViewPort.offsetX + rp1.x - 5, Picture.ViewPort.offsetY + rp2.y + 8, te.width + 10, 18);
					w.fill();

					w.setSourceRgba(0,0,0, 0.8);
					w.moveTo(Picture.ViewPort.offsetX + rp1.x, Picture.ViewPort.offsetY + rp2.y + 8 + te.height + (18 - te.height) / 2);
					w.showText(text);
				}


			}
		}

		if (isZooming && zoomLines.length > 1)
		{
			w.setSourceRgba(1,1,1,0.5);
			w.setLineWidth(4);

			w.moveTo(Picture.ViewPort.offsetX + zoomLines[0].x, Picture.ViewPort.offsetY + zoomLines[0].y);

			foreach(z; zoomLines[1..$])
			{
				w.lineTo(Picture.ViewPort.offsetX+z.x, Picture.ViewPort.offsetY+z.y);

			}
			w.stroke();
		}


		if (status == State.ANNOTATING)
		{
			w.setDash([10,5,2,5], 0);
			w.setLineWidth(2);

			// Get the boundingbox of the points
			Rectangle r = calculateBoundingBox(points);

			auto rp1 = normalizedToViewPort(r.p1);
			auto rp2 = normalizedToViewPort(r.p2);

			w.setSourceRgb(0.2, 0.2, 0.2);
			w.rectangle(
				Picture.ViewPort.offsetX + rp1.x + 2,
				Picture.ViewPort.offsetY + rp1.y + 2,
				(rp2.x - rp1.x),
				(rp2.y - rp1.y)
			);
			w.stroke();

			// Draw the bounding box

			w.setSourceRgba(defaultLabelColors[label][0], defaultLabelColors[label][1], defaultLabelColors[label][2], 0.8);
			w.rectangle(
				Picture.ViewPort.offsetX + rp1.x,
				Picture.ViewPort.offsetY + rp1.y,
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
					Picture.ViewPort.offsetX + pv.x,
					Picture.ViewPort.offsetY + pv.y,
					5, 0, 2 * PI
				);
				w.fill();
			}

			// Draw a small label under the rect
			if (points.length > 1 && label < labels.length)
			{
				cairo_text_extents_t te;
				w.setFontSize(10);
				w.textExtents(labels[label], &te);
				w.rectangle(Picture.ViewPort.offsetX + rp1.x - 5, Picture.ViewPort.offsetY + rp2.y + 8, te.width + 10, 18);
				w.fill();

				w.setSourceRgba(0,0,0, 0.8);
				w.setFontSize(10);
				w.moveTo(Picture.ViewPort.offsetX + rp1.x, Picture.ViewPort.offsetY + rp2.y + 8 + te.height + (18 - te.height) / 2);
				w.showText(labels[label]);
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
				w.lineTo(Picture.ViewPort.width, lastMouseCoords.y);
				w.stroke();

				w.moveTo(lastMouseCoords.x, 0);
				w.lineTo(lastMouseCoords.x, lastMouseCoords.y-16);
				w.stroke();

				w.moveTo(lastMouseCoords.x, lastMouseCoords.y + 16);
				w.lineTo(lastMouseCoords.x, Picture.ViewPort.height);
				w.stroke();

			}

		}

		return true;

	}

	void updateHistoryMenu()
	{
		if (status == State.EDITING)
		{
			mnuUndo.setSensitive(Picture.historyIndex > 0);
			mnuRedo.setSensitive(Picture.historyIndex < Picture.history.length - 1);
		}
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
		coords.x -= Picture.ViewPort.offsetX;
		coords.y -= Picture.ViewPort.offsetY;

		coords.x =  (coords.x / Picture.ViewPort.scale) + Picture.ViewPort.roiTopLeft.x;
		coords.y =  (coords.y / Picture.ViewPort.scale) + Picture.ViewPort.roiTopLeft.y;

		auto normalized = Point(coords.x / Picture.width, coords.y / Picture.height);

		if (status == State.ANNOTATING)
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
				Picture.rects[0].score = float.max;

				bool isOutside = p1.x == p2.x || p1.y == p2.y;

				if (isOutside)
				{
					Picture.rects = Picture.rects[1 .. $];
					Picture.writeAnnotations();
				}
				else Picture.writeAnnotations();

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

		coords.x -= Picture.ViewPort.offsetX;
		coords.y -= Picture.ViewPort.offsetY;

		if (isZooming)
		{

			zoomLines ~= Point(coords.x, coords.y);
			canvas.queueDraw();
			return true;
		}

		coords.x = (coords.x/Picture.ViewPort.scale + Picture.ViewPort.roiTopLeft.x);
		coords.y = (coords.y/Picture.ViewPort.scale + Picture.ViewPort.roiTopLeft.y);

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
		if (e.key().keyval == GdkKeysyms.GDK_Shift_L)
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


	bool zoomToArea(Point topLeft, Point bottomRight, float padding = 0.05)
	{
		if (padding)
		{
			auto tWidth = bottomRight.x - topLeft.x;
			auto tHeight = bottomRight.y - topLeft.y;

			topLeft.x -= tWidth * padding;
			topLeft.y -= tHeight * padding;
			bottomRight.x += tWidth * padding;
			bottomRight.y += tHeight * padding;
		}

		if (topLeft.x > Picture.width) topLeft.x = Picture.width;
		if (topLeft.y > Picture.height) topLeft.y = Picture.height;

		if (bottomRight.x > Picture.width) bottomRight.x = Picture.width;
		if (bottomRight.y > Picture.height) bottomRight.y = Picture.height;

		if (topLeft.x < 0) topLeft.x = 0;
		if (topLeft.y < 0) topLeft.y = 0;

		if (bottomRight.x < 0) bottomRight.x = 0;
		if (bottomRight.y < 0) bottomRight.y = 0;

		// Calculate area in the picture coords space
		{
			auto width = (bottomRight.x - topLeft.x);
			auto height = (bottomRight.y - topLeft.y);
			auto area = width*height;

			// Cancel zoom if area is too small
			if (area < 8*8)
			{
				warning("Area too small: ", area, " squared pixels");
				zoomLines.length = 0;
				canvas.queueDraw();
				return false;
			}
		}

		Picture.ViewPort.roiTopLeft = topLeft;
		Picture.ViewPort.roiBottomRight = bottomRight;
		Picture.ViewPort.invalidated = true;
		canvas.queueDraw();

		return true;
	}

	bool zoomToViewPortArea(Point topLeft, Point bottomRight, float padding = 0.05)
	{
		// Force min size
		if (bottomRight.x - topLeft.x < 20)
		{
			topLeft.x -= 10;
			bottomRight.x += 10;
		}

		if (bottomRight.y - topLeft.y < 20)
		{
			topLeft.y -= 10;
			bottomRight.y += 10;
		}

		// Calculate area in the view port coords space
		{
			auto area = (bottomRight.x - topLeft.x) * (bottomRight.y - topLeft.y);

			if (area < 25)
			{
				warning("Ignored : ", area, " squared pixels");
				return false;
			}
		}

		topLeft.x = topLeft.x / Picture.ViewPort.scale + Picture.ViewPort.roiTopLeft.x;
		topLeft.y = topLeft.y / Picture.ViewPort.scale + Picture.ViewPort.roiTopLeft.y;
		bottomRight.x = bottomRight.x / Picture.ViewPort.scale + Picture.ViewPort.roiTopLeft.x;
		bottomRight.y = bottomRight.y / Picture.ViewPort.scale + Picture.ViewPort.roiTopLeft.y;

		return zoomToArea(topLeft, bottomRight, padding);
	}

	bool isZoomedIn() { return !(Picture.ViewPort.roiBottomRight.x - Picture.ViewPort.roiTopLeft.x == Picture.width && Picture.ViewPort.roiBottomRight.y - Picture.ViewPort.roiTopLeft.y == Picture.height); }

	void resetZoom()
	{
		Picture.ViewPort.roiTopLeft = Point(0, 0);
		Picture.ViewPort.roiBottomRight = Point(Picture.width, Picture.height);
		Picture.ViewPort.invalidated = true;
		canvas.queueDraw();
	}

	bool readLabels()
	{
		labels.length = 0;

		string file = buildPath(workingDirectory, "labels.txt");
		if (!exists(file)) file = buildPath(workingDirectory, "classes.txt");

		if (!exists(file))
			return false;

		labels = readText(file).splitter("\n").filter!(a => a.length > 0).map!(x => x.strip).array;
		return true;
	}


	void reinit()
	{
		import std.process : browse;

		static Pixbuf logo = null;

		if (logo is null)
		{
			import imports : LOGO;
			string tmpLogo = buildPath(tempDir, "etichetta-logo-tmp.svg");
			std.file.write(tmpLogo, LOGO);
			logo = new Pixbuf(tmpLogo);
			remove(tmpLogo);
		}

		mainWindow.setIcon(logo);
		mainWindow.setTitle("Etichetta " ~ VERSION_STRING ~ " - GitHub: trikko/etichetta");
		mainWindow.addOnDelete( (Event e, Widget w){ Main.quit(); return true; } );
		mainWindow.showAll();

		wndAbout.setIcon(logo);
		wndAbout.addOnDelete( (Event e, Widget w){ wndAbout.hide(); return true; } );
		imgLogo.setFromPixbuf(logo);
		btnWebsite.addOnButtonPress( (Event e, Widget w){ browse("https://github.com/trikko/etichetta"); return false; } );
		btnDonate.addOnButtonPress( (Event e, Widget w){ browse("https://www.paypal.me/andreafontana/5"); return false; } );

		wndAI.setIcon(logo);
		wndAI.addOnDelete( (Event e, Widget w){ wndAI.hide(); return true; } );

		btnAICancel.addOnButtonPress( (Event e, Widget w){ wndAI.hide(); return true; } );
		btnAIOk.addOnButtonPress( (Event e, Widget w){
			import ai: AI;
			import gtk.MessageDialog;

			auto model = fileAIModel.getFile().getPath();
			auto labels = fileAILabels.getFile().getPath();

			// Check if user selected a model file and a labels file
			if (model.empty || labels.empty)
			{
				// Show a warning in a messagebox
				auto dialog = new MessageDialog(wndAI, DialogFlags.MODAL, MessageType.WARNING, ButtonsType.CLOSE, "Please select a model and a labels file");
				dialog.setModal(true);
				dialog.run();
				dialog.destroy();

				return true;
			}

			btnAIOk.setSensitive(false);
			btnAIOk.setLabel("Loading...");

			scope(exit)
			{
				btnAIOk.setSensitive(true);
				btnAIOk.setLabel("Load");
			}

			// Load the model and the labels
			if(!AI.load(model, labels, chkAIGpu.getActive?AI.availableExecProviders[0][0]:"CPU"))
			{
				auto dialog = new MessageDialog(wndAI, DialogFlags.MODAL, MessageType.WARNING, ButtonsType.CLOSE, "Error loading the model.\nPlease check the files and try again.");
				dialog.setModal(true);
				dialog.run();
				dialog.destroy();
				return true;
			}

			// Check labels match between AI.labels and GUI.labels

			int[string] guiLabels;
			foreach(idx, l; GUI.labels)
				guiLabels[l] = cast(int)idx;

			AI.labelsMap = null;

			foreach(idx, l; AI.labels)
			{
				if (l in guiLabels)
				{
					assert(GUI.labels[guiLabels[l]] == l);
					AI.labelsMap[cast(int)idx] = guiLabels[l];
					debug info("Matching label (AI -> GUI): ", l, "(", idx ,") -> ",  GUI.labels[guiLabels[l]], "(", guiLabels[l], ")");
				}
			}

			if(AI.labelsMap.empty)
			{
				auto dialog = new MessageDialog(wndAI, DialogFlags.MODAL, MessageType.WARNING, ButtonsType.CLOSE, "No labels match between the AI labels and the project labels.\nPlease check the files and try again.");
				dialog.setModal(true);
				dialog.run();
				dialog.destroy();
			}

			mnuAuto.setSensitive(true);

			AI.minConfidence = adjConfidence.getValue() / 100;
			AI.maxOverlapping = adjOverlapping.getValue() / 100;
			wndAI.hide();
			return true;
		} );

		// Bind events
		canvas.addOnDraw(toDelegate(&onDraw));

		evtLayer.addOnButtonPress(toDelegate(&onClick));			// Click on image
		evtLayer.addOnMotionNotify(toDelegate(&onMotion));		// Mouse move on image

		mainWindow.addOnKeyRelease(toDelegate(&onKeyRelease));	// Key release
		mainWindow.addOnKeyPress(toDelegate(&onKeyPress));			// Key press

		mnuOpen.addOnButtonPress((Event e, Widget w){ actionOpenDir(); return true; }); // Open a directory
		mnuReload.addOnButtonPress((Event e, Widget w){ reloadDirectory(); return true; }); // Reload the current directory

		mnuExit.addOnButtonPress( (Event e, Widget w){ Main.quit(); return true; } );

		mnuNextImage.addOnButtonPress( (Event e, Widget w){ actionPictureCycling(true); return true; } );
		mnuPrevImage.addOnButtonPress( (Event e, Widget w){ actionPictureCycling(false); return true; } );
		mnuNextImageToAnnotate.addOnButtonPress( (Event e, Widget w){ actionPictureCycling(true, true); return true; } );
		mnuPrevImageToAnnotate.addOnButtonPress( (Event e, Widget w){ actionPictureCycling(false, true); return true; } );

		mnuNextAnnotation.addOnButtonPress( (Event e, Widget w){ actionAnnotationCycling(true); return true; } );

		mnuPrevAnnotation.addOnButtonPress( (Event e, Widget w){ actionAnnotationCycling(false); return true; } );
		mnuAddAnnotation.addOnButtonPress( (Event e, Widget w){ actionStartDrawing(true); return true; } );

		mnuToggleZoom.addOnButtonPress( (Event e, Widget w){ actionToggleZoom(); return true; } );
		mnuCancelAnnotation.addOnButtonPress( (Event e, Widget w){ actionEditingMode(); return true; } );
		mnuDeleteAnnotation.addOnButtonPress( (Event e, Widget w){ actionDeleteRect(); return true; } );

		mnuUndo.addOnButtonPress( (Event e, Widget w){ actionUndo(); return true; } );
		mnuUndo.addOnButtonPress( (Event e, Widget w){ actionRedo(); return true; } );

		mnuGuides.addOnButtonPress( (Event e, Widget w){ actionToggleGuides(); return true; } );

		mnuSetCurrentLabel.addOnButtonPress( (Event e, Widget w){ search.setText(""); actionSearchLabel(""); wndLabels.showAll(); return true; } );

		mnuAbout.addOnButtonPress( (Event e, Widget w){ wndAbout.showAll(); return true; } );
		mnuTutorial.addOnButtonPress( (Event e, Widget w){ browse("https://github.com/trikko/etichetta/blob/main/HOWTO.md"); return true; } );

		mnuAI.addOnButtonPress( (Event e, Widget w){ actionShowAISettings(); return true; } );

		readLabels();
		addWorkingDirectoryChangeCallback( (dir) { mnuAuto.setSensitive(false); readLabels(); } );

		lstLabels.addOnRowActivated( (path, col, tv) {

			auto sel = lstLabels.getSelection().getSelected;
			if (sel && sel.userData !is null)
			{
				auto val = store.getValue(sel, 2).get!uint;
				actionChangeLabel(val);
				wndLabels.hide();
			}

		});

		store = new TreeStore([GType.OBJECT, GType.STRING, GType.UINT]);

		import gtk.TreeIter;
		import gtk.TreeViewColumn;

		import pango.PgFontDescription;
		wndLabels.addOnFocusOut( (Event e, Widget w) { wndLabels.hide(); return true; } );

		lstLabels.appendColumn(new TreeViewColumn("Color",new CellRendererPixbuf(), "pixbuf", 0));
		lstLabels.appendColumn(new TreeViewColumn("Label",new CellRendererText(), "text", 1));
		lstLabels.setModel(store);
		lstLabels.setHeadersVisible(false);

		import gdk.Color : GdkColorspace;
		import gtk.CssProvider;
		import gtk.StyleContext;

		CssProvider css = new CssProvider();
		css.loadFromData("treeview { padding:10px; font-size: 15px;} ");

		StyleContext.addProviderForScreen(mainWindow.getScreen(), css, 800);

		search.addOnChanged( (e) { actionSearchLabel(search.getText().strip); } );

		search.addOnKeyPress( (Event e, Widget w) {
			if (e.key().keyval == GdkKeysyms.GDK_Return)
			{
				auto sel = lstLabels.getSelection().getSelected;
				if (sel)
				{
					auto val = store.getValue(sel, 2).get!uint;

					actionChangeLabel(val);
					wndLabels.hide();
					return true;
				}
			}
			else if (e.key.keyval == GdkKeysyms.GDK_Escape)
			{
				// Close popup if esc is pressed while the search is empty
				if (search.getText().empty())
				{
					wndLabels.hide();
					return true;
				}

				search.setText("");
			}
			else if (e.key.keyval == GdkKeysyms.GDK_Down)
			{
				auto sel = lstLabels.getSelection().getSelected;
				store.iterNext(sel);
				lstLabels.getSelection().selectIter(sel);
				return true;
			}
			else if (e.key.keyval == GdkKeysyms.GDK_Up)
			{
				auto sel = lstLabels.getSelection().getSelected;
				store.iterPrevious(sel);
				lstLabels.getSelection().selectIter(sel);
				return true;
			}

			return false;
		});


		addStatusChangeCallback(
			(s)
			{
				points.length = 0;

				mnuDeleteAnnotation.setSensitive(s == State.EDITING && Picture.rects.length > 0);
				mnuCancelAnnotation.setSensitive(s == State.ANNOTATING);
				mnuNextAnnotation.setSensitive(s == State.EDITING && Picture.rects.length > 1);
				mnuPrevAnnotation.setSensitive(s == State.EDITING && Picture.rects.length > 1);
				mnuUndo.setSensitive(s == State.ANNOTATING && points.length > 0);

				if (s == State.ANNOTATING)
				{
					mainWindow.setCursor(pencil);
					mnuRedo.setSensitive(false);
					mnuUndo.setSensitive(points.length > 0);
				}
				else
				{
					updateHistoryMenu();
					mainWindow.setCursor(standard);
				}
			}
		);

		// Preload cursors
		standard = new Cursor(canvas.getDisplay(), "default");
		hand = new Cursor(canvas.getDisplay(), "grab");
		handClosed = new Cursor(canvas.getDisplay(), "grabbing");
		editing = new Cursor(CursorType.DOT);

		directions = [
			new Cursor(canvas.getDisplay(), "nw-resize"),
			new Cursor(canvas.getDisplay(), "row-resize"),
			new Cursor(canvas.getDisplay(), "ne-resize"),
			new Cursor(canvas.getDisplay(), "col-resize"),
			new Cursor(canvas.getDisplay(), "se-resize"),
			new Cursor(canvas.getDisplay(), "row-resize"),
			new Cursor(canvas.getDisplay(), "sw-resize"),
			new Cursor(canvas.getDisplay(), "col-resize")
		];

		pencil = new Cursor(CursorType.PENCIL);
	}
}