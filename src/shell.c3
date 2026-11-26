<*
 The interface's state beside the app, and the window's frame: the shell
 holds the view, the workspace and the menus; the root lays out the menu bar,
 the toolbar, the panes and the status bar, and takes the shortcuts.

 The interface reads the app through two provided values: `AppState`, watched
 by the composites whose shape follows the file (the toolbar, the info panel,
 the overview), and `Shell`, watched by the canvas, which only repaints. A
 command changes the app and then says which of the two it touched (`changed`).
*>
module ktxview::ui;
import ktxview::app, ktxview::layers;
import cui, cui::widgets;
import std::collections::list;
import std::core::string;
import std::math;

<* The interface's font, compiled in so the binary runs from anywhere. *>
const char[*] FONT = $embed("../assets/DejaVuSans.ttf");

const Color TEXT = { 0.90, 0.91, 0.93, 1.0 };
const Color DIM = { 0.58, 0.60, 0.66, 1.0 };
const Color HEADING = { 1.0, 1.0, 1.0, 1.0 };
const Color BAR_BACK = { 0.15, 0.16, 0.19, 1.0 };
const Color BAR_LINE = { 0.26, 0.27, 0.32, 1.0 };
const Color PANEL_BACK = { 0.12, 0.13, 0.15, 1.0 };
const Color CELL_HOVER = { 0.22, 0.24, 0.30, 1.0 };

const float ZOOM_MIN = 0.01;
const float ZOOM_MAX = 4096.0;
<* Width of the key column in the info panel. *>
const float INFO_KEY_W = 128.0;
const Vec2 THUMB_CELL = { 196.0, 222.0 };

<* The panes' views, in the order the workspace registers them. *>
enum View : char
{
	IMAGE,
	INFO,
	OVERVIEW,
}

<* No pane shows the view asked for. *>
excuse NO_LEAF;

<* Which file the file dialog is picking. *>
enum Pick : char
{
	OPEN,
	COMPARE,
}

<* GPU textures the interface draws with. All NO_TEXTURE without a GPU, as in tests. *>
struct Textures
{
	<* The preview, filtered: for zooms up to 1:1. *>
	cui::Texture smooth;
	<* The preview, nearest: for zooms past 1:1. *>
	cui::Texture sharp;
	cui::Texture[app::MAX_THUMBS] thumbs;
}

<* What the interface keeps beside the app: the view, the workspace and the menus. *>
struct Shell
{
	<* Borrowed; outlives the Ui. *>
	app::AppState* app;
	View2D view;
	<* The canvas size at its last layout. *>
	Vec2 view_size;
	<* The plane size the view was last fitted to; a new one keeps its screen size. *>
	Vec2 shown_plane;
	<* Frame the image at the canvas's next layout. *>
	bool frame_pending;
	<* The view is past 1:1, so the canvas draws `textures.sharp`. *>
	bool sharp;
	<* The zoom the plane was last painted at; the tiles' overlap depends on it. *>
	float painted_zoom;
	Textures textures;
	Hover hover;
	bool quit;
	Pick pick;
	bool dialog_open;
	<* Where the file dialog opens. Owned. *>
	String browse_dir;
	AreaLayout areas;
	AreaView[View::len] views;
	Menu[4] menus;
	MenuItem[app::MAX_RECENT] recent_items;
}

<* Hand the shell its app and set up the workspace. Call `free()` after the Ui is gone. *>
fn void Shell.init(&self, app::AppState* a)
{
	*self = {
		.app = a,
		.view = { .zoom = 1, .zoom_min = ZOOM_MIN, .zoom_max = ZOOM_MAX },
		.frame_pending = true,
		.views = {
			{ .name = "Image", .build = &build_canvas },
			{ .name = "Info", .build = &build_info },
			{ .name = "Overview", .build = &build_overview },
		},
	};
	self.areas.init(self.views[..]);
	self.areas.split_leaf(self.areas.root, HORIZONTAL);
	self.areas.root.ratio = 0.24;
	self.areas.root.first.active = View.INFO.ordinal;
	self.areas.root.second.active = View.IMAGE.ordinal;
	self.menus = {
		{ "File", FILE_ITEMS[..] },
		{ "Recent", {} },
		{ "View", VIEW_ITEMS[..] },
		{ "Image", IMAGE_ITEMS[..] },
	};
	self.update_recent();
}

fn void Shell.free(&self)
{
	self.areas.free();
	if (self.browse_dir.len) self.browse_dir.free(mem);
}

<* Point the Recent menu at the app's list; call after the list changes. *>
fn void Shell.update_recent(&self)
{
	sz n = math::min(self.app.recent.len(), app::MAX_RECENT);
	for (sz i = 0; i < n; i++)
	{
		String path = self.app.recent[i];
		self.recent_items[i] = { .label = path, .on_select = RECENT_OPENERS[i] };
	}
	if (n == 0)
	{
		self.recent_items[0] = { .label = "No recent files", .disabled = true };
		n = 1;
	}
	self.menus[1].items = self.recent_items[:n];
}

// ---------------------------------------------------------------------------
// The root

<* The whole window, and the keyboard shortcuts. *>
struct AppRoot (Widget)
{
	<* Borrowed; outlives the Ui. *>
	Shell* shell;
}

fn Element* AppRoot.build(&self, Element* elem) @dynamic
{
	Ui* ui = elem.ui;
	Shell* shell = self.shell;
	return @subtree(ui)
	{
		@tree((Stack) { })
		{
			// The workspace, third, takes the height the bars leave.
			@tree((VDock) { .fill = 2 })
			{
				@node((MenuBar) { .menus = shell.menus[..] });
				@node((Toolbar) { });
				@node((AreaHost) { .areas = &shell.areas });
				status_bar();
			};
			@node((Dialog) {
				.title = "Open",
				.body = &build_file_browser,
				.modal = true,
				.close_outside = true,
				.on_close = &dialog_closed,
			}).with_id("file_dialog");
			@node((TooltipHost) { });
		};
	};
}

fn bool AppRoot.on_key(&self, Element* elem, KeyEvent event) @dynamic
{
	if (!event.down) return false;
	Ui* ui = elem.ui;
	Shell* shell = self.shell;
	Modifiers mods = ui.input.modifiers();
	if (mods.ctrl)
	{
		switch (event.key)
		{
			case Q: cmd_quit(ui);
			case O: if (!shell.dialog_open) cmd_open(ui);
			case D: if (!shell.dialog_open) cmd_compare(ui);
			default: return false;
		}
		return true;
	}
	if (shell.dialog_open || mods.alt || mods.super) return false;
	switch (event.key)
	{
		case LEFT_BRACKET:
			if (mods.shift)
			{
				step_face(ui, -1);
			}
			else
			{
				step_layer(ui, -1);
			}
		case RIGHT_BRACKET:
			if (mods.shift)
			{
				step_face(ui, 1);
			}
			else
			{
				step_layer(ui, 1);
			}
		case COMMA: step_level(ui, -1);
		case PERIOD: step_level(ui, 1);
		case R: pick_channel(ui, R);
		case G: pick_channel(ui, G);
		case B: pick_channel(ui, B);
		case A: pick_channel(ui, A);
		case C: pick_channel(ui, shell.app.channel == RGB && shell.app.mode == IMAGE ? layers::Channel.RGBA : layers::Channel.RGB);
		case I: cmd_image_view(ui);
		case O: cmd_overview(ui);
		case M: cmd_lit(ui);
		case D: cmd_diff(ui);
		case T: cmd_tile(ui);
		case F: cmd_frame(ui);
		case KEY_1: cmd_actual(ui);
		default: return false;
	}
	return true;
}

<*
 Build the interface over a shell and hand the keyboard to it. The Ui keeps
 pointers to the shell and its app, so both must outlive it.

 @param [&inout] ui : "A fresh Ui"
 @param [&inout] shell : "Initialised with its app"
*>
fn void build(Ui* ui, Shell* shell)
{
	ui.provide(shell);
	ui.provide(shell.app);
	// No flush here: a renderer has to make the glyph atlas before the first
	// paint, or the text painted then is cached without it.
	@canvas(ui)
	{
		@node((AppRoot) { .shell = shell });
	};
	if (try Element* root = ui.find(AppRoot)) root.request_focus();
}

<*
 Load the interface font into a Ui.

 @param [&inout] ui : "Before the first layout, so text is measured with it"
 @return? cui::Ui.load_font_bytes!
*>
fn void? load_font(Ui* ui)
{
	(void)ui.load_font_bytes(FONT[..])!;
}

// ---------------------------------------------------------------------------
// Layout pieces

<*
 Children stacked top to bottom at full width; the child at `fill` takes the
 height the others leave.
*>
struct VDock (Widget)
{
	sz fill;
}

fn Vec2 VDock.layout(&self, Element* elem, Constraints constraints) @dynamic
{
	Vec2 own = constraints.max;
	float used = 0;
	foreach (i, child : elem.children)
	{
		if (i == self.fill) continue;
		used += elem.layout_child(i, { .min = { own.x, 0 }, .max = { own.x, own.y } }).y;
	}
	float y = 0;
	foreach (i, child : elem.children)
	{
		if (i == self.fill) elem.layout_child(i, cui::tight({ own.x, math::max(own.y - used, 0.0f) }));
		elem.place_child(i, { 0, y });
		y += child.size.y;
	}
	return own;
}

<* A full-width strip with a background and a line under it, padded around one child. *>
struct Bar (Widget)
{
	Color color;
	Insets insets;
	<* Draw the line along the top instead of the bottom. *>
	bool line_on_top;
}

fn Vec2 Bar.layout(&self, Element* elem, Constraints constraints) @dynamic
{
	Vec2 pad = { self.insets.left + self.insets.right, self.insets.top + self.insets.bottom };
	Vec2 child;
	if (elem.children.len())
	{
		child = elem.layout_child(0, cui::loose({ math::max(constraints.max.x - pad.x, 0.0f), constraints.max.y }));
		elem.place_child(0, { self.insets.left, self.insets.top });
	}
	return constraints.constrain({ constraints.max.x, child.y + pad.y });
}

fn void Bar.paint(&self, Element* elem, Painter* painter) @dynamic
{
	painter.rect({ 0, 0 }, elem.size, { .color = self.color });
	painter.rect({ 0, self.line_on_top ? 0 : elem.size.y - 1 }, { elem.size.x, 1 }, { .color = BAR_LINE });
}

<* Strings a composite's built subtree borrows, freed when it builds again. *>
struct Strings
{
	List{String} list;
}

<*
 Keep a formatted string until the next clear.

 @param [in] fmt : "As string::format"
 @return "Borrowed: valid until clear()"
*>
fn String Strings.format(&self, String fmt, args...)
{
	if (!self.list.is_initialized()) self.list.init(mem);
	String s = string::format(mem, fmt, ...args);
	self.list.push(s);
	return s;
}

fn void Strings.clear(&self)
{
	foreach (s : self.list) s.free(mem);
	self.list.clear();
}

fn void Strings.free(&self)
{
	self.clear();
	self.list.free();
}
