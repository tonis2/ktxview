module ktxview_test::ui_test @test;
import ktxview::app, ktxview::ui, ktxview::layers;
import ktxview_test::fixtures;
import ktx::basis, ktx::vk;
import cui, cui::widgets;
import std::core::string;
import std::math;

fn void clicking_a_layer_tab_shows_that_layer()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	rig.click_text("1 normal + roughness");
	test::eq(rig.app.layer, 1u);
	// Layer 1 is a flat normal: the preview is its RGB, made opaque.
	char[] normal = rig.app.doc.image(0, 1, 0)!!;
	test::eq(rig.preview_at(5, 5)[:3], normal[(5 * 32 + 5) * 4:3]);
	test::eq(rig.preview_at(5, 5)[3], (char)255);
	test::le(math::abs((int)normal[(5 * 32 + 5) * 4] - 128), 2);
	// The channel buttons now carry layer 1's names.
	test::eq(@ok(rig.ui.find_text("roughness")), true);
}

fn void the_alpha_button_shows_the_transcoded_height()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	rig.click_text("height");
	test::eq(rig.app.channel, layers::Channel.A);
	basis::Transcoded want = basis::transcode(mem, file, 0, 0, 0, basis::TF_RGBA32, 4)!!;
	defer free(want.data);
	for (uint y = 0; y < 32; y += 7)
	{
		for (uint x = 0; x < 32; x += 5)
		{
			char height = want.data[((sz)y * 32 + x) * 4 + 3];
			test::eq(rig.preview_at(x, y)[..], (char[]){ height, height, height, 255 });
		}
	}
}

fn void the_mip_slider_steps_through_levels()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	Element* slider = rig.ui.find_id("mip")!!;
	Vec2 left = slider.absolute + (Vec2){ 90, slider.size.y * 0.5f };
	Vec2 right = slider.absolute + (Vec2){ slider.size.x - 4, slider.size.y * 0.5f };
	rig.ui.drag(left, right);
	test::eq(rig.app.level, 5u);
	test::eq(rig.app.preview.width, 1u);
	// The drag kept its slider: the toolbar was not rebuilt under it.
	test::eq(rig.ui.find_id("mip")!!, slider);
}

fn void keys_switch_layer_level_channel_and_tiling()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	rig.press({ RIGHT_BRACKET });
	test::eq(rig.app.layer, 1u);
	rig.press({ LEFT_BRACKET });
	test::eq(rig.app.layer, 0u);
	rig.press({ PERIOD });
	rig.press({ PERIOD });
	test::eq(rig.app.level, 2u);
	test::eq(rig.app.preview.width, 8u);
	rig.press({ COMMA });
	test::eq(rig.app.level, 1u);
	rig.press({ A });
	test::eq(rig.app.channel, layers::Channel.A);
	rig.press({ C });
	test::eq(rig.app.channel, layers::Channel.RGB);
	rig.press({ C });
	test::eq(rig.app.channel, layers::Channel.RGBA);
	rig.press({ T });
	test::eq(rig.app.tiled, true);
	test::eq(rig.shell.plane_size().x, 3.0f * 16);
}

fn void the_overview_opens_an_image_in_the_canvas()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	rig.press({ O });
	test::eq(ui::showing(rig.ui, OVERVIEW), true);
	test::eq(rig.app.thumb_count, 4);
	rig.click_text("L1 alpha: roughness");
	test::eq(ui::showing(rig.ui, IMAGE), true);
	test::eq(rig.app.layer, 1u);
	test::eq(rig.app.channel, layers::Channel.A);
	// Roughness falls from 255 at the top row.
	test::ge(rig.preview_at(0, 0)[0], (char)250);
}

fn void the_lit_view_follows_the_light_drag()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	rig.press({ M });
	test::eq(rig.app.mode, app::Mode.LIT);
	float x_before = rig.app.light_x;
	uint rev = rig.app.preview.revision;
	Element* canvas = rig.ui.find(ImageView)!!;
	Vec2 mid = canvas.absolute + canvas.size * 0.5f;
	rig.ui.drag(mid, mid + (Vec2){ 120, 0 }, held: { L });
	test::gt(rig.app.light_x, x_before);
	test::gt(rig.app.preview.revision, rev);
	rig.press({ M });
	test::eq(rig.app.mode, app::Mode.IMAGE);
}

fn void the_wheel_zooms_and_a_drag_pans()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	Element* canvas = rig.ui.find(ImageView)!!;
	Vec2 mid = canvas.absolute + canvas.size * 0.5f;
	float framed = rig.shell.view.scale();
	rig.ui.wheel(mid, 1);
	test::gt(rig.shell.view.scale(), framed);
	Vec2 pan = rig.shell.view.pan;
	rig.ui.drag(mid, mid + (Vec2){ 50, 0 });
	test::lt(rig.shell.view.pan.x, pan.x);
	rig.press({ KEY_1 });
	test::eq(rig.shell.view.scale(), 1.0f);
}

fn void the_status_line_reads_the_texel_under_the_pointer()
{
	char[] file = fixtures::plain(mem, vk::R8G8B8A8_UNORM, 8, 1, 1);
	defer free(file);
	fixtures::Rig rig;
	rig.open("plain.ktx2", file);
	defer rig.free();

	Element* canvas = rig.ui.find(ImageView)!!;
	rig.ui.hover(canvas.absolute + canvas.size * 0.5f, 0.05f);
	test::eq(rig.shell.hover.on, true);
	String line = ui::status_text(canvas);
	defer line.free(mem);
	test::eq(line.contains("RGBA 0 255 100 200"), true);
	test::eq(line.contains("0.784"), true);
}

fn void an_undecodable_file_still_fills_the_info_panel()
{
	char[] file = fixtures::astc(mem);
	defer free(file);
	fixtures::Rig rig;
	rig.open("astc.ktx2", file);
	defer rig.free();

	test::eq(rig.app.blank, "Can't decode ASTC 4x4 yet.");
	test::eq(rig.info("Decodes"), "not yet: ASTC 4x4");
	test::eq(rig.info("Size"), "16 × 16");
	test::eq(rig.info("Format"), "ASTC 4x4");
}

fn void the_info_panel_lists_the_metadata()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	fixtures::Rig rig;
	rig.open("wall.ktx2", file);
	defer rig.free();

	test::eq(@ok(rig.ui.find_text("three.layers")), true);
	test::eq(@ok(rig.ui.find_text(fixtures::LAYERS)), true);
	test::eq(rig.info("Format"), "UASTC 4x4");
	test::eq(rig.info("Layer 1"), "linear rgb=normal a=roughness");
	test::eq(rig.info("Supercompression"), "Zstandard");
}

fn void ctrl_o_opens_the_file_dialog()
{
	fixtures::Rig rig;
	rig.open("", {});
	defer rig.free();

	test::eq(rig.app.has_doc, false);
	rig.press({ LEFT_CTRL, O });
	test::eq(rig.shell.dialog_open, true);
	test::eq(rig.shell.pick, ui::Pick.OPEN);
	test::eq(@ok(rig.ui.find_id("browser")), true);
	// Shortcuts stay with the dialog while it is up.
	rig.press({ T });
	test::eq(rig.app.tiled, false);
}

fn void file_open_from_the_menu_shows_the_dialog()
{
	fixtures::Rig rig;
	rig.open("", {});
	defer rig.free();

	rig.click_text("File");
	rig.click_text("Open…");
	test::eq(rig.shell.dialog_open, true);
	FileBrowser* browser = rig.ui.find_id("browser")!!.widget_as(FileBrowser);
	test::eq(browser.mask.len, 1);
	test::eq(browser.mask[0], "*.ktx2");
}

fn void the_toolbar_offers_only_what_the_file_has()
{
	char[] file = fixtures::plain(mem, vk::R8G8B8A8_UNORM, 8, 6, 1);
	defer free(file);
	fixtures::Rig rig;
	rig.open("cube.ktx2", file);
	defer rig.free();

	// One layer, one level, no material: faces, channels and tiling only.
	test::eq(@ok(rig.ui.find_id("layers")), false);
	test::eq(@ok(rig.ui.find_id("mip")), false);
	test::eq(@ok(rig.ui.find_id("modes")), false);
	rig.click_text("-Z");
	test::eq(rig.app.face, 5u);
	test::eq(rig.preview_at(0, 0)[..], (char[]){ 200, 55, 100, 255 });
}
