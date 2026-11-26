<*
 The paths that touch the disk: the open dialog and the recent list. Each
 test writes a fixture into a fresh directory under the system's temp
 directory and removes it after.
*>
module ktxview_test::files_test @test;
import ktxview::app, ktxview::ui;
import ktxview_test::fixtures;
import ktx::basis;
import std::io, std::io::file, std::io::path;
import std::core::string;

fn void the_open_dialog_opens_a_file_and_remembers_it() => @pool()
{
	String dir = fixtures::scratch_dir("dialog");
	defer (void)path::rmtree(path::tnew(dir)!!);
	String wall = string::tformat("%s/wall.ktx2", dir);
	char[] file = fixtures::material(mem, basis::UASTC_4X4);
	defer free(file);
	file::save(wall, file)!!;

	fixtures::Rig rig;
	rig.open("", {});
	defer rig.free();
	rig.shell.browse_dir = dir.copy(mem);

	rig.press({ LEFT_CTRL, O });
	test::eq(rig.shell.dialog_open, true);
	// A click selects the row and a second one opens it.
	rig.click_text("wall.ktx2");
	rig.click_text("wall.ktx2");

	test::eq(rig.shell.dialog_open, false);
	test::eq(rig.app.has_doc, true);
	test::eq(rig.app.doc.name(), "wall.ktx2");
	test::eq(rig.app.recent[0], wall);
	test::eq(rig.shell.recent_items[0].label, wall);
	test::eq(rig.app.preview.width, 32u);
}

fn void a_file_that_will_not_open_leaves_a_message() => @pool()
{
	String dir = fixtures::scratch_dir("broken");
	defer (void)path::rmtree(path::tnew(dir)!!);
	String bad = string::tformat("%s/bad.ktx2", dir);
	file::save(bad, "not a texture")!!;

	fixtures::Rig rig;
	rig.open("", {});
	defer rig.free();
	ui::open_file(rig.ui, bad);
	test::eq(rig.app.has_doc, false);
	test::eq(rig.app.message.starts_with("Can't open"), true);
	test::eq(rig.app.recent.len(), 0);
}

fn void the_recent_list_survives_a_restart() => @pool()
{
	String dir = fixtures::scratch_dir("recent");
	defer (void)path::rmtree(path::tnew(dir)!!);
	String list = string::tformat("%s/recent", dir);

	app::AppState first;
	first.init(mem);
	first.load_recent(list);
	first.remember("/a.ktx2");
	first.remember("/b.ktx2");
	first.free();

	app::AppState second;
	second.init(mem);
	defer second.free();
	second.load_recent(list);
	test::eq(second.recent.len(), 2);
	test::eq(second.recent[0], "/b.ktx2");
	test::eq(second.recent[1], "/a.ktx2");
}
