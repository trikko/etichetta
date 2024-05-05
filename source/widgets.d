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

module widgets;

import imports : LAYOUT;
import gtkattributes;

import gtk.Main, gtk.Builder, gtk.Window, gtk.DrawingArea, gtk.EventBox,
   gtk.CheckMenuItem, gtk.MenuItem, gtk.Entry, gtk.TreeView;

mixin GtkAttributes;

@ui Window   		   wndLabels;
@ui Window   		   mainWindow;

@ui DrawingArea	   canvas;

@ui EventBox 		   evtLayer;

@ui CheckMenuItem		mnuZoomOnExit;
@ui CheckMenuItem		mnuGuides;

@ui MenuItem		   mnuExit;
@ui MenuItem		   mnuOpen;
@ui MenuItem		   mnuNextImage;
@ui MenuItem 		   mnuPrevImage;
@ui MenuItem		   mnuNextImageToAnnotate;
@ui MenuItem 		   mnuPrevImageToAnnotate;
@ui MenuItem		   mnuNextAnnotation;
@ui MenuItem		   mnuPrevAnnotation;
@ui MenuItem		   mnuAddAnnotation;
@ui MenuItem		   mnuToggleZoom;
@ui MenuItem		   mnuCancelAnnotation;
@ui MenuItem		   mnuDeleteAnnotation;
@ui MenuItem		   mnuUndo;
@ui MenuItem		   mnuSetCurrentLabel;

@ui Entry			   search;
@ui TreeView		   lstLabels;

struct Widgets
{
   static reinit()
   {
      Builder b = new Builder();
		b.addFromString(LAYOUT);
		b.bindAll!widgets;
   }
}