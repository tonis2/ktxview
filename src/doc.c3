<*
 An opened .ktx2 file: its bytes, what it says about itself, and its images
 decoded to RGBA8 on demand.

 A Basis file (UASTC or ETC1S) is transcoded one layer and face at a time, every
 level at once, because the levels share one supercompressed container. Any
 other file is read once and each image is decoded when it is first asked for.
 A format the library has no decoder for still opens: `info` fills in and
 `cannot_decode` says what is missing.
*>
module ktxview::doc;
import ktx::container, ktx::basis, ktx::codec, ktx::vk, ktx::dfd;
import ktxview::layers;
import std::io::file;
import std::core::string;

<* There is no decoder for this file's format; `cannot_decode` says which. *>
excuse NO_DECODER;

<* How the images are decoded. *>
enum Codec : char
{
	NONE,
	BASIS,
	PLAIN,
}

<* An opened file. Free with `free()`. *>
struct Document
{
	Allocator allocator;
	<* Owned. *>
	String path;
	<* The whole file. Owned. *>
	char[] bytes;
	<* Owned. *>
	container::FileInfo info;
	Codec codec;
	<* PLAIN only: the inflated levels. Owned. *>
	container::Texture tex;
	uint width;
	uint height;
	<* Each at least 1. *>
	uint levels;
	uint layers;
	uint faces;
	<* RGBA8 per (layer, face, level), empty until decoded. Owned. *>
	char[][] images;
	<* What can't be decoded, such as "ASTC 4x4"; empty when images decode. Owned. *>
	String cannot_decode;
	<* Valid when `named`; the names borrow from `info`. *>
	layers::LayerMap names;
	bool named;
}

<*
 Open a file from disk.

 @param [&inout] allocator : "Owns the document"
 @param [in] path : "A .ktx2 file"

 @return? container::BAD_IDENTIFIER, file::load!
*>
fn Document? open(Allocator allocator, String path)
{
	char[] bytes = file::load(allocator, path)!;
	defer alloc::free(allocator, bytes.ptr);
	return from_bytes(allocator, path, bytes);
}

<*
 Open a file already in memory.

 @param [&inout] allocator : "Owns the document"
 @param [in] path : "What the file is called; copied"
 @param [in] bytes : "The whole file; copied"

 @return? container::BAD_IDENTIFIER
*>
fn Document? from_bytes(Allocator allocator, String path, char[] bytes)
{
	container::FileInfo info = container::describe(allocator, bytes)!;
	Document doc = {
		.allocator = allocator,
		.path = path.copy(allocator),
		.bytes = alloc::clone_slice(allocator, bytes),
		.info = info,
		.width = info.width,
		.height = max(info.height, 1u),
		.levels = max(info.level_count, 1u),
		.layers = max(info.layer_count, 1u),
		.faces = max(info.face_count, 1u),
	};
	doc.images = alloc::new_array(allocator, char[], (sz)doc.layers * doc.faces * doc.levels);

	if (try text = info.text(layers::KEY))
	{
		if (try map = layers::parse(text))
		{
			doc.names = map;
			doc.named = true;
		}
	}

	if (@ok(basis::info(doc.bytes)))
	{
		doc.codec = BASIS;
		return doc;
	}
	container::Texture? tex = container::read(allocator, doc.bytes);
	if (catch err = tex)
	{
		doc.cannot_decode = string::format(allocator, "this file (%s)", err);
		return doc;
	}
	doc.tex = tex;
	doc.codec = PLAIN;
	// The smallest image decodes in no time, and says whether any of them can.
	@pool()
	{
		if (catch codec::decode_image(tmem, doc.tex.vk_format, doc.tex.image(doc.levels - 1)!!,
			doc.level_width(doc.levels - 1), doc.level_height(doc.levels - 1)))
		{
			doc.codec = NONE;
			doc.cannot_decode = format_name(allocator, &doc.info);
		}
	};
	return doc;
}

<* Release everything the document owns. *>
fn void Document.free(&self)
{
	if (!self.allocator) return;
	foreach (image : self.images)
	{
		if (image.len) alloc::free(self.allocator, image.ptr);
	}
	if (self.images.len) alloc::free(self.allocator, self.images.ptr);
	self.tex.free();
	self.info.free();
	if (self.cannot_decode.len) self.cannot_decode.free(self.allocator);
	alloc::free(self.allocator, self.bytes.ptr);
	self.path.free(self.allocator);
	*self = {};
}

<* Texels across one level; never 0. *>
fn uint Document.level_width(&self, uint level) => max(self.width >> level, 1u);
<* Texels down one level; never 0. *>
fn uint Document.level_height(&self, uint level) => max(self.height >> level, 1u);

<* The file name without its directory. Borrowed from the document. *>
fn String Document.name(&self)
{
	sz? slash = self.path.rindex_of_char('/');
	if (catch slash) return self.path;
	return self.path[slash + 1..];
}

// Where an image sits in `images`.
fn sz Document.slot(&self, uint level, uint layer, uint face)
	=> ((sz)layer * self.faces + face) * self.levels + level;

<*
 One image as RGBA8, decoded the first time it is asked for.

 @require level < self.levels && layer < self.layers && face < self.faces : "No such image"

 @return "Borrowed: level_width × level_height texels, alive until free()"
 @return? NO_DECODER, basis::transcode_levels!, codec::decode_image!
*>
fn char[]? Document.image(&self, uint level, uint layer, uint face)
{
	sz at = self.slot(level, layer, face);
	if (self.images[at].len) return self.images[at];
	switch (self.codec)
	{
		case NONE:
			return NO_DECODER~;
		case BASIS:
			basis::Transcoded[] all = basis::transcode_levels(self.allocator, self.bytes, layer, face, basis::TF_RGBA32)!;
			defer alloc::free(self.allocator, all.ptr);
			foreach (l, t : all) self.images[self.slot((uint)l, layer, face)] = t.data;
		case PLAIN:
			char[] data = self.tex.image(level, layer, face)!;
			self.images[at] = codec::decode_image(self.allocator, self.tex.vk_format, data,
				self.level_width(level), self.level_height(level))!;
	}
	return self.images[at];
}

<* Whether the layer names say which layers are basecolor, normal and roughness. *>
fn bool Document.is_material(&self)
{
	return self.named && @ok(self.names.find("basecolor")) && @ok(self.names.find("normal"))
		&& @ok(self.names.find("roughness"));
}

<*
 The layer names for one layer, or a blank set when the file has none.

 @param layer : "A layer of the file"

 @return "Borrowed from the document"
*>
fn layers::Layer Document.layer_names(&self, uint layer)
{
	if (!self.named || layer >= self.names.count) return {};
	return self.names.layers[layer];
}

<*
 The format the way a person says it: "BC7_SRGB", "UASTC 4x4", "ETC1S", "ASTC 6x6 sRGB".

 @param [&inout] allocator : "Owns the name"
 @param [&in] info : "The file's description"
*>
fn String format_name(Allocator allocator, container::FileInfo* info)
{
	if (info.dfd_status == PARSED)
	{
		switch (info.dfd.model)
		{
			case dfd::MODEL_UASTC: return "UASTC 4x4".copy(allocator);
			case dfd::MODEL_ETC1S: return "ETC1S".copy(allocator);
			default: break;
		}
	}
	vk::FormatInfo? fi = vk::info(info.vk_format);
	if (catch fi) return string::format(allocator, "VkFormat %d", info.vk_format);
	if (fi.name == "ASTC") return string::format(allocator, "ASTC %dx%d%s", fi.block_w, fi.block_h, fi.srgb ? " sRGB" : "");
	return fi.name.copy(allocator);
}

<* How a texture could sit in GPU memory. *>
enum GpuLayout : char
{
	BLOCK_4X4, // BC7 or ASTC 4x4: 16 bytes per 4x4 block
	RGBA8,
}

<*
 Bytes the whole texture takes on a GPU, every level, layer and face counted.

 @param layout : "How the GPU would hold it"
*>
fn ulong Document.gpu_bytes(&self, GpuLayout layout)
{
	ulong bytes;
	for (uint l = 0; l < self.levels; l++)
	{
		ulong w = self.level_width(l);
		ulong h = self.level_height(l);
		switch (layout)
		{
			case BLOCK_4X4: bytes += (w + 3) / 4 * ((h + 3) / 4) * 16;
			case RGBA8: bytes += w * h * 4;
		}
	}
	return bytes * self.layers * self.faces;
}
