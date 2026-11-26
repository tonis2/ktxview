<*
 What the menus, the shortcuts and the panels do. Each command changes the
 app or the view, then says what it changed (`changed`), so the panels that
 read it are rebuilt and the canvas repaints.
*>
module ktxview::ui;
import ktxview::app, ktxview::layers;
import cui, cui::widgets;
import std::core::string;
import std::math;

<* What a command changed. *>
enum Change : char
{
	<* Only the pictures: the canvas repaints. *>
	PICTURE,
	<* What the file offers or what is picked: the panels rebuild too. *>
	STRUCTURE,
}

<*
 Tell the interface the app changed.

 @param [&inout] ui : "The interface"
 @param change : "How far the change reaches"
*>
fn void changed(Ui* ui, Change change)
{
	ui.invalidate(Shell);
	if (change == STRUCTURE) ui.invalidate(app::AppState);
}

<* The shell the interface was built over. *>
macro Shell* shell_of(Ui* ui) => ui.inherit(Shell)!!;

<*
 Open a file, show it framed and remember it. A failure leaves the open file
 alone and puts the reason in the status line.

 @param [&inout] ui : "The interface"
 @param [in] path : "A .ktx2 file"
*>
fn void open_file(Ui* ui, String path)
{
	Shell* shell = shell_of(ui);
	if (try shell.app.open(path))
	{
		shell.frame_pending = true;
		shell.update_recent();
		if (shell.browse_dir.len) shell.browse_dir.free(mem);
		shell.browse_dir = parent_dir(path).copy(mem);
	}
	changed(ui, STRUCTURE);
}

fn String parent_dir(String path) @private
{
	sz? slash = path.rindex_of_char('/');
	if (catch slash) return "";
	return path[:slash];
}

<*
 Compare the open file with another, and show the difference.

 @param [&inout] ui : "The interface"
 @param [in] path : "A .ktx2 or .png"
*>
fn void compare_file(Ui* ui, String path)
{
	(void)shell_of(ui).app.compare_with(path);
	changed(ui, STRUCTURE);
}

fn void file_chosen(Ui* ui, String path) @private
{
	Shell* shell = shell_of(ui);
	if (try Element* dialog = ui.find_id("file_dialog")) dialog.widget_as(Dialog).set_open(dialog, false);
	switch (shell.pick)
	{
		case OPEN: open_file(ui, path);
		case COMPARE: compare_file(ui, path);
	}
}

fn void show_dialog(Ui* ui, Pick pick, String title) @private
{
	Shell* shell = shell_of(ui);
	Element* elem = ui.find_id("file_dialog")!!;
	Dialog* dialog = elem.widget_as(Dialog);
	shell.pick = pick;
	dialog.title = title;
	dialog.set_open(elem, true);
	shell.dialog_open = true;
}

fn void dialog_closed(Ui* ui) @private => shell_of(ui).dialog_open = false;

fn void cmd_open(Ui* ui) @private => show_dialog(ui, OPEN, "Open a KTX2 file");

fn void cmd_compare(Ui* ui) @private
{
	if (!shell_of(ui).app.has_doc) return;
	show_dialog(ui, COMPARE, "Compare with a KTX2 or PNG");
}

fn void cmd_stop_comparing(Ui* ui) @private
{
	shell_of(ui).app.close_compare();
	changed(ui, STRUCTURE);
}

fn void cmd_quit(Ui* ui) @private => shell_of(ui).quit = true;

fn void open_recent(Ui* ui, sz index) @private
{
	app::AppState* a = shell_of(ui).app;
	if (index >= a.recent.len()) return;
	// Opening reorders the list, so the path is copied first.
	@pool() { open_file(ui, a.recent[index].tcopy()); };
}

// A menu item's callback gets only the Ui, so each recent slot has its own.
const OnClick[app::MAX_RECENT] RECENT_OPENERS @private = {
	fn (ui) => open_recent(ui, 0), fn (ui) => open_recent(ui, 1),
	fn (ui) => open_recent(ui, 2), fn (ui) => open_recent(ui, 3),
	fn (ui) => open_recent(ui, 4), fn (ui) => open_recent(ui, 5),
	fn (ui) => open_recent(ui, 6), fn (ui) => open_recent(ui, 7),
};

<*
 Show a view in the pane that shows the canvas or the overview, or else in the first pane.

 @param [&inout] ui : "The interface"
 @param view : "What the pane should show"
*>
fn void show_view(Ui* ui, View view)
{
	Shell* shell = shell_of(ui);
	AreaNode* leaf = find_leaf(shell.areas.root, View.IMAGE) ?? find_leaf(shell.areas.root, View.OVERVIEW) ?? null;
	if (!leaf) leaf = first_leaf(shell.areas.root);
	if (leaf.active == view.ordinal) return;
	leaf.active = view.ordinal;
	if (try Element* host = ui.find(AreaHost)) host.request_build();
}

fn AreaNode*? find_leaf(AreaNode* node, View view) @private
{
	if (node.is_leaf()) return node.active == view.ordinal ? node : NO_LEAF~;
	return find_leaf(node.first, view) ?? find_leaf(node.second, view);
}

fn AreaNode* first_leaf(AreaNode* node) @private => node.is_leaf() ? node : first_leaf(node.first);

<*
 Whether any pane shows a view.

 @param [&inout] ui : "The interface"
 @param view : "The view to look for"
*>
fn bool showing(Ui* ui, View view) => @ok(find_leaf(shell_of(ui).areas.root, view));

fn void cmd_overview(Ui* ui) @private => show_view(ui, showing(ui, OVERVIEW) ? View.IMAGE : View.OVERVIEW);

fn void cmd_image_view(Ui* ui) @private
{
	show_view(ui, IMAGE);
	set_mode(ui, IMAGE);
}

fn void cmd_lit(Ui* ui) @private
{
	show_view(ui, IMAGE);
	set_mode(ui, shell_of(ui).app.mode == LIT ? app::Mode.IMAGE : app::Mode.LIT);
}

fn void cmd_diff(Ui* ui) @private
{
	show_view(ui, IMAGE);
	set_mode(ui, shell_of(ui).app.mode == DIFF ? app::Mode.IMAGE : app::Mode.DIFF);
}

fn void set_mode(Ui* ui, app::Mode mode) @private
{
	shell_of(ui).app.set_mode(mode);
	changed(ui, STRUCTURE);
}

fn void cmd_tile(Ui* ui) @private
{
	Shell* shell = shell_of(ui);
	shell.app.tiled = !shell.app.tiled;
	shell.frame_pending = true;
	changed(ui, STRUCTURE);
}

fn void cmd_frame(Ui* ui) @private
{
	shell_of(ui).frame_pending = true;
	changed(ui, PICTURE);
}

fn void cmd_actual(Ui* ui) @private
{
	shell_of(ui).actual_size();
	changed(ui, PICTURE);
}

// Steps wrap around, so ] on the last layer comes back to the first.
fn void step_layer(Ui* ui, int step) @private
{
	app::AppState* a = shell_of(ui).app;
	if (!a.has_doc) return;
	a.set_layer((uint)(((int)a.layer + (int)a.doc.layers + step) % (int)a.doc.layers));
	changed(ui, STRUCTURE);
}

fn void step_face(Ui* ui, int step) @private
{
	app::AppState* a = shell_of(ui).app;
	if (!a.has_doc) return;
	a.set_face((uint)(((int)a.face + (int)a.doc.faces + step) % (int)a.doc.faces));
	changed(ui, STRUCTURE);
}

fn void step_level(Ui* ui, int step) @private
{
	app::AppState* a = shell_of(ui).app;
	if (!a.has_doc) return;
	a.set_level((uint)math::clamp((int)a.level + step, 0, (int)a.doc.levels - 1));
	changed(ui, STRUCTURE);
}

fn void pick_channel(Ui* ui, layers::Channel channel) @private
{
	show_view(ui, IMAGE);
	shell_of(ui).app.set_channel(channel);
	changed(ui, STRUCTURE);
}

fn MenuItemFlags tile_state(Ui* ui) @private => { .checked = shell_of(ui).app.tiled };
fn MenuItemFlags lit_state(Ui* ui) @private => { .checked = shell_of(ui).app.mode == LIT, .disabled = !shell_of(ui).app.can_light() };
fn MenuItemFlags diff_state(Ui* ui) @private => { .checked = shell_of(ui).app.mode == DIFF, .disabled = !shell_of(ui).app.compare.loaded };
fn MenuItemFlags overview_state(Ui* ui) @private => { .checked = showing(ui, OVERVIEW) };
fn MenuItemFlags compare_state(Ui* ui) @private => { .disabled = !shell_of(ui).app.has_doc };
fn MenuItemFlags stop_state(Ui* ui) @private => { .disabled = !shell_of(ui).app.compare.loaded };

// Globals, not consts: a const array is copied to the stack where it is sliced,
// and the menus keep these slices.
MenuItem[*] file_items @private = {
	{ .label = "Open…", .shortcut = "Ctrl+O", .on_select = &cmd_open },
	{ .label = "Compare with…", .shortcut = "Ctrl+D", .on_select = &cmd_compare, .state = &compare_state },
	{ .label = "Stop comparing", .on_select = &cmd_stop_comparing, .state = &stop_state },
	{ .separator = true },
	{ .label = "Quit", .shortcut = "Ctrl+Q", .on_select = &cmd_quit },
};

MenuItem[*] view_items @private = {
	{ .label = "Image", .shortcut = "I", .on_select = &cmd_image_view },
	{ .label = "Overview", .shortcut = "O", .on_select = &cmd_overview, .state = &overview_state },
	{ .label = "Lit material", .shortcut = "M", .on_select = &cmd_lit, .state = &lit_state },
	{ .label = "Difference", .shortcut = "D", .on_select = &cmd_diff, .state = &diff_state },
	{ .separator = true },
	{ .label = "Tile 3×3", .shortcut = "T", .on_select = &cmd_tile, .state = &tile_state },
	{ .label = "Frame", .shortcut = "F", .on_select = &cmd_frame },
	{ .label = "Actual size", .shortcut = "1", .on_select = &cmd_actual },
};

MenuItem[*] image_items @private = {
	{ .label = "Next layer", .shortcut = "]", .on_select = fn (ui) => step_layer(ui, 1) },
	{ .label = "Previous layer", .shortcut = "[", .on_select = fn (ui) => step_layer(ui, -1) },
	{ .label = "Next face", .shortcut = "Shift+]", .on_select = fn (ui) => step_face(ui, 1) },
	{ .label = "Previous face", .shortcut = "Shift+[", .on_select = fn (ui) => step_face(ui, -1) },
	{ .label = "Smaller mip", .shortcut = ".", .on_select = fn (ui) => step_level(ui, 1) },
	{ .label = "Larger mip", .shortcut = ",", .on_select = fn (ui) => step_level(ui, -1) },
	{ .separator = true },
	{ .label = "Colour", .shortcut = "C", .on_select = fn (ui) => pick_channel(ui, RGB) },
	{ .label = "Colour and alpha", .shortcut = "C C", .on_select = fn (ui) => pick_channel(ui, RGBA) },
	{ .label = "Red", .shortcut = "R", .on_select = fn (ui) => pick_channel(ui, R) },
	{ .label = "Green", .shortcut = "G", .on_select = fn (ui) => pick_channel(ui, G) },
	{ .label = "Blue", .shortcut = "B", .on_select = fn (ui) => pick_channel(ui, B) },
	{ .label = "Alpha", .shortcut = "A", .on_select = fn (ui) => pick_channel(ui, A) },
};
