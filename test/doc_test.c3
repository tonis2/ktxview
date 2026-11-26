module ktxview_test::doc_test @test;
import ktxview::doc, ktxview::layers;
import ktxview_test::fixtures;
import ktx::basis, ktx::container, ktx::vk;
import std::math;

fn void a_uastc_material_opens_with_its_layer_names()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	doc::Document d = doc::from_bytes(mem, "dir/wall.ktx2", file)!!;
	defer d.free();

	test::eq(d.name(), "wall.ktx2");
	test::eq(d.codec, doc::Codec.BASIS);
	test::eq(d.width, 32u);
	test::eq(d.levels, 6u);
	test::eq(d.layers, 2u);
	test::eq(d.faces, 1u);
	test::eq(doc::format_name(tmem, &d.info), "UASTC 4x4");
	test::eq(d.info.text(layers::KEY)!!, fixtures::LAYERS);
	test::eq(d.named, true);
	test::eq(d.layer_names(1).label(A), "roughness");
	test::eq(d.is_material(), true);
}

fn void basis_images_are_the_transcoder_s_rgba()
{
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	doc::Document d = doc::from_bytes(mem, "wall.ktx2", file)!!;
	defer d.free();

	for (uint level = 0; level < d.levels; level++)
	{
		basis::Transcoded want = basis::transcode(mem, file, level, 1, 0, basis::TF_RGBA32, 4)!!;
		defer free(want.data);
		test::eq(d.image(level, 1, 0)!!, want.data);
		test::eq(want.width, d.level_width(level));
	}
}

fn void an_etc1s_array_opens_and_decodes()
{
	char[] file = fixtures::material(mem, basis::ETC1S);
	defer free(file);
	doc::Document d = doc::from_bytes(mem, "wall.ktx2", file)!!;
	defer d.free();

	test::eq(doc::format_name(tmem, &d.info), "ETC1S");
	test::eq(container::scheme_name(d.info.scheme), "BasisLZ");
	test::eq(d.named, true);
	test::eq(d.image(0, 0, 0)!!.len, 32 * 32 * 4);
}

fn void a_bc7_file_decodes_every_level()
{
	char[] file = fixtures::plain(mem, vk::BC7_UNORM, 16, 1, 3);
	defer free(file);
	doc::Document d = doc::from_bytes(mem, "bc7.ktx2", file)!!;
	defer d.free();

	test::eq(d.codec, doc::Codec.PLAIN);
	test::eq(doc::format_name(tmem, &d.info), "BC7_UNORM");
	test::eq(d.named, false);
	for (uint level = 0; level < 3; level++)
	{
		char[] image = d.image(level, 0, 0)!!;
		test::eq(image.len, (sz)d.level_width(level) * d.level_height(level) * 4);
		// One colour encodes almost exactly in BC7.
		test::le(math::abs((int)image[0] - 0), 2);
		test::le(math::abs((int)image[1] - 255), 2);
	}
}

fn void each_cube_face_is_its_own_image()
{
	char[] file = fixtures::plain(mem, vk::R8G8B8A8_UNORM, 8, 6, 1);
	defer free(file);
	doc::Document d = doc::from_bytes(mem, "cube.ktx2", file)!!;
	defer d.free();

	test::eq(d.faces, 6u);
	for (uint face = 0; face < 6; face++)
	{
		char[] image = d.image(0, 0, face)!!;
		test::eq((uint)image[0], face * 40);
		test::eq((uint)image[1], 255 - face * 40);
		test::eq((uint)image[3], 200u);
	}
}

fn void astc_opens_but_says_it_cannot_decode()
{
	char[] file = fixtures::astc(mem);
	defer free(file);
	doc::Document d = doc::from_bytes(mem, "astc.ktx2", file)!!;
	defer d.free();

	test::eq(d.codec, doc::Codec.NONE);
	test::eq(d.cannot_decode, "ASTC 4x4");
	test::eq(d.width, 16u);
	test::@error(d.image(0, 0, 0), doc::NO_DECODER);
}

fn void a_file_that_is_not_ktx2_is_refused()
{
	char[64] junk;
	test::@error(doc::from_bytes(mem, "junk.ktx2", junk[..]), container::BAD_IDENTIFIER);
}

fn void gpu_sizes_count_blocks_and_texels()
{
	char[] file = fixtures::plain(mem, vk::R8G8B8A8_UNORM, 8, 6, 1);
	defer free(file);
	doc::Document d = doc::from_bytes(mem, "cube.ktx2", file)!!;
	defer d.free();
	test::eq(d.gpu_bytes(RGBA8), 8ul * 8 * 4 * 6);
	test::eq(d.gpu_bytes(BLOCK_4X4), 4ul * 16 * 6);
}
