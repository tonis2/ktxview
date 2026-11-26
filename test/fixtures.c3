<*
 Test files, made in memory with ktx.c3l: no blobs are checked in. Each image
 is a pattern whose texels a test can compute, so a decoded view can be held
 against the numbers that went in.
*>
module ktxview_test::fixtures;
import ktxview::app, ktxview::ui, ktxview::layers;
import ktx::container, ktx::basis, ktx::codec, ktx::vk;
import cui, cui::widgets;
import std::core::string;
import std::io::path;
import std::time;
import std::math;

const String LAYERS = "srgb rgb=basecolor a=height; linear rgb=normal a=roughness";

<* Layer 0 of the material: a colour ramp, with height rising left to right. *>
fn char[] basecolor_height(Allocator allocator, uint w, uint h)
{
	char[] out = alloc::new_array(allocator, char, (sz)w * h * 4);
	for (uint y = 0; y < h; y++)
	{
		for (uint x = 0; x < w; x++)
		{
			sz i = ((sz)y * w + x) * 4;
			out[i] = (char)(40 + x * 4);
			out[i + 1] = (char)(90 + y * 2);
			out[i + 2] = 150;
			out[i + 3] = (char)(x * 255 / (w - 1));
		}
	}
	return out;
}

<* Layer 1: a flat normal, with roughness falling top to bottom. *>
fn char[] normal_roughness(Allocator allocator, uint w, uint h)
{
	char[] out = alloc::new_array(allocator, char, (sz)w * h * 4);
	for (uint y = 0; y < h; y++)
	{
		for (uint x = 0; x < w; x++)
		{
			sz i = ((sz)y * w + x) * 4;
			char[4] texel = { 128, 128, 255, (char)(255 - y * 255 / (h - 1)) };
			out[i:4] = texel[..];
		}
	}
	return out;
}

<* A two-layer material with `three.layers`, as UASTC (Zstd) or ETC1S (BasisLZ). *>
fn char[] material(Allocator allocator, uint format, uint size = 32)
{
	char[] l0 = basecolor_height(mem, size, size);
	defer free(l0);
	char[] l1 = normal_roughness(mem, size, size);
	defer free(l1);
	char[][2] images = { l0, l1 };
	char[] value = string::format(mem, "%s\0", LAYERS);
	defer free(value);
	container::KvPair[1] kv = { { layers::KEY, value } };
	return basis::encode(allocator, format, images[..], size, size, ARRAY,
		{ .quality = 90, .effort = 2, .srgb = false, .mipmaps = true, .kv = kv[..] })!!;
}

<* A plain file of one format, a 2D image or a cube, every image filled by face_colour. *>
fn char[] plain(Allocator allocator, uint format, uint size, uint faces, uint levels)
{
	container::Texture tex = container::create(mem, {
		.vk_format = format, .width = size, .height = size, .face_count = faces, .level_count = levels,
	})!!;
	defer tex.free();
	for (uint l = 0; l < levels; l++)
	{
		uint w = tex.level_width(l);
		for (uint f = 0; f < faces; f++)
		{
			char[] rgba = face_colour(mem, w, f);
			defer free(rgba);
			if (format == vk::R8G8B8A8_UNORM)
			{
				tex.set_image(l, 0, f, rgba)!!;
				continue;
			}
			char[] encoded = codec::encode_image(mem, format, rgba, w, w)!!;
			defer free(encoded);
			tex.set_image(l, 0, f, encoded)!!;
		}
	}
	return container::write(allocator, &tex, { .scheme = ZSTD })!!;
}

<* An image of one colour per face: face f is (f * 40, 255 - f * 40, 100, 200). *>
fn char[] face_colour(Allocator allocator, uint size, uint face)
{
	char[] out = alloc::new_array(allocator, char, (sz)size * size * 4);
	for (sz i = 0; i < out.len; i += 4)
	{
		char[4] texel = { (char)(face * 40), (char)(255 - face * 40), 100, 200 };
		out[i:4] = texel[..];
	}
	return out;
}

<* An ASTC 4x4 file of zero blocks: it opens, but nothing decodes it yet. *>
fn char[] astc(Allocator allocator)
{
	container::Texture tex = container::create(mem, { .vk_format = vk::ASTC_4X4_UNORM, .width = 16, .height = 16 })!!;
	defer tex.free();
	return container::write(allocator, &tex)!!;
}

<*
 A fresh, empty directory under the system's temp directory, for one test.

 @param [in] name : "Part of the directory's name"
 @return "In temp memory"
*>
fn String scratch_dir(String name)
{
	String base = (String)path::temp_directory(tmem)!!;
	String dir = string::tformat("%s/ktxview-%s-%d", base, name, clock::now());
	(void)path::rmtree(path::tnew(dir)!!);
	path::mkdir(dir, recursive: true)!!;
	return dir;
}

<* A headless interface over an app: no window, no GPU. *>
struct Rig
{
	Ui* ui;
	app::AppState app;
	ui::Shell shell;
}

<*
 Build the interface around one file. Opened through a pointer: the Ui keeps
 pointers into the rig.

 @param [in] name : "The file's name; .png names compare as PNG"
 @param [in] bytes : "The file"
*>
fn void Rig.open(&self, String name, char[] bytes, Vec2 size = { 1400, 860 })
{
	self.app.init(mem);
	if (bytes.len) self.app.open_bytes(name, bytes)!!;
	self.shell.init(&self.app);
	self.ui = cui::new_ui(size);
	ui::load_font(self.ui)!!;
	ui::build(self.ui, &self.shell);
	self.ui.flush();
}

fn void Rig.free(&self)
{
	self.ui.free();
	self.shell.free();
	self.app.free();
}

<* Click the visible text that best matches, as a person would. *>
fn void Rig.click_text(&self, String text)
{
	self.ui.click(self.ui.find_text(text)!!.center());
}

<* Press one key, or a chord, on the interface. *>
fn void Rig.press(&self, Key[] keys)
{
	self.ui.press_keys(keys);
}

<* The value the info panel shows for a key, or "" when it has no such row. *>
fn String Rig.info(&self, String key)
{
	String found;
	self.ui.@each(ui::InfoRow; elem)
	{
		ui::InfoRow* row = elem.widget_as(ui::InfoRow);
		if (row.key == key) found = row.value;
	};
	return found;
}

<* The preview texel at a position, as RGBA bytes. *>
fn char[4] Rig.preview_at(&self, uint x, uint y)
{
	app::Picture* p = &self.app.preview;
	sz i = ((sz)y * p.width + x) * 4;
	char[4] out = p.pixels[i:4];
	return out;
}
