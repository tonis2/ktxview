<*
 The viewer's state and the commands that change it, with no interface in
 sight: which file is open, which image of it is picked and how it is looked
 at, and the RGBA8 pictures the interface draws. Every command rebuilds the
 pictures it affects and bumps their revision; whoever owns the GPU copies
 compares revisions and uploads.
*>
module ktxview::app;
import ktxview::doc, ktxview::layers, ktxview::pixels;
import image, image::png;
import std::io, std::io::file;
import std::collections::list;
import std::core::string;

<* NOT_RGBA8: a PNG that isn't 8 bits a channel. NO_MATCH: the other file has no image like this one. *>
excuse NOT_RGBA8, NO_MATCH;

<* What the canvas shows. *>
enum Mode : char (String label)
{
	IMAGE { "Image" },
	LIT { "Lit" },
	DIFF { "Diff" },
}

<* Most images the overview shows; each has an RGB and an alpha thumbnail. *>
const sz MAX_THUMB_IMAGES = 12;
const sz MAX_THUMBS = MAX_THUMB_IMAGES * 2;
<* The overview draws the largest level at most this many texels across. *>
const uint THUMB_SIZE = 256;
const sz MAX_RECENT = 8;
<* How much a difference is magnified on screen. *>
const uint DIFF_SCALE = 8;

<* An RGBA8 image the interface draws. *>
struct Picture
{
	<* Owned. *>
	char[] pixels;
	uint width;
	uint height;
	<* Bumped on every change, so a GPU copy can tell it is stale. *>
	uint revision;
}

<*
 Make room for an image of a size and mark the picture changed.

 @param [&inout] allocator : "Owns the pixels"
 @return "The pixels to fill, width × height × 4 bytes"
*>
fn char[] Picture.resize(&self, Allocator allocator, uint width, uint height)
{
	sz bytes = (sz)width * height * 4;
	if (self.pixels.len != bytes)
	{
		if (self.pixels.len) alloc::free(allocator, self.pixels.ptr);
		self.pixels = bytes ? alloc::new_array(allocator, char, bytes) : {};
	}
	self.width = width;
	self.height = height;
	self.revision++;
	return self.pixels;
}

<* Whether there is nothing to draw. *>
fn bool Picture.is_empty(&self) => self.pixels.len == 0;

<* One overview cell: an image of the file, as colour or as alpha. *>
struct Thumb
{
	Picture picture;
	uint layer;
	uint face;
	<* RGB or A. *>
	layers::Channel channel;
	<* Owned. *>
	String caption;
}

<* A second image to hold the current one against: another KTX2, or a PNG. *>
struct Compare
{
	bool loaded;
	<* Owned. *>
	String path;
	<* When the other file is a KTX2. *>
	bool is_ktx;
	doc::Document other;
	<* When it is a PNG: RGBA8, owned. *>
	char[] png;
	uint png_width;
	uint png_height;
	<* Valid after a DIFF refresh that found both images. *>
	pixels::Psnr psnr;
	bool measured;
}

<* Everything the viewer knows. Lives as long as the window. *>
struct AppState
{
	Allocator allocator;
	doc::Document doc;
	bool has_doc;
	uint layer;
	uint face;
	uint level;
	layers::Channel channel;
	bool tiled;
	Mode mode;
	<* What the canvas draws. *>
	Picture preview;
	<* Why the preview is empty. Owned; empty when it shows something. *>
	String blank;
	<* The lit view's light, in the unit disc: x right, y up. *>
	float light_x;
	float light_y;
	Thumb[MAX_THUMBS] thumbs;
	sz thumb_count;
	bool thumbs_built;
	Compare compare;
	<* Paths, newest first. Owned. *>
	List{String} recent;
	<* Where `recent` is kept between runs; empty keeps it in memory only. Owned. *>
	String recent_file;
	<* The last problem worth telling the user about. Owned. *>
	String message;
}

<*
 Start with nothing open.

 @param [&inout] allocator : "Owns everything the state holds"
*>
fn void AppState.init(&self, Allocator allocator)
{
	*self = { .allocator = allocator, .light_x = -0.45f, .light_y = 0.5f };
	self.recent.init(allocator, 0);
	self.set_blank("Open a .ktx2: File › Open, a path on the command line, or drop one on the window.");
}

<* Release the file, the pictures and the lists. *>
fn void AppState.free(&self)
{
	self.close();
	foreach (path : self.recent) path.free(self.allocator);
	self.recent.free();
	free_string(self.allocator, &self.recent_file);
	free_string(self.allocator, &self.message);
	free_string(self.allocator, &self.blank);
	if (self.preview.pixels.len) alloc::free(self.allocator, self.preview.pixels.ptr);
}

fn void free_string(Allocator allocator, String* s) @local
{
	if (s.len) s.free(allocator);
	*s = "";
}

// The status line's last word; `text` is copied.
fn void AppState.set_message(&self, String text)
{
	free_string(self.allocator, &self.message);
	self.message = text.copy(self.allocator);
}

// What the empty canvas says; `text` is copied.
fn void AppState.set_blank(&self, String text)
{
	free_string(self.allocator, &self.blank);
	self.blank = text.copy(self.allocator);
}

<* Close the document and whatever was compared with it. *>
fn void AppState.close(&self)
{
	self.close_compare();
	self.drop_thumbs();
	if (self.has_doc) self.doc.free();
	self.has_doc = false;
}

// Releases the overview's thumbnails, so the next file builds its own.
fn void AppState.drop_thumbs(&self)
{
	foreach (&thumb : self.thumbs[:self.thumb_count])
	{
		if (thumb.picture.pixels.len) alloc::free(self.allocator, thumb.picture.pixels.ptr);
		thumb.caption.free(self.allocator);
		*thumb = {};
	}
	self.thumb_count = 0;
	self.thumbs_built = false;
}

<*
 Open a file from disk in place of the current one, and remember it as recent.

 @param [in] path : "A .ktx2 file"
 @return? doc::open!
*>
fn void? AppState.open(&self, String path)
{
	doc::Document? opened = doc::open(self.allocator, path);
	if (catch err = opened)
	{
		@pool() { self.set_message(string::tformat("Can't open %s: %s", path, err)); };
		return err~;
	}
	self.show(opened);
	self.remember(path);
}

<*
 Open a file held in memory in place of the current one.

 @param [in] path : "What to call it"
 @param [in] bytes : "The whole file; copied"
 @return? doc::from_bytes!
*>
fn void? AppState.open_bytes(&self, String path, char[] bytes)
{
	self.show(doc::from_bytes(self.allocator, path, bytes)!);
}

// Takes over an opened document and starts on its first image.
fn void AppState.show(&self, doc::Document opened)
{
	self.close();
	self.doc = opened;
	self.has_doc = true;
	self.layer = 0;
	self.face = 0;
	self.level = 0;
	self.channel = RGB;
	self.mode = IMAGE;
	free_string(self.allocator, &self.message);
	self.refresh();
}

<*
 Pick a layer, kept in range.

 @param layer : "Past the last one picks the last one"
*>
fn void AppState.set_layer(&self, uint layer)
{
	if (!self.has_doc) return;
	self.layer = min(layer, self.doc.layers - 1);
	self.refresh();
}

<*
 Pick a cubemap face, kept in range.

 @param face : "+X -X +Y -Y +Z -Z, 0 to 5"
*>
fn void AppState.set_face(&self, uint face)
{
	if (!self.has_doc) return;
	self.face = min(face, self.doc.faces - 1);
	self.refresh();
}

<*
 Pick a mip level, kept in range.

 @param level : "0 is the largest"
*>
fn void AppState.set_level(&self, uint level)
{
	if (!self.has_doc) return;
	self.level = min(level, self.doc.levels - 1);
	self.refresh();
}

<*
 Look at one channel, or the colour, of the image. Leaves the lit and diff views.

 @param channel : "What to show"
*>
fn void AppState.set_channel(&self, layers::Channel channel)
{
	self.channel = channel;
	self.mode = IMAGE;
	self.refresh();
}

<*
 Switch the canvas between the image, the lit material and the difference.
 A view the file can't give leaves the mode as it was.

 @param mode : "What the canvas should show"
*>
fn void AppState.set_mode(&self, Mode mode)
{
	if (mode == LIT && !self.can_light()) return;
	if (mode == DIFF && !self.compare.loaded) return;
	self.mode = mode;
	self.refresh();
}

<* Whether the file names a basecolor, a normal and a roughness map, and decodes. *>
fn bool AppState.can_light(&self) => self.has_doc && self.doc.codec != NONE && self.doc.is_material();

<*
 The modes this file offers, in toolbar order.

 @param [out] out : "Room for every mode"
 @require out.len >= Mode::len : "Too little room"
 @return "How many were written"
*>
fn sz AppState.modes(&self, Mode[] out)
{
	sz n;
	out[n++] = IMAGE;
	if (self.can_light()) out[n++] = LIT;
	if (self.compare.loaded) out[n++] = DIFF;
	return n;
}

<*
 Move the lit view's light by a distance on the image.

 @param dx : "Right, in units of the disc's radius"
 @param dy : "Up, in the same units"
*>
fn void AppState.move_light(&self, float dx, float dy)
{
	pixels::LightDir l = pixels::light_at(self.light_x + dx, self.light_y + dy);
	self.light_x = l.x;
	self.light_y = l.y;
	if (self.mode == LIT) self.refresh();
}

<*
 The caption of a layer: its names from the file, or its number.

 @param [&inout] allocator : "Owns the caption"
 @param layer : "A layer of the open file"
 @require self.has_doc : "No file is open"
*>
fn String AppState.layer_caption(&self, Allocator allocator, uint layer)
	=> self.doc.layer_names(layer).caption(allocator, layer);

<*
 What to call a channel of the current layer: "height" for A on a basecolor + height layer.

 @param channel : "The channel to name"
 @return "Borrowed from the file, or a literal"
*>
fn String AppState.channel_label(&self, layers::Channel channel)
{
	if (!self.has_doc) return channel.label;
	return self.doc.layer_names(self.layer).label(channel);
}

<*
 The decoded texel at a position of the current image.

 @return? doc::NO_DECODER, doc::Document.image!
*>
fn char[4]? AppState.texel(&self, uint x, uint y)
{
	if (!self.has_doc) return doc::NO_DECODER~;
	char[] image = self.doc.image(self.level, self.layer, self.face)!;
	uint w = self.doc.level_width(self.level);
	usz at = ((usz)min(y, self.doc.level_height(self.level) - 1) * w + min(x, w - 1)) * 4;
	char[4] out = image[at:4];
	return out;
}

<* Rebuild the preview for the current file, image and mode. *>
fn void AppState.refresh(&self) => @pool()
{
	// With nothing open the blank text keeps saying how to open something.
	if (!self.has_doc) return;
	String why = self.fill_preview();
	free_string(self.allocator, &self.blank);
	if (why.len == 0) return;
	self.preview.resize(self.allocator, 0, 0);
	self.blank = why.copy(self.allocator);
}

// Fills the preview, or says in temp memory why it can't.
fn String AppState.fill_preview(&self)
{
	if (self.doc.codec == NONE) return string::tformat("Can't decode %s yet.", self.doc.cannot_decode);
	char[]? image = self.doc.image(self.level, self.layer, self.face);
	if (catch err = image) return string::tformat("Can't decode this image: %s", err);
	uint w = self.doc.level_width(self.level);
	uint h = self.doc.level_height(self.level);
	switch (self.mode)
	{
		case IMAGE:
			pixels::view_channel(self.preview.resize(self.allocator, w, h), image, w, self.channel);
		case LIT:
			pixels::Material? material = self.material(w, h);
			if (catch material) return "Can't decode the material's layers.";
			pixels::shade(self.preview.resize(self.allocator, w, h), &material, pixels::light_at(self.light_x, self.light_y));
		case DIFF:
			char[]? other = self.other_image(w, h);
			if (catch other) return string::tformat("The other file has no %d × %d image at level %d, layer %d, face %d.", w, h, self.level, self.layer, self.face);
			self.compare.psnr = pixels::diff(self.preview.resize(self.allocator, w, h), image, other, DIFF_SCALE);
			self.compare.measured = true;
	}
	return "";
}

// The maps the lit view reads, at the current level and face.
fn pixels::Material? AppState.material(&self, uint w, uint h)
{
	layers::Place base = self.doc.names.find("basecolor")!;
	layers::Place normal = self.doc.names.find("normal")!;
	layers::Place rough = self.doc.names.find("roughness")!;
	uint level = self.level;
	return {
		.basecolor = self.doc.image(level, (uint)base.layer, self.face)!,
		.normal = self.doc.image(level, (uint)normal.layer, self.face)!,
		.roughness = self.doc.image(level, (uint)rough.layer, self.face)!,
		.roughness_byte = rough.channel.byte(),
		.width = w,
		.height = h,
	};
}

// The compared file's image that matches the current one, if it has one that size.
fn char[]? AppState.other_image(&self, uint w, uint h)
{
	Compare* c = &self.compare;
	if (!c.loaded) return NO_MATCH~;
	if (!c.is_ktx)
	{
		if (c.png_width != w || c.png_height != h) return NO_MATCH~;
		return c.png;
	}
	doc::Document* other = &c.other;
	if (self.level >= other.levels || self.layer >= other.layers || self.face >= other.faces) return NO_MATCH~;
	if (other.level_width(self.level) != w || other.level_height(self.level) != h) return NO_MATCH~;
	return other.image(self.level, self.layer, self.face);
}

<*
 Hold the current file against another, and show the difference.

 @param [in] path : "A .ktx2 or a .png"
 @return? NOT_RGBA8, doc::open!, png::load_bytes!
*>
fn void? AppState.compare_with(&self, String path)
{
	char[]? bytes = file::load(self.allocator, path);
	if (catch err = bytes)
	{
		@pool() { self.set_message(string::tformat("Can't open %s: %s", path, err)); };
		return err~;
	}
	defer alloc::free(self.allocator, bytes.ptr);
	if (catch err = self.compare_bytes(path, bytes))
	{
		@pool() { self.set_message(string::tformat("Can't compare with %s: %s", path, err)); };
		return err~;
	}
}

<*
 Hold the current file against another held in memory.

 @param [in] path : "What to call it; a name ending in .png is read as a PNG"
 @param [in] bytes : "The whole file; copied"
 @return? NOT_RGBA8, doc::from_bytes!, png::load_bytes!
*>
fn void? AppState.compare_bytes(&self, String path, char[] bytes)
{
	Compare next = { .loaded = true };
	if (path.ends_with(".png"))
	{
		image::Image img = png::load_bytes(bytes, self.allocator)!;
		defer img.free();
		if (img.bit_depth != 8) return NOT_RGBA8~;
		next.png = img.to_rgba(self.allocator);
		next.png_width = img.width;
		next.png_height = img.height;
	}
	else
	{
		next.other = doc::from_bytes(self.allocator, path, bytes)!;
		next.is_ktx = true;
	}
	next.path = path.copy(self.allocator);
	self.close_compare();
	self.compare = next;
	self.mode = DIFF;
	self.refresh();
}

<* Stop comparing, and go back to the image. *>
fn void AppState.close_compare(&self)
{
	Compare* c = &self.compare;
	if (!c.loaded) return;
	if (c.is_ktx) c.other.free();
	if (c.png.len) alloc::free(self.allocator, c.png.ptr);
	c.path.free(self.allocator);
	*c = {};
	if (self.mode == DIFF)
	{
		self.mode = IMAGE;
		self.refresh();
	}
}

<*
 The overview's level: the largest no wider or taller than THUMB_SIZE.

 @require self.has_doc : "No file is open"
*>
fn uint AppState.thumb_level(&self)
{
	uint level;
	while (level + 1 < self.doc.levels && max(self.doc.level_width(level), self.doc.level_height(level)) > THUMB_SIZE) level++;
	return level;
}

<* Build the overview's thumbnails, once per file: colour and alpha for every layer and face. *>
fn void AppState.build_thumbs(&self) => @pool()
{
	if (self.thumbs_built || !self.has_doc) return;
	self.thumbs_built = true;
	if (self.doc.codec == NONE) return;
	uint level = self.thumb_level();
	uint w = self.doc.level_width(level);
	for (uint layer = 0; layer < self.doc.layers; layer++)
	{
		for (uint face = 0; face < self.doc.faces; face++)
		{
			if (self.thumb_count == MAX_THUMBS) return;
			char[]? image = self.doc.image(level, layer, face);
			if (catch image) continue;
			layers::Layer names = self.doc.layer_names(layer);
			foreach (channel : (layers::Channel[2]){ RGB, A })
			{
				Thumb* t = &self.thumbs[self.thumb_count++];
				*t = { .layer = layer, .face = face, .channel = channel };
				pixels::view_channel(t.picture.resize(self.allocator, w, self.doc.level_height(level)), image, w, channel);
				String face_part = self.doc.faces == 6 ? string::tformat(" %s", FACE_NAMES[face]) : "";
				String name = names.names[channel.ordinal];
				t.caption = string::format(self.allocator, "L%d%s %s%s%s", layer, face_part,
					channel == RGB ? "rgb" : "alpha", name.len ? ": " : "", name);
			}
		}
	}
}

<* Cubemap faces in file order. *>
const String[6] FACE_NAMES = { "+X", "-X", "+Y", "-Y", "+Z", "-Z" };

<*
 Put a path at the top of the recent list, and save the list when it has a file.

 @param [in] path : "Copied"
*>
fn void AppState.remember(&self, String path)
{
	foreach (i, known : self.recent)
	{
		if (known != path) continue;
		known.free(self.allocator);
		self.recent.remove_at(i);
		break;
	}
	self.recent.insert_at(0, path.copy(self.allocator));
	while (self.recent.len() > MAX_RECENT) self.recent.pop()!!.free(self.allocator);
	if (!self.recent_file.len) return;
	@pool()
	{
		DString text;
		text.tinit();
		foreach (known : self.recent) text.appendf("%s\n", known);
		(void)file::save(self.recent_file, text.str_view());
	};
}

<*
 Keep the recent list in a file, and read what is already there.

 @param [in] path : "One path per line; it need not exist yet"
*>
fn void AppState.load_recent(&self, String path)
{
	free_string(self.allocator, &self.recent_file);
	self.recent_file = path.copy(self.allocator);
	@pool()
	{
		char[]? text = file::load(tmem, path);
		if (catch text) return;
		Splitter lines = ((String)text).tokenize("\n");
		while (try line = lines.next())
		{
			if (self.recent.len() < MAX_RECENT && line.len) self.recent.push(line.copy(self.allocator));
		}
	};
}
