<*
 What each layer of a packed material holds, from the `three.layers` metadata
 entry: `srgb rgb=basecolor a=height; linear rgb=normal a=roughness` names one
 layer per `;`, its colour space, and what each channel group means. A file
 without the entry gets plain RGBA labels.
*>
module ktxview::layers;
import std::core::string;

<* MALFORMED: `three.layers` could not be read. NOT_FOUND: no layer holds that map. *>
excuse MALFORMED, NOT_FOUND;

<* The metadata key the material pipeline writes. *>
const String KEY = "three.layers";

<* The most layers a description names; a longer one is MALFORMED. *>
const sz MAX_LAYERS = 16;

<* How a layer's colour is encoded. *>
enum Space : char (String word)
{
	UNSAID { "" },
	SRGB { "srgb" },
	LINEAR { "linear" },
}

<* A way of looking at an image: the colour, all four channels, or one channel. *>
enum Channel : char (String label, String group)
{
	RGB { "RGB", "rgb" },
	RGBA { "RGBA", "rgba" },
	R { "R", "r" },
	G { "G", "g" },
	B { "B", "b" },
	A { "A", "a" },
}

<* Which byte of an RGBA8 texel a single channel is; 0 for RGB and RGBA. *>
fn uint Channel.byte(self)
{
	switch (self)
	{
		case RGB:
		case RGBA:
		case R: return 0;
		case G: return 1;
		case B: return 2;
		case A: return 3;
	}
}

<* One layer's space and channel names. Names are borrowed from the parsed text. *>
struct Layer
{
	Space space;
	<* Empty where the description says nothing. *>
	String[Channel::len] names;
}

<* Every layer a description names, in file order. *>
struct LayerMap
{
	Layer[MAX_LAYERS] layers;
	sz count;
}

<*
 Read a `three.layers` value.

 @param [in] text : "The value, without its NUL; the names borrow from it"

 @return "One Layer per `;`-separated part"
 @return? MALFORMED
*>
fn LayerMap? parse(String text)
{
	LayerMap map;
	Splitter parts = text.tokenize(";");
	while (try part = parts.next())
	{
		String trimmed = part.trim();
		if (trimmed.len == 0 || map.count == MAX_LAYERS) return MALFORMED~;
		map.layers[map.count++] = parse_layer(trimmed)!;
	}
	if (map.count == 0) return MALFORMED~;
	return map;
}

fn Layer? parse_layer(String text) @local
{
	Layer layer;
	Splitter words = text.tokenize(" ");
	while (try word = words.next())
	{
		sz? eq = word.index_of_char('=');
		if (catch eq)
		{
			if (layer.space != UNSAID) return MALFORMED~;
			layer.space = space_of(word)!;
			continue;
		}
		String name = word[eq + 1..];
		if (name.len == 0) return MALFORMED~;
		layer.names[channel_of(word[:eq])!.ordinal] = name;
	}
	return layer;
}

fn Space? space_of(String word) @local
{
	foreach (space : Space::values)
	{
		if (space != UNSAID && space.word == word) return space;
	}
	return MALFORMED~;
}

fn Channel? channel_of(String group) @local
{
	foreach (channel : Channel::values)
	{
		if (channel.group == group) return channel;
	}
	return MALFORMED~;
}

<*
 What to call a channel of a layer: its name from the description, or the plain label.

 @return "Borrowed from the description, or a literal"
*>
fn String Layer.label(&self, Channel channel)
{
	String name = self.names[channel.ordinal];
	return name.len > 0 ? name : channel.label;
}

<*
 The layer's tab caption, such as "0 basecolor + height", or "Layer 0" when it names nothing.

 @param index : "The layer's number in the file"
 @param [&inout] allocator : "Owns the caption"
*>
fn String Layer.caption(&self, Allocator allocator, sz index)
{
	String rgb = self.names[Channel.RGB.ordinal];
	String a = self.names[Channel.A.ordinal];
	if (rgb.len > 0 && a.len > 0) return string::format(allocator, "%d %s + %s", index, rgb, a);
	if (rgb.len > 0) return string::format(allocator, "%d %s", index, rgb);
	if (a.len > 0) return string::format(allocator, "%d a=%s", index, a);
	return string::format(allocator, "Layer %d", index);
}

<* Where a named map lives: a layer and the channel group holding it. *>
struct Place
{
	sz layer;
	Channel channel;
}

<*
 Find the layer and channel a map is stored in, such as "normal" or "roughness".

 @param [in] name : "The map's name as the description spells it"

 @return? NOT_FOUND
*>
fn Place? LayerMap.find(&self, String name)
{
	for (sz i = 0; i < self.count; i++)
	{
		foreach (c, n : self.layers[i].names)
		{
			if (n == name) return { i, Channel::from_ordinal(c) };
		}
	}
	return NOT_FOUND~;
}
