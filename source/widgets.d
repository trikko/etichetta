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
import gtk.Button;

import gtk.Main, gtk.Builder, gtk.Window, gtk.DrawingArea, gtk.EventBox, gtk.Button, gtk.CheckButton, gtk.Adjustment,
   gtk.CheckMenuItem, gtk.MenuItem, gtk.Entry, gtk.TreeView, gtk.Dialog, gtk.Image, gtk.FileChooserButton;
   import gtk.Adjustment;
   import gtk.ProgressBar;

mixin GtkAttributes;

@ui Window   		   wndLabels;
@ui Dialog           wndAbout;
@ui Window   		   mainWindow;
@ui Dialog           wndAI;
@ui Window           wndResize;

@ui ProgressBar      pbResize;
@ui Button           btnResizeCancel;
@ui Button           btnResize;
@ui FileChooserButton fileImagesDir;
@ui Entry            maxImageDimension;

@ui DrawingArea	   canvas;

@ui EventBox 		   evtLayer;

@ui CheckMenuItem		mnuZoomOnExit;
@ui CheckMenuItem		mnuGuides;

@ui Adjustment       adjOverlapping;
@ui Adjustment       adjConfidence;

@ui MenuItem		   mnuExit;
@ui MenuItem		   mnuOpen;
@ui MenuItem         mnuReload;
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
@ui MenuItem		   mnuRedo;
@ui MenuItem		   mnuSetCurrentLabel;
@ui MenuItem		   mnuAbout;
@ui MenuItem         mnuTutorial;

@ui MenuItem         mnuAuto;
@ui MenuItem         mnuAI;

@ui MenuItem         mnuResize;

@ui MenuItem         mnuCopyAll;
@ui MenuItem         mnuCopy;
@ui MenuItem         mnuPaste;
@ui MenuItem         mnuCloneLast;

@ui Button           btnAICancel;
@ui Button           btnAIOk;
@ui Button           btnWebsite;
@ui Button           btnDonate;
@ui Image            imgLogo;

@ui FileChooserButton fileAIModel;
@ui FileChooserButton fileAILabels;

@ui CheckButton      chkAIGpu;

@ui Entry			   search;
@ui TreeView		   lstLabels;

struct Widgets
{
   static reinit()
   {
      Builder b = new Builder();
		b.addFromString(LAYOUT);
		b.bindWidgets!widgets;
   }
}