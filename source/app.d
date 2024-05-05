import std;
import std.digest.crc;

import   gtk.Main, gtk.Button, gtk.CheckButton, gtk.ComboBoxText, gtk.TreeStore, gtk.IconView, gtk.DrawingArea, gtk.FileChooserDialog, gtk.TreeView,
         gtk.ToggleButton, gtk.TreeView, gtk.Grid, gtk.Frame, gtk.Image, gtk.EventBox, gtk.MenuItem, gtk.CheckMenuItem, gtk.CellRendererText, gtk.CellRendererPixbuf,
         gtk.Adjustment, gtk.Window, gtk.MainWindow, gtk.Widget, gtk.ListStore, gtk.Container, gtk.EntryCompletion, gtk.Entry, gtk.TreePath, gtk.TreeViewColumn;

import gdk.Keysyms, gdk.Cairo, gdk.Color, gdk.Cursor, gdk.Event,gdk.Pixbuf;
import cairo.Context;

// Ui binding
import gtk.SearchEntry;
import gtk.EntryCompletion;

import bindings;
import actions;
import viewport;
import picture;
import common;

TreeStore			store;

string 	currentWorkingDirectory;

// Some different colors for the labels
static immutable defaultLabelColors = [
	[0, 0.301961, 0.262745],
	[1.0, 1.0, 0.0],
	[0.109804, 0.901961, 1],
	[1, 0.290196, 0.27451],
	[1, 0.203922, 1],
	[1, 0.858824, 0.898039],
	[0, 0.435294, 0.65098],
	[0, 0.537255, 0.254902],
	[0.639216, 0, 0.34902],
	[0.478431, 0.286275, 0],
	[0, 0, 0.65098],
	[0.388235, 1, 0.67451],
	[0.717647, 0.592157, 0.384314],
	[0.560784, 0.690196, 1],
	[0.6, 0.490196, 0.529412],
	[0.352941, 0, 0.027451],
	[0.501961, 0.588235, 0.576471],
	[0.996078, 1, 0.901961],
	[0.105882, 0.266667, 0],
	[0.309804, 0.776471, 0.00392157],
	[0.231373, 0.364706, 1],
	[0.290196, 0.231373, 0.32549],
	[1, 0.184314, 0.501961],
	[0.380392, 0.380392, 0.352941],
	[0.729412, 0.0352941, 0],
	[0.419608, 0.47451, 0],
	[0, 0.760784, 0.627451],
	[1, 0.666667, 0.572549],
	[1, 0.564706, 0.788235],
	[0.72549, 0.0117647, 0.666667],
	[0.819608, 0.380392, 0],
	[0.866667, 0.937255, 1]
];


string[]			labels;
Point[] 			points;
int				label = 1;

Point[] 			zoomLines;
bool				isZooming = false;

bool isGrabbing = false;
bool showGuides = false;
int  grabIndex = -1;


Point lastMouseCoords;




version(Windows)
{
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

	currentWorkingDirectory = buildPath(dirName(args[0]), "example");
   Main.init(args);

	bindActions();
	initCommon();

	// Fill the list of available pictures
	if (!readPicturesDir())
	{
		Main.quit();
		return 1;
	}

	readLabels();



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




	Main.run();
	return 0;
}



void readLabels()
{
	labels.length = 0;

	string file = buildPath(currentWorkingDirectory, "labels.txt");
	if (!exists(file)) file = buildPath(currentWorkingDirectory, "classes.txt");

	if (!exists(file))
	{
		warning("No labels.txt or classes.txt found. Labels text will be not available.");
		return;
	}

	labels = [""] ~ readText(file).splitter("\n").filter!(a => a.length > 0).map!(x => x.strip).array;
}

bool readPicturesDir()
{
	Picture.list.length = 0;

	foreach(f; dirEntries(buildPath(currentWorkingDirectory, "images"), SpanMode.shallow))
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

	ViewPort.roiTopLeft = topLeft;
	ViewPort.roiBottomRight = bottomRight;
	ViewPort.invalidated = true;
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

	topLeft.x = topLeft.x / ViewPort.scale + ViewPort.roiTopLeft.x;
	topLeft.y = topLeft.y / ViewPort.scale + ViewPort.roiTopLeft.y;
	bottomRight.x = bottomRight.x / ViewPort.scale + ViewPort.roiTopLeft.x;
	bottomRight.y = bottomRight.y / ViewPort.scale + ViewPort.roiTopLeft.y;

	return zoomToArea(topLeft, bottomRight, padding);
}

bool isZoomedIn() { return !(ViewPort.roiBottomRight.x - ViewPort.roiTopLeft.x == Picture.width && ViewPort.roiBottomRight.y - ViewPort.roiTopLeft.y == Picture.height); }

void resetZoom()
{
	ViewPort.roiTopLeft = Point(0, 0);
	ViewPort.roiBottomRight = Point(Picture.width, Picture.height);
	ViewPort.invalidated = true;
	canvas.queueDraw();
}




