# Layers

Dependencies point one way: `layers` and `doc`, then `pixels`, then `app`, then the
`ui` module, then `main`.

- `src/layers.c3`: reads `three.layers`. No files, no decoding.
- `src/doc.c3`: an opened file: its bytes, `container::describe`, and RGBA8 images
  decoded on demand with ktx.c3l.
- `src/pixels.c3`: CPU image work: channel views, the lit shading, the difference.
- `src/app.c3`: `AppState`, the commands, and the pictures the UI draws. No cui.
- `src/shell.c3`, `commands.c3`, `canvas.c3`, `panels.c3` (module `ktxview::ui`):
  the interface. Commands change the app, then call `changed(ui, ...)`.
- `src/main.c3`: the window, the GPU textures, drops, `--screenshot`.

# Testing

    c3c test --test-noleak
    c3c test --test-noleak --test-filter <name>

Only run the leak-checked suite (a plain `c3c test`) when the owner asks for it.

Fixtures are made in memory by `test/fixtures.c3` with ktx.c3l; no binary files are
checked in. UI tests run headless (`cui::new_ui`, no GPU) through `fixtures::Rig`.

Check the window with `build/ktxview --screenshot out.png file.ktx2`: it renders,
saves and quits. Don't leave windows open.

# Widgets

Reusable widgets belong in cui (`libs/cui.c3l`), not here. When the viewer
needs something cui lacks, write the smallest local version and note it under
"cui gaps" in plan.md.

# Libraries

cui, vk, c3w, image, font and ktx are each a submodule in `libs/` (`cui.c3l`,
`vulkan.c3l`, `window.c3l`, `image.c3l`, `font.c3l`, `ktx.c3l`).
