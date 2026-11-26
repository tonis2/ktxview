module ktxview_test::layers_test @test;
import ktxview::layers;
import ktxview_test::fixtures;

fn void the_pack_string_names_two_layers()
{
	layers::LayerMap map = layers::parse(fixtures::LAYERS)!!;
	test::eq(map.count, 2);
	test::eq(map.layers[0].space, layers::Space.SRGB);
	test::eq(map.layers[0].label(RGB), "basecolor");
	test::eq(map.layers[0].label(A), "height");
	test::eq(map.layers[1].space, layers::Space.LINEAR);
	test::eq(map.layers[1].label(RGB), "normal");
	test::eq(map.layers[1].label(A), "roughness");
	// What the description leaves out keeps its plain label.
	test::eq(map.layers[0].label(R), "R");
	test::eq(map.layers[1].label(RGBA), "RGBA");
}

fn void captions_read_like_tabs()
{
	layers::LayerMap map = layers::parse(fixtures::LAYERS)!!;
	String caption = map.layers[0].caption(tmem, 0);
	test::eq(caption, "0 basecolor + height");
	layers::Layer blank;
	test::eq(blank.caption(tmem, 3), "Layer 3");
}

fn void maps_are_found_by_name()
{
	layers::LayerMap map = layers::parse(fixtures::LAYERS)!!;
	layers::Place rough = map.find("roughness")!!;
	test::eq(rough.layer, 1);
	test::eq(rough.channel, layers::Channel.A);
	test::eq(rough.channel.byte(), 3u);
	test::@error(map.find("metalness"), layers::NOT_FOUND);
}

fn void single_channels_and_spacing_are_read()
{
	layers::LayerMap map = layers::parse("  linear r=metal g=rough  b=ao ;srgb rgba=albedo ;")!!;
	test::eq(map.count, 2);
	test::eq(map.layers[0].label(G), "rough");
	test::eq(map.layers[0].label(B), "ao");
	test::eq(map.layers[1].label(RGBA), "albedo");
	// A layer may leave its space unsaid.
	test::eq(layers::parse("rgb=x")!!.layers[0].space, layers::Space.UNSAID);
}

fn void malformed_descriptions_are_refused()
{
	test::@error(layers::parse(""), layers::MALFORMED);
	test::@error(layers::parse("srgb rgb="), layers::MALFORMED);
	test::@error(layers::parse("srgb xyz=normal"), layers::MALFORMED);
	test::@error(layers::parse("srgb linear rgb=a"), layers::MALFORMED);
	test::@error(layers::parse("cmyk rgb=a"), layers::MALFORMED);
	test::@error(layers::parse("srgb rgb=a; ; linear a=b"), layers::MALFORMED);
}
