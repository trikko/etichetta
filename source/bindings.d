module bindings;

import std;
import actions;
import gtkattributes;
import gtk.Main, gtk.Window, gtk.DrawingArea, gtk.EventBox, gtk.CheckMenuItem, gtk.MenuItem, gtk.Entry, gtk.TreeView;
import gdk.Pixbuf;

import gdk.Event, gtk.Widget, gtk.Builder;

mixin GtkAttributes;

immutable static LAYOUT = import("layout.glade");

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


void bindActions()
{
   Builder b = new Builder();
   b.addFromString(LAYOUT);
   b.bindAll!bindings;

   mainWindow.addOnDelete( (Event e, Widget w){ Main.quit(); return true; } );
	mainWindow.showAll();

   // Bind events
	canvas.addOnDraw(toDelegate(&onDraw));

	evtLayer.addOnButtonPress(toDelegate(&onClick));			// Click on image
	evtLayer.addOnMotionNotify(toDelegate(&onMotion));		// Mouse move on image

	mainWindow.addOnKeyRelease(toDelegate(&onKeyRelease));	// Key release
	mainWindow.addOnKeyPress(toDelegate(&onKeyPress));			// Key press

	mnuOpen.addOnButtonPress(toDelegate(&actionOpenDir));				// Open a directory

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

	mnuUndo.addOnButtonPress( (Event e, Widget w){ actionUndoLastPoint(); return true; } );
	mnuGuides.addOnButtonPress( (Event e, Widget w){ actionToggleGuides(); return true; } );

	mnuSetCurrentLabel.addOnButtonPress( (Event e, Widget w){ search.setText(""); actionSearchLabel(""); wndLabels.showAll(); return true; } );

}

