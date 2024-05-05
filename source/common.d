module common;
import gdk.Cursor;


enum State
{
	EDITING,
	DRAWING
}

// A point in the picture space, normalized to [0,1]
struct Point
{
	double x = double.max;
	double y = double.max;
}

struct Rectangle
{
	Point p1 = Point(double.max, double.max);
	Point p2 = Point(-double.max, -double.max);
	int label = 1;
}


Cursor standard;
Cursor pencil;
Cursor hand;
Cursor handClosed;
Cursor editing;
Cursor[] directions;

private State _status = State.EDITING;

void initCommon()
{
   import bindings : canvas;

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

State status() { return _status; }
void status(State s)
{
   import bindings;
   import picture : Picture;
   import app : points;

	Cursor cursor;
	if (s == State.DRAWING) cursor = pencil;
	else cursor = standard;

	mnuDeleteAnnotation.setSensitive(s == State.EDITING && Picture.rects.length > 0);
	mnuCancelAnnotation.setSensitive(s == State.DRAWING);
	mnuNextAnnotation.setSensitive(s == State.EDITING && Picture.rects.length > 1);
	mnuPrevAnnotation.setSensitive(s == State.EDITING && Picture.rects.length > 1);
	mnuUndo.setSensitive(s == State.DRAWING && points.length > 0);

	mainWindow.setCursor(cursor);
	_status = s;
	points.length = 0;
}