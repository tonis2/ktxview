module ktxview_test::app_test @test;
import ktxview::app, ktxview::layers, ktxview::pixels;
import ktxview_test::fixtures;
import ktx::basis, ktx::vk;
import image, image::png;
import std::core::string;

fn void opening_shows_layer_zero_in_colour()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.open_bytes("wall.ktx2", file)!!;

	test::eq(a.preview.width, 32u);
	char[] image = a.doc.image(0, 0, 0)!!;
	char[] expect = mem::new_array(char, image.len);
	defer free(expect);
	pixels::view_channel(expect, image, 32, RGB);
	test::eq(a.preview.pixels, expect);
	test::eq(a.blank, "");
}

fn void picks_rebuild_the_preview_and_stay_in_range()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.open_bytes("wall.ktx2", file)!!;

	uint before = a.preview.revision;
	a.set_level(99);
	test::eq(a.level, 5u);
	test::eq(a.preview.width, 1u);
	test::gt(a.preview.revision, before);
	a.set_layer(7);
	test::eq(a.layer, 1u);
	test::eq(a.channel_label(A), "roughness");
}

fn void the_lit_view_needs_a_material()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.open_bytes("wall.ktx2", file)!!;
	a.set_mode(LIT);
	test::eq(a.mode, app::Mode.LIT);
	test::eq(a.preview.width, 32u);

	uint before = a.preview.revision;
	a.move_light(0.3f, 0);
	test::gt(a.preview.revision, before);

	char[] plain = fixtures::plain(mem, vk::R8G8B8A8_UNORM, 8, 1, 1);
	defer free(plain);
	a.open_bytes("plain.ktx2", plain)!!;
	a.set_mode(LIT);
	test::eq(a.mode, app::Mode.IMAGE);
}

fn void a_file_compared_with_itself_has_no_difference()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.open_bytes("wall.ktx2", file)!!;
	a.compare_bytes("same.ktx2", file)!!;

	test::eq(a.mode, app::Mode.DIFF);
	test::eq(a.compare.measured, true);
	foreach (db : a.compare.psnr.db) test::eq(db, double::inf);
	test::eq(a.preview.pixels[0:4], (char[]){ 0, 0, 0, 255 });

	a.close_compare();
	test::eq(a.mode, app::Mode.IMAGE);
}

fn void a_png_of_the_same_size_compares()
{
	char[] file = fixtures::plain(mem, vk::R8G8B8A8_UNORM, 8, 1, 1);
	defer free(file);
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.open_bytes("plain.ktx2", file)!!;

	// The same colour, one step brighter in red.
	char[] rgba = fixtures::face_colour(mem, 8, 0);
	defer free(rgba);
	foreach (i, &c : rgba) if (i % 4 == 0) *c += 1;
	image::Image img = { .width = 8, .height = 8, .bit_depth = 8, .format = RGBA, .pixels = rgba };
	char[] bytes = png::save_bytes(&img)!!;
	defer free(bytes);
	a.compare_bytes("other.png", bytes)!!;

	test::eq_approx(a.compare.psnr.db[0], 48.1308, delta: 0.001);
	test::eq(a.compare.psnr.db[1], double::inf);
	test::eq(a.preview.pixels[0], (char)app::DIFF_SCALE);

	// A PNG of another size has nothing to match, and the canvas says so.
	image::Image small = { .width = 4, .height = 4, .bit_depth = 8, .format = RGBA, .pixels = rgba[:64] };
	char[] small_bytes = png::save_bytes(&small)!!;
	defer free(small_bytes);
	a.compare_bytes("small.png", small_bytes)!!;
	test::eq(a.preview.is_empty(), true);
	test::eq(a.blank, "The other file has no 8 × 8 image at level 0, layer 0, face 0.");
}

fn void an_undecodable_file_leaves_the_canvas_blank_with_a_reason()
{
	char[] file = fixtures::astc(mem);
	defer free(file);
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.open_bytes("astc.ktx2", file)!!;
	test::eq(a.preview.is_empty(), true);
	test::eq(a.blank, "Can't decode ASTC 4x4 yet.");
	a.build_thumbs();
	test::eq(a.thumb_count, 0);
}

fn void thumbnails_cover_every_layer_and_face()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.open_bytes("wall.ktx2", file)!!;
	a.build_thumbs();
	test::eq(a.thumb_count, 4);
	test::eq(a.thumbs[1].caption, "L0 alpha: height");
	test::eq(a.thumbs[3].caption, "L1 alpha: roughness");

	char[] cube = fixtures::plain(mem, vk::R8G8B8A8_UNORM, 8, 6, 1);
	defer free(cube);
	a.open_bytes("cube.ktx2", cube)!!;
	a.build_thumbs();
	test::eq(a.thumb_count, 12);
	test::eq(a.thumbs[5].caption, "L0 +Y alpha");
	// Face 2's alpha is 200 everywhere.
	test::eq(a.thumbs[5].picture.pixels[0:4], (char[]){ 200, 200, 200, 255 });
}

fn void recent_files_are_newest_first_without_repeats()
{
	app::AppState a;
	a.init(mem);
	defer a.free();
	a.remember("a.ktx2");
	a.remember("b.ktx2");
	a.remember("a.ktx2");
	test::eq(a.recent.len(), 2);
	test::eq(a.recent[0], "a.ktx2");
	for (int i = 0; i < 20; i++) a.remember(string::tformat("%d.ktx2", i));
	test::eq(a.recent.len(), app::MAX_RECENT);
	test::eq(a.recent[0], "19.ktx2");
}
