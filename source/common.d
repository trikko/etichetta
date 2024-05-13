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

module common;

import std.algorithm : each;

immutable VERSION_STRING = "v0.1.4";

enum State
{
	EDITING,
	ANNOTATING
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

	int 	label = 0;
	float score = float.max;
}

// Some different colors for the labels
static immutable defaultLabelColors = [
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
	[0.866667, 0.937255, 1],
	[0, 0.301961, 0.262745],
];

alias StatusChangeCallback 				= void delegate(State);
alias WorkingDirectoryChangeCallback 	= void delegate(string);

private StatusChangeCallback[]   			_statusCallback;
private WorkingDirectoryChangeCallback[]	_workingDirectoryCallback;

private State 	_status 					= State.EDITING;
private string _workingDirectory		= string.init;

State    status()          { return _status; }
void     status(State s)   { _status = s;  _statusCallback.each!(cb => cb(s)); }

void     addStatusChangeCallback(StatusChangeCallback cb) { _statusCallback ~= cb; }

void 		reloadDirectory() 				{ _workingDirectoryCallback.each!(cb => cb(workingDirectory)); }
void 		workingDirectory(string dir) 	{ _workingDirectory = dir; _workingDirectoryCallback.each!(cb => cb(dir)); }
string 	workingDirectory() 				{ return _workingDirectory; }

void 		addWorkingDirectoryChangeCallback(WorkingDirectoryChangeCallback cb) { _workingDirectoryCallback ~= cb; }