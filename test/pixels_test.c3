module ktxview_test::pixels_test @test;
import ktxview::pixels, ktxview::layers;

fn void single_channels_spread_to_grey()
{
	char[8] src = { 10, 20, 30, 40, 50, 60, 70, 80 };
	char[8] dst;
	pixels::view_channel(dst[..], src[..], 2, G);
	test::eq(dst[..], (char[]){ 20, 20, 20, 255, 60, 60, 60, 255 });
	pixels::view_channel(dst[..], src[..], 2, A);
	test::eq(dst[..], (char[]){ 40, 40, 40, 255, 80, 80, 80, 255 });
	pixels::view_channel(dst[..], src[..], 2, RGB);
	test::eq(dst[..], (char[]){ 10, 20, 30, 255, 50, 60, 70, 255 });
}

fn void alpha_shows_the_checkerboard_through()
{
	// Two texels in different checker squares, both fully see-through.
	uint w = pixels::CHECKER * 2;
	char[] src = mem::new_array(char, (sz)w * 4);
	defer free(src);
	char[] dst = mem::new_array(char, (sz)w * 4);
	defer free(dst);
	pixels::view_channel(dst, src, w, RGBA);
	test::eq(dst[0], pixels::CHECKER_LIGHT);
	test::eq(dst[(sz)pixels::CHECKER * 4], pixels::CHECKER_DARK);
	test::eq(dst[3], (char)255);

	// Opaque texels show as they are.
	src[0:4] = (char[4]){ 9, 8, 7, 255 }[..];
	pixels::view_channel(dst, src, w, RGBA);
	test::eq(dst[0:4], (char[]){ 9, 8, 7, 255 });
}

fn void identical_images_have_no_difference()
{
	char[8] a = { 1, 2, 3, 4, 5, 6, 7, 8 };
	char[8] dst;
	pixels::Psnr p = pixels::diff(dst[..], a[..], a[..], 8);
	foreach (db : p.db) test::eq(db, double::inf);
	test::eq(dst[..], (char[]){ 0, 0, 0, 255, 0, 0, 0, 255 });
}

fn void a_difference_is_scaled_and_measured()
{
	char[4] a = { 100, 100, 100, 255 };
	char[4] b = { 110, 100, 100, 255 };
	char[4] dst;
	pixels::Psnr p = pixels::diff(dst[..], a[..], b[..], 8);
	test::eq(dst[0], (char)80);
	// One texel 10 apart: 10 log10(255² / 100).
	test::eq_approx(p.db[0], 28.1308, delta: 0.001);
	test::eq(p.db[1], double::inf);
}

fn void the_light_stays_above_the_surface()
{
	pixels::LightDir l = pixels::light_at(3, 0);
	test::eq_approx(l.x, 0.95f, delta: 0.0001);
	test::gt(l.z, 0.0f);
	test::eq_approx(((float[<3>])l).length(), 1.0f, delta: 0.0001);
}

fn void a_face_toward_the_light_is_brighter()
{
	// Two texels: one normal facing straight out, one tilted away from a light on the right.
	char[8] base = { 128, 128, 128, 255, 128, 128, 128, 255 };
	char[8] normal = { 128, 128, 255, 255, 20, 128, 160, 255 };
	char[8] rough = { 255, 255, 255, 200, 255, 255, 255, 200 };
	char[8] dst;
	pixels::Material m = { base[..], normal[..], rough[..], 3, 2, 1 };
	pixels::shade(dst[..], &m, pixels::light_at(0.8f, 0));
	test::gt(dst[0], dst[4]);
	test::eq(dst[3], (char)255);
}
