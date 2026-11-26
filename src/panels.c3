<*
 The panels around the canvas: the toolbar of pickers, the info panel, the
 overview of every image, and the status line.
*>
module ktxview::ui;
import ktxview::app, ktxview::doc, ktxview::layers, ktxview::pixels;
import ktx::container, ktx::dfd, ktx::vk;
import cui, cui::widgets;
import std::core::string;
import std::math;

// ---------------------------------------------------------------------------
// Toolbar

<* The pickers above the workspace: layer, face, mip level, channel, tiling and view. *>
struct Toolbar (Widget)
{
	Strings texts;
	String[layers::MAX_LAYERS] layer_options;
	String[6] face_options;
	String[layers::Channel::len] channel_options;
	String[app::Mode::len] mode_options;
}

fn void Toolbar.unmount(&self, Element* elem) @dynamic => self.texts.free();

fn Element* Toolbar.build(&self, Element* elem) @dynamic
{
	Ui* ui = elem.ui;
	app::AppState* a = elem.watch(app::AppState)!!;
	self.texts.clear();
	if (!a.has_doc)
	{
		return @subtree(ui)
		{
			@tree((Bar) { .color = BAR_BACK, .insets = { 10, 7, 10, 7 } })
			{
				@node((Label) { .text = "No file open. File › Open (Ctrl+O), or drop a .ktx2 on the window.", .size = 13, .color = DIM });
			};
		};
	}

	doc::Document* d = &a.doc;
	sz layer_count = math::min((sz)d.layers, layers::MAX_LAYERS);
	for (sz i = 0; i < layer_count; i++)
	{
		self.layer_options[i] = self.texts.format("%s", a.layer_caption(tmem, (uint)i));
	}
	foreach (i, &option : self.channel_options) *option = a.channel_label(layers::Channel::from_ordinal(i));
	foreach (i, &option : self.face_options) *option = app::FACE_NAMES[i];
	app::Mode[app::Mode::len] modes;
	sz mode_count = a.modes(modes[..]);
	sz mode_index;
	for (sz i = 0; i < mode_count; i++)
	{
		self.mode_options[i] = modes[i].label;
		if (modes[i] == a.mode) mode_index = i;
	}

	return @subtree(ui)
	{
		@tree((Bar) { .color = BAR_BACK, .insets = { 10, 6, 10, 6 } })
		{
			@tree((Wrap) { .gap_x = 14, .gap_y = 6 })
			{
				if (layer_count > 1)
				{
					@tree(widgets::tip("Layer", "[ and ] step through the layers"))
					{
						@node((Segmented) { .options = self.layer_options[:layer_count], .selected = a.layer, .on_change = &layer_chosen }).with_id("layers");
					};
				}
				if (d.faces == 6)
				{
					@tree(widgets::tip("Cubemap face", "Shift+[ and Shift+] step through the faces"))
					{
						@node((Segmented) { .options = self.face_options[..], .selected = a.face, .on_change = &face_chosen }).with_id("faces");
					};
				}
				if (d.levels > 1)
				{
					@tree((Row) { .gap = 8, .cross_align = CENTER })
					{
						@tree(widgets::tip("Mip level", ", and . step through the levels"))
						{
							@node((Slider) {
								.label = "Mip",
								.value = (float)a.level,
								.min = 0,
								.max = (float)(d.levels - 1),
								.step = 1,
								.on_change = &level_slid,
								.size = { 300, 0 },
							}).with_id("mip");
						};
						@node((LiveLabel) { .text_of = &level_size_text, .size = { 96, 18 }, .text_size = 13, .color = DIM });
					};
				}
				@tree(widgets::tip("Channel", "C colour (twice: with alpha), R G B A one channel"))
				{
					@node((Segmented) {
						.options = self.channel_options[..],
						.selected = a.mode == IMAGE ? (sz)a.channel.ordinal : -1,
						.on_change = &channel_chosen,
					}).with_id("channels");
				};
				@tree(widgets::tip("Tile 3×3 to check the seams (T)"))
				{
					@node((ToggleButton) { .label = "Tile 3×3", .on = a.tiled, .on_change = &tile_toggled }).with_id("tile");
				};
				if (mode_count > 1)
				{
					@tree(widgets::tip("What the canvas shows", "M lit material, D difference"))
					{
						@node((Segmented) { .options = self.mode_options[:mode_count], .selected = mode_index, .on_change = &mode_chosen }).with_id("modes");
					};
				}
			};
		};
	};
}

fn void layer_chosen(Ui* ui, usz index) @private
{
	shell_of(ui).app.set_layer((uint)index);
	changed(ui, STRUCTURE);
}

fn void face_chosen(Ui* ui, usz index) @private
{
	shell_of(ui).app.set_face((uint)index);
	changed(ui, STRUCTURE);
}

// A drag passes through every level, so only the canvas follows it: rebuilding
// the toolbar would release the slider being dragged.
fn void level_slid(Ui* ui, float value) @private
{
	app::AppState* a = shell_of(ui).app;
	uint level = (uint)math::round(value);
	if (level == a.level) return;
	a.set_level(level);
	changed(ui, PICTURE);
}

fn String level_size_text(Element* elem) @private
{
	app::AppState* a = elem.inherit(app::AppState)!!;
	if (!a.has_doc) return "";
	return string::format(mem, "%d × %d", a.doc.level_width(a.level), a.doc.level_height(a.level));
}

fn void channel_chosen(Ui* ui, usz index) @private => pick_channel(ui, layers::Channel::from_ordinal(index));

fn void tile_toggled(Ui* ui, bool on) @private
{
	Shell* shell = shell_of(ui);
	shell.app.tiled = on;
	shell.frame_pending = true;
	changed(ui, PICTURE);
}

fn void mode_chosen(Ui* ui, usz index) @private
{
	app::Mode[app::Mode::len] modes;
	sz count = shell_of(ui).app.modes(modes[..]);
	if ((sz)index < count) set_mode(ui, modes[index]);
}

// ---------------------------------------------------------------------------
// Views

// The workspace's views and the file dialog's body: builders cui calls on every switch.
fn Element* build_canvas(Ui* ui) @private
{
	return @subtree(ui) { @node((ImageView) { }); };
}
fn Element* build_info(Ui* ui) @private
{
	return @subtree(ui) { @node((InfoPanel) { }); };
}
fn Element* build_overview(Ui* ui) @private
{
	return @subtree(ui) { @node((Overview) { .cell = THUMB_CELL }); };
}

fn Element* build_file_browser(Ui* ui) @private
{
	Shell* shell = shell_of(ui);
	String[] mask = shell.pick == OPEN ? open_mask[..] : compare_mask[..];
	return @subtree(ui)
	{
		@tree((Rectangle) { .size = { 640, 420 } })
		{
			@tree((Scroll) { })
			{
				@node((FileBrowser) { .mask = mask, .start = shell.browse_dir, .on_choose = &file_chosen }).with_id("browser");
			};
		};
	};
}

// Globals, not consts: a const array is copied to the stack where it is sliced,
// and the browser keeps the slice.
String[*] open_mask @private = { "*.ktx2" };
String[*] compare_mask @private = { "*.ktx2", "*.png" };

// ---------------------------------------------------------------------------
// Info panel

<* One line of the info panel: a dim key, and its value cut to fit. *>
struct InfoRow (Widget)
{
	<* Borrowed, like every string in a widget. *>
	String key;
	String value;
}

fn Vec2 InfoRow.layout(&self, Element* elem, Constraints constraints) @dynamic
	=> constraints.constrain({ constraints.max.x, 20 });

fn void InfoRow.paint(&self, Element* elem, Painter* painter) @dynamic
{
	painter.text({ 0, 2 }, self.key, { .size = 13, .color = DIM });
	float room = math::max(elem.size.x - INFO_KEY_W, 0.0f);
	painter.text_box({ INFO_KEY_W, 2 }, self.value, { .size = 13, .color = TEXT }, room, ELLIPSIS);
}

fn void InfoRow.describe(&self, Element* elem, Description* out) @dynamic
{
	out.text = self.key;
	out.value = self.value;
}

<* Everything the file says about itself. *>
struct InfoPanel (Widget)
{
	Strings texts;
	<* The level index is folded away until asked for; a rebuild keeps the choice. *>
	bool levels_open;
}

fn void InfoPanel.unmount(&self, Element* elem) @dynamic => self.texts.free();

fn Element* InfoPanel.build(&self, Element* elem) @dynamic
{
	Ui* ui = elem.ui;
	app::AppState* a = elem.watch(app::AppState)!!;
	self.texts.clear();
	return @subtree(ui)
	{
		@tree((Rectangle) { .style = { .color = PANEL_BACK } })
		{
			@tree((Scroll) { })
			{
				@tree((Padding) { .insets = { 12, 10, 12, 12 } })
				{
					@tree((Column) { .gap = 4 })
					{
						if (!a.has_doc)
						{
							@node((Label) { .text = "No file open.", .size = 14, .color = DIM });
						}
						else
						{
							info_rows(self, a);
						}
					};
				};
			};
		};
	};
}

fn void row(String key, String value) @private => @node((InfoRow) { .key = key, .value = value });

fn void heading(String text) @private
{
	@tree((Padding) { .insets = { 0, 10, 0, 2 } })
	{
		@node((Label) { .text = text, .size = 14, .color = HEADING });
	};
}

// The rows for an open file, built into the enclosing scope.
fn void info_rows(InfoPanel* panel, app::AppState* a) @private
{
	doc::Document* d = &a.doc;
	container::FileInfo* info = &d.info;
	Strings* t = &panel.texts;

	@node((Label) { .text = d.name(), .size = 16, .color = HEADING, .overflow = ELLIPSIS });
	row("File size", t.format("%s (%d bytes)", human(tmem, (ulong)info.file_size), info.file_size));

	heading("Format");
	row("Format", t.format("%s", doc::format_name(tmem, info)));
	row("vkFormat", t.format("%s (%d)", vk::name(info.vk_format), info.vk_format));
	row("Size", info.depth > 0
		? t.format("%d × %d × %d", info.width, info.height, info.depth)
		: t.format("%d × %d", info.width, max(info.height, 1u)));
	row("Levels", info.level_count == 0 ? "1 (generate at load)" : t.format("%d", info.level_count));
	row("Layers", info.layer_count == 0 ? "not an array" : t.format("%d", info.layer_count));
	row("Faces", info.face_count == 6 ? "6 (cubemap)" : t.format("%d", info.face_count));
	row("Supercompression", t.format("%s", container::scheme_name(info.scheme)));
	switch (info.dfd_status)
	{
		case PARSED:
			dfd::Info f = info.dfd;
			row("DFD model", t.format("%s", dfd::model_name(f.model)));
			row("Transfer", f.transfer == dfd::TRANSFER_SRGB ? "sRGB" : "linear");
			row("Primaries", f.primaries == dfd::PRIMARIES_BT709 ? "BT.709" : t.format("%d", f.primaries));
			row("Block", t.format("%d × %d × %d, %d bytes", f.block_w, f.block_h, f.block_d, f.bytes_plane0));
		case BAD:
			row("DFD", "malformed");
		case MISSING:
			row("DFD", "missing");
	}
	row("Decodes", d.codec == NONE ? t.format("not yet: %s", d.cannot_decode) : "yes, to RGBA8");

	heading("GPU memory");
	row("BC7 / ASTC 4×4", t.format("%s", human(tmem, d.gpu_bytes(BLOCK_4X4))));
	row("RGBA8", t.format("%s", human(tmem, d.gpu_bytes(RGBA8))));

	if (d.named)
	{
		heading("Layers (three.layers)");
		for (sz i = 0; i < d.names.count; i++)
		{
			layers::Layer* l = &d.names.layers[i];
			row(t.format("Layer %d", i), t.format("%s%s", l.space.word.len ? l.space.word : "(no space)", describe_names(tmem, l)));
		}
	}

	if (info.kv.len)
	{
		heading("Metadata");
		foreach (&pair : info.kv)
		{
			String? text = pair.text();
			String value = t.format("%s", text ?? string::tformat("(%d bytes)", pair.value.len));
			@tree((Disclosure) { .label = pair.key, .expanded = true, .style = DISCLOSURE })
			{
				@node((Label) { .text = value, .size = 13, .color = TEXT, .overflow = WRAP });
			};
		}
	}

	heading("Level index");
	@tree((Disclosure) { .label = t.format("%d levels", info.levels.len), .expanded = panel.levels_open, .style = DISCLOSURE, .on_change = &levels_toggled })
	{
		@tree((Column) { .gap = 2 })
		{
			foreach (l, entry : info.levels)
			{
				row(t.format("%d: %d × %d", l, d.level_width((uint)l), d.level_height((uint)l)),
					t.format("%s (%s inflated)", human(tmem, entry.length), human(tmem, entry.uncompressed)));
			}
		};
	};

	if (a.compare.loaded)
	{
		heading("Compare");
		app::Compare* c = &a.compare;
		row("With", c.path);
		if (c.measured)
		{
			foreach (i, db : c.psnr.db)
			{
				row(t.format("PSNR %s", CHANNEL_NAMES[i]), db == double::inf ? "identical" : t.format("%.2f dB", db));
			}
		}
	}
}

const String[4] CHANNEL_NAMES @private = { "R", "G", "B", "A" };

fn void levels_toggled(Ui* ui, bool open) @private
{
	ui.@each(InfoPanel; panel) { panel.widget_as(InfoPanel).levels_open = open; };
}

const DisclosureStyle DISCLOSURE @private = {
	.background = { 0.15, 0.16, 0.19, 1.0 },
	.header = { 0.18, 0.19, 0.23, 1.0 },
	.header_hover = { 0.23, 0.24, 0.30, 1.0 },
	.border = { 0.26, 0.27, 0.32, 1.0 },
	.text = { 0.90, 0.91, 0.93, 1.0 },
	.mark = { 0.72, 0.74, 0.79, 1.0 },
	.radius = { 4.0, 4.0, 4.0, 4.0 },
	.header_height = 26.0,
	.text_size = 13.0,
	.padding = 8.0,
	.gap = 6.0,
	.border_width = 1.0,
};

// A layer's channel names as " rgb=basecolor a=height".
fn String describe_names(Allocator allocator, layers::Layer* l) @private
{
	DString out;
	out.init(allocator);
	foreach (i, name : l.names)
	{
		if (name.len) out.appendf(" %s=%s", layers::Channel::from_ordinal(i).group, name);
	}
	return out.str_view();
}

// A byte count the way people read it: "1.9 MiB".
fn String human(Allocator allocator, ulong bytes) @private
{
	if (bytes < 1024) return string::format(allocator, "%d B", bytes);
	if (bytes < 1024 * 1024) return string::format(allocator, "%.1f KiB", bytes / 1024.0);
	if (bytes < 1024 * 1024 * 1024) return string::format(allocator, "%.1f MiB", bytes / (1024.0 * 1024.0));
	return string::format(allocator, "%.2f GiB", bytes / (1024.0 * 1024.0 * 1024.0));
}

// ---------------------------------------------------------------------------
// Overview

<* Every layer and face of the file, as colour and as alpha: the contact sheet. *>
struct Overview (Widget)
{
	<* One thumbnail and its caption. *>
	Vec2 cell;
}

fn Element* Overview.build(&self, Element* elem) @dynamic
{
	Ui* ui = elem.ui;
	app::AppState* a = elem.watch(app::AppState)!!;
	a.build_thumbs();
	String note = "";
	if (!a.has_doc)
	{
		note = "No file open.";
	}
	else if (a.doc.codec == NONE)
	{
		note = a.blank;
	}
	return @subtree(ui)
	{
		@tree((Rectangle) { .style = { .color = CANVAS_BACK } })
		{
			@tree((Scroll) { })
			{
				@tree((Padding) { .insets = { 16, 14, 16, 16 } })
				{
					@tree((Column) { .gap = 10 })
					{
						if (note.len)
						{
							@node((Label) { .text = note, .size = 14, .color = BLANK_TEXT, .overflow = WRAP });
						}
						else
						{
							@tree((Grid) { .cell = self.cell, .gap_x = 12, .gap_y = 12 })
							{
								for (sz i = 0; i < a.thumb_count; i++) @node((ThumbCell) { .index = i }).with_id(a.thumbs[i].caption);
							};
						}
					};
				};
			};
		};
	};
}

<* One thumbnail of the overview, with its caption. A click shows it in the canvas. *>
struct ThumbCell (Widget)
{
	sz index;
	bool hovered;
	bool held;
}

fn void ThumbCell.paint(&self, Element* elem, Painter* painter) @dynamic
{
	Shell* shell = shell_of(elem.ui);
	app::Thumb* thumb = &shell.app.thumbs[self.index];
	if (self.hovered) painter.rect({ 0, 0 }, elem.size, { .color = CELL_HOVER, .border_radius = { 6, 6, 6, 6 } });
	float side = elem.size.x - 8;
	Vec2 pic = { thumb.picture.width, thumb.picture.height };
	float scale = side / math::max(pic.x, pic.y);
	Vec2 size = pic * scale;
	painter.rect({ 4 + (side - size.x) * 0.5f, 4 + (side - size.y) * 0.5f }, size,
		{ .color = cui::WHITE, .texture = shell.textures.thumbs[self.index] });
	TextStyle style = { .size = 13, .color = TEXT };
	float w = elem.ui.text.measure(0, thumb.caption, style.size).x;
	painter.text_box({ math::max((elem.size.x - w) * 0.5f, 4.0f), side + 8 }, thumb.caption, style, elem.size.x - 8, ELLIPSIS);
}

fn void ThumbCell.on_hover(&self, Element* elem, bool entered) @dynamic
{
	self.hovered = entered;
	if (entered) elem.set_cursor(POINTING_HAND);
	elem.request_paint();
}

fn bool ThumbCell.on_mouse(&self, Element* elem, MouseEvent event) @dynamic
{
	if (event.button != LEFT) return false;
	switch (event.kind)
	{
		case PRESS:
			self.held = true;
			return true;
		case RELEASE:
			if (!self.held) return false;
			self.held = false;
			if (elem.contains_local(event.pos)) open_thumb(elem.ui, self.index);
			return true;
		default:
			return false;
	}
}

fn void ThumbCell.describe(&self, Element* elem, Description* out) @dynamic
{
	out.text = shell_of(elem.ui).app.thumbs[self.index].caption;
}

// Shows one of the overview's images in the canvas.
fn void open_thumb(Ui* ui, sz index) @private
{
	Shell* shell = shell_of(ui);
	app::Thumb* t = &shell.app.thumbs[index];
	shell.app.face = t.face;
	shell.app.set_layer(t.layer);
	shell.app.set_channel(t.channel);
	shell.frame_pending = true;
	show_view(ui, IMAGE);
	changed(ui, STRUCTURE);
}

// ---------------------------------------------------------------------------
// Status bar

<* Build the status line, in the enclosing scope: the texel under the pointer, the zoom, and the last problem. *>
fn void status_bar() @private
{
	@tree((Bar) { .color = BAR_BACK, .insets = { 10, 4, 10, 5 }, .line_on_top = true })
	{
		// VISIBLE, not ELLIPSIS: a LiveLabel repaints its text but keeps the size
		// it measured first, so a cut label would stay as wide as its first text.
		@node((LiveLabel) { .text_of = &status_text, .size = { 0, 18 }, .text_size = 13, .color = TEXT }).with_id("status");
	};
}

<*
 The status line's text.

 @param [&in] elem : "Any element of the interface"
 @return "Allocated with mem; the LiveLabel takes it"
*>
fn String status_text(Element* elem)
{
	Shell* shell = shell_of(elem.ui);
	app::AppState* a = shell.app;
	@pool()
	{
		DString line;
		line.tinit();
		if (a.has_doc && shell.hover.on) hover_text(&line, shell);
		if (a.has_doc) line.appendf("%szoom %d%%", line.len() ? "    " : "", (int)math::round(shell.view.scale() * 100));
		if (a.mode == DIFF && a.compare.measured) psnr_text(&line, &a.compare.psnr);
		if (a.message.len) line.appendf("%s%s", line.len() ? "    " : "", a.message);
		return line.str_view().copy(mem);
	};
}

fn void psnr_text(DString* line, pixels::Psnr* psnr) @private
{
	line.append("    PSNR");
	foreach (i, db : psnr.db)
	{
		if (db == double::inf)
		{
			line.appendf(" %s =", CHANNEL_NAMES[i]);
			continue;
		}
		line.appendf(" %s %.2f", CHANNEL_NAMES[i], db);
	}
	line.append(" dB");
}

fn void hover_text(DString* line, Shell* shell) @private
{
	app::AppState* a = shell.app;
	line.appendf("x %d  y %d  level %d", shell.hover.x, shell.hover.y, a.level);
	char[4]? texel = a.texel(shell.hover.x, shell.hover.y);
	if (catch texel) return;
	line.appendf("    RGBA %d %d %d %d    %.3f %.3f %.3f %.3f", texel[0], texel[1], texel[2], texel[3],
		texel[0] / 255.0, texel[1] / 255.0, texel[2] / 255.0, texel[3] / 255.0);
	layers::Layer names = a.doc.layer_names(a.layer);
	String described = describe_names(tmem, &names);
	if (described.len) line.appendf("    %s", described[1..]);
}
