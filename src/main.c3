<*
 ktxview: a viewer for KTX2 textures.

 `ktxview [options] [file.ktx2]` opens a window on the file. The options pick
 what to show first; `--screenshot out.png` renders that, saves it and quits,
 which is how the viewer is checked from a script.
*>
module ktxview;
import ktxview::app, ktxview::ui, ktxview::layers;
import cui, cui::vulkan;
import std::io, std::io::path;
import std::math;
import std::os::env;
import std::core::string;

const String USAGE = `usage: ktxview [options] [file.ktx2]

options:
  --layer <n>          start on this array layer
  --face <n>           start on this cubemap face
  --level <n>          start on this mip level
  --channel <c>        rgb, rgba, r, g, b or a
  --view <v>           image, overview, lit or diff
  --tile               tile the image 3x3
  --compare <file>     compare with another .ktx2 or a .png
  --size <w>x<h>       window size, default 1400x860
  --screenshot <png>   render once, save the window to a PNG and quit
  -h, --help           this help`;

<* What the command line asked for. Strings borrow from the arguments. *>
struct Options
{
	String file;
	String compare;
	String screenshot;
	String view;
	layers::Channel channel;
	bool has_channel;
	uint layer;
	uint face;
	uint level;
	bool tile;
	Vec2 size;
}

<* The command line asks for help or makes no sense. *>
excuse BAD_ARGUMENTS;

<*
 Read the command line.

 @param [in] args : "As main gets them, the program first"
 @return? BAD_ARGUMENTS, String.to_uint!
*>
fn Options? parse_args(String[] args)
{
	Options o = { .size = { 1400, 860 } };
	for (sz i = 1; i < args.len; i++)
	{
		String arg = args[i];
		if (arg == "-h" || arg == "--help") return BAD_ARGUMENTS~;
		if (arg == "--tile")
		{
			o.tile = true;
			continue;
		}
		if (!arg.starts_with("--"))
		{
			o.file = arg;
			continue;
		}
		if (i + 1 >= args.len) return BAD_ARGUMENTS~;
		String value = args[++i];
		switch (arg)
		{
			case "--layer": o.layer = value.to_uint()!;
			case "--face": o.face = value.to_uint()!;
			case "--level": o.level = value.to_uint()!;
			case "--compare": o.compare = value;
			case "--screenshot": o.screenshot = value;
			case "--view":
				if (value != "image" && value != "overview" && value != "lit" && value != "diff") return BAD_ARGUMENTS~;
				o.view = value;
			case "--channel":
				o.channel = channel_named(value)!;
				o.has_channel = true;
			case "--size":
				sz x = value.index_of_char('x')!;
				o.size = { (float)value[:x].to_uint()!, (float)value[x + 1..].to_uint()! };
			default:
				return BAD_ARGUMENTS~;
		}
	}
	return o;
}

<*
 The channel a command line names: rgb, rgba, r, g, b or a.

 @param [in] name : "Lower case"
 @return? BAD_ARGUMENTS
*>
fn layers::Channel? channel_named(String name)
{
	foreach (c : layers::Channel::values)
	{
		if (c.group == name) return c;
	}
	return BAD_ARGUMENTS~;
}

<* The GPU copies of the pictures, and the revisions they hold. *>
struct Gpu
{
	ui::Textures textures;
	uint smooth_revision;
	uint sharp_revision;
	uint[app::MAX_THUMBS] thumb_revisions;
}

<*
 Make one texture per picture slot, up front: cui can't free a texture, and
 each new one rebuilds its pipeline. Each is refilled in place after.

 @param [&inout] r : "The window's renderer"
*>
fn Gpu? make_textures(Renderer* r)
{
	char[4] white = { 255, 255, 255, 255 };
	r.canvas.adopt(&r.allocator);
	Gpu gpu;
	gpu.textures.smooth = r.canvas.load_pixels(white[..], 1, 1, linear: true)!;
	gpu.textures.sharp = r.canvas.load_pixels(white[..], 1, 1, linear: false)!;
	foreach (&t : gpu.textures.thumbs) *t = r.canvas.load_pixels(white[..], 1, 1, linear: true)!;
	return gpu;
}

<*
 Copy every picture whose revision moved to its texture. The preview goes to
 the filtered or the nearest texture, whichever the canvas draws now.

 @param [&inout] r : "The window's renderer"
 @param [&in] shell : "What the interface draws"
 @return "Whether anything was uploaded"
*>
fn bool? Gpu.sync(&self, Renderer* r, ui::Shell* shell)
{
	app::AppState* a = shell.app;
	bool uploaded;
	app::Picture* p = &a.preview;
	uint* done = shell.sharp ? &self.sharp_revision : &self.smooth_revision;
	if (*done != p.revision && !p.is_empty())
	{
		Texture t = shell.sharp ? self.textures.sharp : self.textures.smooth;
		r.canvas.update_pixels(t, p.pixels, p.width, p.height, linear: !shell.sharp)!;
		*done = p.revision;
		uploaded = true;
	}
	for (sz i = 0; i < a.thumb_count; i++)
	{
		app::Picture* tp = &a.thumbs[i].picture;
		if (self.thumb_revisions[i] == tp.revision || tp.is_empty()) continue;
		r.canvas.update_pixels(self.textures.thumbs[i], tp.pixels, tp.width, tp.height, linear: true)!;
		self.thumb_revisions[i] = tp.revision;
		uploaded = true;
	}
	return uploaded;
}

<*
 The first .ktx2 in a newline-separated list of dropped paths.

 @param [in] drops : "What the window collected"
 @return? BAD_ARGUMENTS
*>
fn String? first_ktx2(String drops)
{
	Splitter lines = drops.tokenize("\n");
	while (try line = lines.next())
	{
		String p = line.trim();
		if (p.starts_with("file://")) p = p[7..];
		if (p.ends_with(".ktx2")) return p;
	}
	return BAD_ARGUMENTS~;
}

<* Where the recent list is kept, ~/.config/ktxview/recent, or "" without a home directory. Allocated with mem. *>
fn String recent_file()
{
	String? home = env::get_home_dir(tmem);
	if (catch home) return "";
	String dir = string::tformat("%s/.config/ktxview", home);
	(void)path::mkdir(dir, recursive: true);
	return string::format(mem, "%s/recent", dir);
}

fn int main(String[] args)
{
	Options? parsed = parse_args(args);
	if (catch parsed)
	{
		io::printn(USAGE);
		return args.len > 1 && (args[1] == "-h" || args[1] == "--help") ? 0 : 1;
	}
	Options o = parsed;

	app::AppState state;
	state.init(mem);
	defer state.free();
	@pool()
	{
		String recent = recent_file();
		defer if (recent.len) recent.free(mem);
		if (recent.len && !o.screenshot.len) state.load_recent(recent);
	};

	ui::Shell shell;
	shell.init(&state);
	defer shell.free();

	Renderer? made = vulkan::new(window_size: o.size, loop_mode: ON_DEMAND, clear_color: { 0.09, 0.09, 0.11, 1.0 },
		quit_on_escape: false, title: "ktxview");
	if (catch err = made)
	{
		io::eprintfn("ktxview: can't open a window: %s", err);
		return 1;
	}
	Renderer r = made;
	defer r.free();

	Ui* ui = cui::new_ui(o.size);
	defer ui.free();
	if (catch err = ui::load_font(ui)) io::eprintfn("ktxview: the font did not load: %s", err);

	Gpu? gpu_made = make_textures(&r);
	if (catch err = gpu_made)
	{
		io::eprintfn("ktxview: can't make textures: %s", err);
		return 1;
	}
	Gpu gpu = gpu_made;
	shell.textures = gpu.textures;

	ui::build(ui, &shell);
	if (o.file.len) ui::open_file(ui, o.file);
	if (state.has_doc) start_on(ui, &shell, &o);

	// Frames to draw before the screenshot: the pictures reach the GPU after the
	// frame that first lays them out, and the next one draws them.
	int settle = 3;
	while (!shell.quit && r.frame(ui)!!)
	{
		@pool()
		{
			if (try dropped = first_ktx2(r.window.take_drops(tmem))) ui::open_file(ui, dropped);
		};
		if (gpu.sync(&r, &shell)!!)
		{
			ui.request_frame();
			settle = 3;
			continue;
		}
		if (!o.screenshot.len) continue;
		if (settle-- > 0)
		{
			ui.request_frame();
			continue;
		}
		if (settle == -1)
		{
			r.request_screenshot(o.screenshot);
			ui.request_frame();
			continue;
		}
		io::printfn("wrote %s", o.screenshot);
		break;
	}
	return 0;
}

<*
 Apply the command line's starting picks to the opened file.

 @param [&inout] ui : "The interface"
 @param [&inout] shell : "Its shell"
 @param [&in] o : "The command line"
*>
fn void start_on(Ui* ui, ui::Shell* shell, Options* o)
{
	app::AppState* a = shell.app;
	a.set_face(o.face);
	a.set_layer(o.layer);
	a.set_level(o.level);
	if (o.has_channel) a.set_channel(o.channel);
	a.tiled = o.tile;
	if (o.compare.len) ui::compare_file(ui, o.compare);
	switch (o.view)
	{
		case "overview": ui::show_view(ui, OVERVIEW);
		case "lit": a.set_mode(LIT);
		case "diff": a.set_mode(DIFF);
		default: break;
	}
	shell.frame_pending = true;
	ui::changed(ui, STRUCTURE);
}
