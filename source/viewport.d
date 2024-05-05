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

module viewport;

import common;
import gdk.Pixbuf;
import std.algorithm : max, min;
import picture;

// The viewport of the picture
struct ViewPort
{
	static:

	Pixbuf	pixbuf;

	Point		roiTopLeft;			// In the picture coords space
	Point		roiBottomRight;	// In the picture coords space

	int		width;
	int		height;

	double	scale = 1.0;			// Scale factor: 2.0 means that the image is zoomed 2x.
	bool		invalidated = true;	// If true, the rendered pixbuf must be regenerated

	// Center the image in the viewport if image is smaller than the viewport
	int		offsetX = 0;
	int 		offsetY = 0;

	// Create a pixbuf from the current one. The pixbuf is cropped and scaled to fit the viewport
	Pixbuf view()
	{
		assert(Picture.pixbuf !is null);

		// Cache the result
		static Pixbuf result;

		if (!invalidated)
			return result;


		if (pixbuf !is null)
			pixbuf.unref();

		// Calculate the crop area and expand it to fit the viewport proportions
		double minCropW = roiBottomRight.x - roiTopLeft.x;
		double minCropH = roiBottomRight.y - roiTopLeft.y;

		double vpScale = 1.0 * width / height;

		double adjustedCropW = minCropW;
		double adjustedCropH = minCropW / vpScale;

		if (adjustedCropH < minCropH)
		{
			adjustedCropH = minCropH;
			adjustedCropW = minCropH * vpScale;
		}

		// Expand the crop area to fit the right proportions
		roiBottomRight.x += (adjustedCropW - minCropW) / 2;
		roiBottomRight.y += (adjustedCropH - minCropH) / 2;

		roiTopLeft.x -= (adjustedCropW - minCropW) / 2;
		roiTopLeft.y -= (adjustedCropH - minCropH) / 2;

		// Check bounds
		roiTopLeft.x = max(roiTopLeft.x, 0);
		roiTopLeft.y = max(roiTopLeft.y, 0);

		roiBottomRight.x = min(roiBottomRight.x, Picture.width);
		roiBottomRight.y = min(roiBottomRight.y, Picture.height);

		// Crop the original picture
		Pixbuf cropped = Picture.pixbuf.newSubpixbuf(
			cast(int)roiTopLeft.x,
			cast(int)roiTopLeft.y,
			cast(int)(roiBottomRight.x - roiTopLeft.x),
			cast(int)(roiBottomRight.y - roiTopLeft.y)
		);

		// Scale cropped to fit the viewport
		double scaledW = cast(double)(cropped.getWidth) / width;
		double scaledH = cast(double)(cropped.getHeight) / height;

		scale = 1.0 / max(scaledW, scaledH);

		// Cache the result. If it's an upscale, use bilinear interpolation, otherwise use nearest. We want to see the pixels!
		result = cropped.scaleSimple(
			cast(int)(cropped.getWidth * scale),
			cast(int)(cropped.getHeight * scale),
			scale < 1 ? InterpType.BILINEAR : InterpType.NEAREST
		);

		offsetX = (width - result.getWidth) / 2;
		offsetY = (height - result.getHeight) / 2;

		invalidated = false;
		return result;
	}
}