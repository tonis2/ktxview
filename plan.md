## 1. ktxview, a KTX2 viewer

Planned 2026-11-26. Phases 1 to 3 are built; phase 4 is not started.

The materials are one `.ktx2` each: two layers, a map in RGB and a grey map in
alpha, with the layout in the metadata, for example
`three.layers = "srgb rgb=basecolor a=height; linear rgb=normal a=roughness"`.
No image viewer opens these files. Before this, the only way to see inside one
was `ktx info` plus `ktx extract` per layer, montaged by hand.

The viewer opens any KTX2 the pipeline makes and shows:
- the header, the format, the mip levels and the metadata;
- every layer, face and level;
- each channel on its own, named from `three.layers`;
- a tiled view to check seams;
- a lit preview of a packed material, and the difference against another file.

### 1a. Decisions

- **Repo:** `~/Documents/c3/ktxview`, a C3 executable `ktxview`. Local only;
  nothing is pushed without asking.
- **Dependencies follow Rigsmith:**
  - three.c3 as a git submodule at `libs/three`, with
    `dependency-search-paths: ["libs-dev", "libs/three/lib", "libs"]`;
  - `dependencies: ["cui", "vk", "c3w", "image", "font", "ktx"]`;
  - `libs-dev/` holds symlinks to the three.c3 working copies of the libraries,
    so a library can change while the viewer builds against it. It is gitignored.
  - The cui inside three.c3, not the stale standalone clone without `update_pixels`.
- **UI:** cui's own `Renderer` in `ON_DEMAND` mode, so the app idles at about 0%
  CPU. ESC does not quit (Ctrl+Q or the window's close button do), because
  menus and dialogs use it.
- **Layout:** Blender-like. A menu bar, a toolbar, an `AreaHost` workspace
  whose panes offer three views as tabs (Image, Info, Overview), and a status
  line. It opens with Info on the left and Image on the right.
- **Decoding stays on the CPU.** Every image is decoded to RGBA8 with `ktx.c3l`
  and shown through cui's RGBA8 textures. The swapchain is UNORM, so bytes
  display as they are: sRGB colour looks right and data maps show their stored
  values.

### 1b. Phase 1: open a file and show it

1. **Repo skeleton:** `project.json`, `.gitmodules`, `README.md`, `AGENTS.md`,
   this plan. `src/main.c3` opens the window and runs the frame loop.
2. **`src/doc.c3`, the opened file.** It reads the bytes once and answers:
   - `info`: `container::describe` (header, scheme, level index, DFD, metadata);
   - `image(level, layer, face)`: RGBA8, decoded on demand and cached.
     - A Basis file (`basis::info` succeeds) uses `basis::transcode_levels`, all
       levels of one layer and face at once.
     - Any other file uses `container::read` → `Texture.image` →
       `codec::decode_image`.
     - A format with no decoder (ASTC, ETC2, BC6H, float) opens: the info panel
       fills in and the canvas says "Can't decode ASTC 4x4 yet."
3. **`container::describe` in `ktx.c3l`** (`src/ktx/describe.c3`): what `ktx
   info` printed inline. `src/cli/info.c3` and the viewer both call it.
4. **Canvas** (`src/canvas.c3`): `View2D` pan and zoom through `Clip` +
   `set_content_transform`, as `NodeGraph` does. The wheel zooms at the pointer,
   a drag pans, F frames, 1 is 1:1. A smaller mip keeps the image's size on
   screen. Two texture slots: filtered up to 1:1, nearest past it.
5. **Info panel:** name and size, format and vkFormat, dimensions, levels,
   layers, faces, supercompression, DFD model, transfer, primaries and block,
   whether it decodes, GPU memory as BC7/ASTC 4×4 and as RGBA8, the parsed
   `three.layers`, each metadata entry in a `Disclosure`, and the level index.
6. **Opening files:** the command line, a drop on the window (Wayland only),
   File › Open (`FileBrowser`, mask `*.ktx2`), and the Recent menu, kept in
   `~/.config/ktxview/recent`.

### 1c. Phase 2: what's inside

1. **Toolbar:** layer tabs named from `three.layers` ("0 basecolor + height"),
   cubemap faces, the mip `Slider` with the level's size, the channel
   `Segmented` (RGB | RGBA | R | G | B | A, renamed from the metadata, so A on
   layer 0 reads "height"), Tile 3×3, and Image | Lit | Diff when the file
   offers them. A control the file has no use for is left out: no layer tabs
   for one layer, no slider for one level.
2. **Channel views** are built on the CPU (`src/pixels.c3`): one channel spread
   to grey, RGB with alpha forced opaque, or RGBA over a checkerboard of
   8-texel squares.
3. **Overview:** a `Grid` of thumbnails of every layer and face, as colour and
   as alpha, at the largest level no bigger than 256. Clicking one opens it.
4. **`src/layers.c3`** parses `three.layers` into a space and channel names per
   layer; a file without it, or with a malformed one, gets plain labels.
5. **Status line:** the texel under the pointer (x, y, level), its RGBA as bytes
   and 0–1, the layer's channel names, the zoom, PSNR in the diff view, and the
   last problem (a file that would not open).
6. **Shortcuts** go through `AppRoot.on_key`: `[` `]` layers, Shift+`[` `]`
   faces, `,` `.` levels, C R G B A channels, T tile, O overview, I image, M lit,
   D diff, F frame, 1 actual size, Ctrl+O open, Ctrl+D compare, Ctrl+Q quit.

### 1d. Phase 3: material preview and compare

1. **Lit view**, for a file whose `three.layers` names basecolor, normal and
   roughness: a CPU-shaded flat patch, ambient plus N·L diffuse plus a
   Blinn-Phong highlight whose sharpness follows roughness, shaded in linear
   light. Dragging with L held moves the light. Rows are spread across threads
   with `ktx::parallel`; the image is shaded again only when the light, level,
   layer or face changes.
2. **Compare:** File › Compare with… opens a PNG or a second KTX2. The canvas
   shows the absolute difference ×8; the PSNR per channel is in the status line
   and the info panel. A KTX2 is compared at the same level, layer and face; a
   PNG against any level of its size.

### 1e. Phase 4: formats the library can't decode yet

Not started.

1. **An ASTC LDR decoder in `ktx.c3l`** (`src/ktx/astc.c3`), hooked into
   `codec::decode_image`: every block size, every LDR colour mode, 1–4
   partitions, dual plane, weight grid interpolation, void-extent blocks;
   checked against `astcenc -decode_unorm8`.
2. **ETC2/EAC** after that. **BC6H and float formats** tone-mapped, later still.

### 1f. Verification

- `c3c test --test-noleak`: headless cui tests over fixtures made in the test
  with ktx.c3l (UASTC and ETC1S arrays, BC7, an RGBA8 cubemap, ASTC). They click
  layer tabs, channel buttons, the mip slider, the overview and the file dialog,
  and check the preview's CPU pixels; the A view of layer 0 equals the height
  bytes from `basis::transcode`.
- `ktx info`'s output is unchanged on `test/images` and on files made with
  `ktx-linux create`, except that BasisLZ (ETC1S) files now list their metadata.
- By eye, with `--screenshot`: `stone_wall.ktx2` and `roof_tile.ktx2` match the
  contact sheet.

### 1g. Done and to do (2026-11-26)

`c3c build` is clean; `c3c test --test-noleak`: 42 passed. ktx.c3l: 115 passed.
Published 2026-11-26 as github.com/tonis2/ktxview, with `libs/three` at three.c3
bf97c54, whose `ktx.c3l` (bb1a6d2) has the UASTC→ASTC commit and
`container::describe`.

#### Done

- **Phases 1, 2 and 3** as above.
- **`container::describe`** in ktx.c3l: `src/ktx/describe.c3` (new: `FileInfo`,
  `LevelEntry`, `DfdStatus`, `describe`, `FileInfo.text`, `KvPair.text`,
  `scheme_name`), `test/describe_test.c3` (new), and `src/cli/info.c3` switched
  over. It reads the key/value block itself, so it also answers for BasisLZ files,
  which `container::read` refuses.
- **Checked by screenshot** on stone_wall: the info panel with `three.layers`,
  layer 0 RGB, layer 0 A as height, layer 1 RGB, the overview, the 3×3 tile and
  the lit view. Also a 1024² RGBA8 cubemap, ETC1S and BC7 files made with
  `ktx-linux create`, and an ASTC file from `ktx-linux transcode -t astc`, which
  shows "Can't decode ASTC 4x4 yet." with its info.
- **4096² two-layer UASTC:** opening and transcoding a layer takes about 0.2 s,
  another layer 0.13 s, a channel switch under 10 ms, a lit shade about 35 ms.
  The process holds about 350 MB: every level of each decoded layer as RGBA8
  (89 MB a layer), the preview, and the file.

#### To do

- **Phase 4.**
- **Big files:** decoding is synchronous, so a 4096² file blocks the window for
  a fraction of a second, and every change uploads a 64 MB preview. A level
  that is never shown is still decoded for a Basis file, since its levels are
  transcoded together.
- **Drop on X11:** c3w only collects drops on Wayland.
- **Tile seams:** the 3×3 tiles overlap by one screen pixel so the rect edges'
  antialiasing doesn't draw a seam the texture doesn't have.

#### cui gaps

Worked around here; each belongs in cui.

- **Text painted before the first frame has no glyph atlas.** The renderer
  creates the atlas in its first `upload`, and drawings cached before that keep
  texture 0. ktxview's `build` doesn't flush for this reason.
- **`LiveLabel` repaints but doesn't re-layout** when its text changes, so an
  ELLIPSIS or WRAP label keeps its first text's size. The status line uses
  VISIBLE.
- **Texture sampling with a non-uniform index:** the fragment shader indexes
  `textures[]` without NonUniform, and on RADV stray texels from a neighbouring
  textured rect show up in the overview's thumbnails (the CPU pixels are right).
- **No sub-rect or repeat UVs** on a textured rect, so tiling takes nine rects.
- **One mip per texture:** a zoomed-out image is sampled without mips and
  aliases.
- **No per-texture free:** ktxview makes all its textures at startup (two for
  the preview, 24 for thumbnails) and refills them with `update_pixels`.
- **A Column with a flexible child:** `VDock` here; one child takes the height
  the others leave.
- **`Bar`:** a full-width strip with a background and a rule, padded around
  one child.
- **`MenuItem.on_select` has no per-item context,** so the Recent menu needs one
  callback per slot.
