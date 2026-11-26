<*
 What the canvas shows, built on the CPU from decoded RGBA8: one channel as
 grey, the colour with alpha over a checkerboard, a lit material, and the
 difference between two images. Bytes go to the screen as they are, so a
 data map shows its stored values and sRGB colour looks right.
*>
module ktxview::pixels;
import ktxview::layers;
import ktx::parallel;
import std::math;

<* Side of a checkerboard square behind see-through texels, in texels. *>
const uint CHECKER = 8;

const char CHECKER_LIGHT = 204;
const char CHECKER_DARK = 140;

<*
 Build the view of one channel: grey for R, G, B or A; opaque colour for RGB;
 colour over a checkerboard for RGBA.

 @param [out] dst : "width × height × 4 bytes"
 @param [in] src : "RGBA8, the same size"
 @param width : "Texels across, for the checkerboard"
 @param channel : "What to show"
 @require dst.len == src.len && src.len % 4 == 0 : "Images differ in size"
 @require width > 0 && src.len / 4 % width == 0 : "Width does not divide the image"
*>
fn void view_channel(char[] dst, char[] src, uint width, layers::Channel channel)
{
	sz texels = src.len / 4;
	switch (channel)
	{
		case RGB:
			for (sz i = 0; i < texels; i++)
			{
				dst[i * 4:3] = src[i * 4:3];
				dst[i * 4 + 3] = 255;
			}
		case RGBA:
			for (sz i = 0; i < texels; i++)
			{
				uint x = (uint)(i % width) / CHECKER;
				uint y = (uint)(i / width) / CHECKER;
				uint back = (x + y) % 2 == 0 ? CHECKER_LIGHT : CHECKER_DARK;
				uint a = src[i * 4 + 3];
				for (sz c = 0; c < 3; c++) dst[i * 4 + c] = (char)((src[i * 4 + c] * a + back * (255 - a) + 127) / 255);
				dst[i * 4 + 3] = 255;
			}
		case R:
		case G:
		case B:
		case A:
			uint offset = channel.byte();
			for (sz i = 0; i < texels; i++)
			{
				char v = src[i * 4 + offset];
				char[4] grey = { v, v, v, 255 };
				dst[i * 4:4] = grey[..];
			}
	}
}

<* Where the light is: x right and y up on the image, z out of it; unit length. *>
typedef LightDir = float[<3>];

<*
 A light dragged across the image: a point in the unit disc, lifted onto the
 hemisphere so it never lies flat on the surface.

 @param x : "Right, -1..1"
 @param y : "Up, -1..1"
*>
fn LightDir light_at(float x, float y)
{
	float[<2>] p = { x, y };
	float r = p.length();
	if (r > 0.95f) p *= 0.95f / r;
	return (LightDir){ p.x, p.y, math::sqrt(1.0f - p.x * p.x - p.y * p.y) };
}

<* The three maps a lit view reads, each an RGBA8 image of the same size. *>
struct Material
{
	<* sRGB colour in RGB. *>
	char[] basecolor;
	<* Tangent space, OpenGL convention: green points up the image. *>
	char[] normal;
	char[] roughness;
	<* Which byte of a roughness texel holds it: 0..3. *>
	uint roughness_byte;
	uint width;
	uint height;
}

struct ShadeJob @local
{
	Material* material;
	char[] dst;
	LightDir light;
	float[256] to_linear;
	char[4096] to_srgb;
}

<*
 Shade a flat patch of the material under one white light: ambient, N·L
 diffuse and a Blinn-Phong highlight whose sharpness follows roughness. Rows
 are spread across threads.

 @param [out] dst : "width × height × 4 bytes"
 @param [&in] material : "The maps"
 @param light : "From light_at"
 @require dst.len == (sz)material.width * material.height * 4 : "Wrong output size"
 @require material.roughness_byte < 4 : "No such byte"
*>
fn void shade(char[] dst, Material* material, LightDir light)
{
	ShadeJob* job = mem::new(ShadeJob);
	defer free(job);
	*job = { .material = material, .dst = dst, .light = light };
	for (int i = 0; i < 256; i++) job.to_linear[i] = srgb_to_linear(i / 255.0f);
	for (int i = 0; i < 4096; i++)
	{
		job.to_srgb[i] = (char)(math::clamp(linear_to_srgb(i / 4095.0f), 0.0f, 1.0f) * 255.0f + 0.5f);
	}
	parallel::run(material.height, job, &shade_row, parallel::shares(material.height, 16));
}

fn void shade_row(void* ctx, usz y) @local
{
	ShadeJob* job = ctx;
	Material* m = job.material;
	float[<3>] l = (float[<3>])job.light;
	float[<3>] h = (l + (float[<3>]){ 0, 0, 1 }).normalize();
	for (usz x = 0; x < m.width; x++)
	{
		usz i = (y * m.width + x) * 4;
		float[<3>] n = {
			m.normal[i] / 127.5f - 1.0f,
			m.normal[i + 1] / 127.5f - 1.0f,
			m.normal[i + 2] / 127.5f - 1.0f,
		};
		n = n.length() > 0.0001f ? n.normalize() : (float[<3>]){ 0, 0, 1 };
		float n_dot_l = math::max(n.dot(l), 0.0f);
		float n_dot_h = math::max(n.dot(h), 0.0f);

		float rough = math::max(m.roughness[i + m.roughness_byte] / 255.0f, 0.03f);
		float alpha = rough * rough;
		float shininess = math::clamp(2.0f / (alpha * alpha) - 2.0f, 1.0f, 4096.0f);
		float spec = 0.04f * (shininess + 8.0f) / 8.0f * math::pow(n_dot_h, shininess) * n_dot_l;

		for (usz c = 0; c < 3; c++)
		{
			float base = job.to_linear[m.basecolor[i + c]];
			float lit = base * (0.12f + 0.88f * n_dot_l) + spec;
			job.dst[i + c] = job.to_srgb[(usz)(math::clamp(lit, 0.0f, 1.0f) * 4095.0f + 0.5f)];
		}
		job.dst[i + 3] = 255;
	}
}

fn float srgb_to_linear(float c) => c <= 0.04045f ? c / 12.92f : math::pow((c + 0.055f) / 1.055f, 2.4f);
fn float linear_to_srgb(float c) => c <= 0.0031308f ? c * 12.92f : 1.055f * math::pow(c, 1.0f / 2.4f) - 0.055f;

<* Peak signal to noise per channel R, G, B, A, in dB; infinite where the two agree. *>
struct Psnr
{
	double[4] db;
}

<*
 The absolute difference of two images, scaled up so small errors show, and
 how far apart they are per channel.

 @param [out] dst : "The difference as an opaque RGB image; alpha's difference is not drawn"
 @param [in] a : "RGBA8"
 @param [in] b : "RGBA8, the same size"
 @param scale : "Each difference is multiplied by this, then clamped"
 @require a.len == b.len && dst.len == a.len && a.len % 4 == 0 : "Images differ in size"
 @require a.len > 0 : "Empty images"
*>
fn Psnr diff(char[] dst, char[] a, char[] b, uint scale)
{
	ulong[4] squared;
	for (sz i = 0; i < a.len; i += 4)
	{
		for (sz c = 0; c < 4; c++)
		{
			int d = math::abs((int)a[i + c] - (int)b[i + c]);
			squared[c] += (ulong)(d * d);
			if (c < 3) dst[i + c] = (char)math::min(d * (int)scale, 255);
		}
		dst[i + 3] = 255;
	}
	Psnr out;
	double texels = (double)(a.len / 4);
	foreach (c, sum : squared)
	{
		out.db[c] = sum == 0 ? double::inf : 10.0 * math::log10(255.0 * 255.0 * texels / sum);
	}
	return out;
}
