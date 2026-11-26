<*
 The image canvas: the preview drawn on a plane that pans and zooms, one
 texel to one plane unit, behind a clip. The wheel zooms at the pointer, a
 drag pans, and a drag with L held moves the lit view's light.

 Pan and zoom are the content transform (`View2D`, as NodeGraph uses it), so
 they cost one matrix write and no repaint. Past 1:1 the plane draws the
 nearest-filtered copy of the preview, so texels stay square.
*>
module ktxview::ui;
import ktxview::app, ktxview::layers;
import cui, cui::widgets;
import std::math;

const Color CANVAS_BACK = { 0.09, 0.09, 0.11, 1.0 };
const Color BLANK_TEXT = { 0.72, 0.74, 0.79, 1.0 };
<* How far a light drag must go, in screen pixels, to move the light across the whole disc's radius. *>
const float LIGHT_DRAG_PX = 250.0;

<* What the pointer is over on the canvas. *>
struct Hover
{
	bool on;
	<* Texel of the current level. *>
	uint x;
	uint y;
}

<* The canvas. Its view lives on the Shell, so a rebuilt pane keeps it. *>
struct ImageView (Widget)
{
	DragTracker drag;
	<* This drag moves the light rather than the view. *>
	bool lighting;
}

<* The plane under the view: the preview, once or 3×3, in plane units. *>
struct ImagePlane (Widget)
{
	Shell* shell;
}

fn void ImageView.mount(&self, Element* elem) @dynamic
{
	elem.set_cursor(CROSSHAIR);
	Shell* shell = elem.inherit(Shell)!!;
	elem.append(elem.ui.@node((ImagePlane) { .shell = shell }));
}

fn Vec2 ImageView.layout(&self, Element* elem, Constraints constraints) @dynamic
{
	elem.clips = true;
	Vec2 own = constraints.max;
	Shell* shell = elem.watch(Shell)!!;
	foreach (i, child : elem.children)
	{
		elem.layout_child(i, cui::tight(shell.plane_size()));
		elem.place_child(i, { 0, 0 });
	}
	shell.view_size = own;
	Vec2 plane = shell.plane_size();
	if (shell.frame_pending && own.x > 0 && own.y > 0)
	{
		shell.frame_pending = false;
		shell.frame(own);
	}
	else if (plane.x > 0 && shell.shown_plane.x > 0 && plane.x != shell.shown_plane.x)
	{
		shell.keep_size(plane);
	}
	if (plane.x > 0) shell.shown_plane = plane;
	elem.set_content_transform(shell.view.matrix());
	return own;
}

fn void ImageView.paint(&self, Element* elem, Painter* painter) @dynamic
{
	Shell* shell = elem.watch(Shell)!!;
	painter.rect({ 0, 0 }, elem.size, { .color = CANVAS_BACK });
	app::AppState* a = shell.app;
	if (!a.preview.is_empty()) return;
	float width = math::min(elem.size.x - 40.0f, 520.0f);
	if (width <= 0) return;
	TextStyle style = { .size = 15, .color = BLANK_TEXT };
	Vec2 box = elem.ui.text.measure_box(0, a.blank, style.size, width, WRAP);
	painter.text_box((elem.size - box) * 0.5f, a.blank, style, width, WRAP);
}

fn bool ImageView.on_mouse(&self, Element* elem, MouseEvent event) @dynamic
{
	Shell* shell = elem.inherit(Shell)!!;
	switch (event.kind)
	{
		case SCROLL:
			shell.view.zoom_at(event.pos, cui::wheel_zoom_factor(event.scroll, event.scroll_precise));
			shell.view_moved(elem);
			return true;
		case PRESS:
			if (event.button == RIGHT) return false;
			self.drag.press(event.pos, event.button);
			self.lighting = event.button == LEFT && elem.ui.input.key_down(L) && shell.app.mode == LIT;
			return true;
		case MOVE:
			Vec2 last = self.drag.last;
			shell.hover_at(event.pos);
			if (!self.drag.active()) return false;
			self.drag.move(event.pos);
			if (!self.drag.dragging()) return true;
			Vec2 step = event.pos - last;
			if (self.lighting)
			{
				shell.app.move_light(step.x / LIGHT_DRAG_PX, -step.y / LIGHT_DRAG_PX);
				changed(elem.ui, PICTURE);
				return true;
			}
			shell.view.pan_by(step);
			shell.view_moved(elem);
			return true;
		case RELEASE:
			if (!self.drag.active() || event.button != self.drag.button) return false;
			self.drag.release();
			return true;
	}
}

fn void ImageView.on_hover(&self, Element* elem, bool entered) @dynamic
{
	if (entered) return;
	elem.inherit(Shell)!!.hover.on = false;
}

fn Vec2 ImagePlane.layout(&self, Element* elem, Constraints constraints) @dynamic
{
	// The plane is drawn, never clicked: the canvas behind it takes the pointer.
	elem.ignores_pointer = true;
	return constraints.max;
}

fn void ImagePlane.paint(&self, Element* elem, Painter* painter) @dynamic
{
	Shell* shell = elem.watch(Shell)!!;
	app::Picture* p = &shell.app.preview;
	if (p.is_empty()) return;
	cui::Texture texture = shell.sharp ? shell.textures.sharp : shell.textures.smooth;
	Vec2 size = { p.width, p.height };
	uint tiles = shell.tiles();
	// A tile's antialiased edge lets the background through where two tiles
	// meet, which reads as a seam the texture doesn't have. Each tile reaches
	// one screen pixel under the next, so the edge blends with its neighbour.
	float reach = tiles > 1 ? 1.0f / shell.view.scale() : 0.0f;
	shell.painted_zoom = shell.view.scale();
	for (uint y = 0; y < tiles; y++)
	{
		for (uint x = 0; x < tiles; x++)
		{
			Vec2 grown = size + (Vec2){ x + 1 < tiles ? reach : 0, y + 1 < tiles ? reach : 0 };
			painter.rect({ x * size.x, y * size.y }, grown, { .color = cui::WHITE, .texture = texture });
		}
	}
}

<* How many times the preview repeats across: 3 when tiled, else 1. *>
fn uint Shell.tiles(&self) => self.app.tiled ? 3 : 1;

<* The plane's size, in plane units: the preview, times the tiling. *>
fn Vec2 Shell.plane_size(&self)
{
	app::Picture* p = &self.app.preview;
	return { (float)(p.width * self.tiles()), (float)(p.height * self.tiles()) };
}

<*
 Fit the whole plane in a viewport of a size.

 @param size : "The canvas, in pixels"
*>
fn void Shell.frame(&self, Vec2 size)
{
	Vec2 plane = self.plane_size();
	if (plane.x == 0) return;
	self.view.frame({ 0, 0, plane.x, plane.y }, size, 24, ZOOM_MAX);
	self.sharp = self.view.scale() > 1.0f;
}

<*
 Zoom so a plane of a new size covers the screen the old one did: a smaller
 mip level shows as big as the level before it, its texels bigger.

 @param plane : "The new plane size"
*>
fn void Shell.keep_size(&self, Vec2 plane)
{
	float before = self.view.scale();
	float after = math::clamp(before * self.shown_plane.x / plane.x, ZOOM_MIN, ZOOM_MAX);
	self.view.pan *= before / after;
	self.view.zoom = after;
	self.sharp = after > 1.0f;
}

<* Show the plane at one texel per screen pixel, its centre in the middle of the canvas. *>
fn void Shell.actual_size(&self)
{
	Vec2 plane = self.plane_size();
	self.view.zoom = 1;
	self.view.pan = plane * 0.5f - self.view_size * 0.5f;
	self.sharp = false;
}

<*
 Put the new view on the canvas, and repaint the plane when the zoom crossed
 1:1 or moved the tiles' overlap.

 @param [&inout] canvas : "The ImageView's element"
*>
fn void Shell.view_moved(&self, Element* canvas)
{
	canvas.set_content_transform(self.view.matrix());
	bool sharp = self.view.scale() > 1.0f;
	bool rezoomed = self.app.tiled && self.view.scale() != self.painted_zoom;
	if (sharp == self.sharp && !rezoomed) return;
	self.sharp = sharp;
	if (canvas.children.len()) canvas.children[0].request_paint();
}

<*
 Note the texel under a point of the canvas.

 @param pos : "Canvas pixels"
*>
fn void Shell.hover_at(&self, Vec2 pos)
{
	app::Picture* p = &self.app.preview;
	Vec2 at = self.view.to_plane(pos);
	Vec2 plane = self.plane_size();
	self.hover.on = !p.is_empty() && at.x >= 0 && at.y >= 0 && at.x < plane.x && at.y < plane.y;
	if (!self.hover.on) return;
	self.hover.x = (uint)at.x % p.width;
	self.hover.y = (uint)at.y % p.height;
}
