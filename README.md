# ktxview

A desktop viewer for KTX2 textures. It opens any `.ktx2` the material pipeline
makes and shows what is inside: the header, the format, the levels and the
metadata; every layer, face and mip level; each channel on its own, named from
the file's `three.layers` entry; a 3×3 tile to check seams; a lit preview of a
packed material; and the difference against another file.

Everything is decoded on the CPU to RGBA8 with `ktx.c3l` and drawn with `cui`,
so what you see is what the file stores: sRGB colour looks right and data maps
show their raw values.

## Build

```sh
git submodule update --init   # cui, vulkan, window, image, font and ktx in libs/
c3c build                     # build/ktxview
c3c test --test-noleak
```

## Run

```sh
build/ktxview material.ktx2
build/ktxview --layer 1 --channel a material.ktx2
build/ktxview --view overview material.ktx2
build/ktxview --compare reference.png texture.ktx2
build/ktxview --view lit --screenshot lit.png material.ktx2   # render, save, quit
```

Files also open from **File › Open** (Ctrl+O), **Recent**, and by dropping one
on the window (Wayland only). The recent list is kept in
`~/.config/ktxview/recent`.

Options: `--layer n`, `--face n`, `--level n`, `--channel rgb|rgba|r|g|b|a`,
`--view image|overview|lit|diff`, `--tile`, `--compare file`, `--size WxH`,
`--screenshot out.png`.

## The window

- **Toolbar**: layer tabs (named from `three.layers`, such as "0 basecolor +
  height"), cubemap faces, the mip slider, the channel buttons (A on a
  basecolor + height layer reads "height"), Tile 3×3, and Image | Lit | Diff
  when the file offers them.
- **Panes**: Image, Info and Overview are tabs every pane offers. Right-click a
  pane to split or close it, the Blender way.
- **Canvas**: the wheel zooms at the pointer, a drag pans. Past 1:1 texels are
  drawn square. A see-through texel shows a checkerboard in RGBA.
- **Overview**: every layer and face as colour and as alpha; click one to open it.
- **Lit**: a flat patch shaded from basecolor, normal and roughness. Drag with
  L held to move the light.
- **Diff**: the absolute difference, ×8, and PSNR per channel in the status
  line and the info panel.
- **Status line**: the texel under the pointer, as bytes and as 0–1 values.

## Shortcuts

| Key | Does |
|---|---|
| Ctrl+O | Open a file |
| Ctrl+D | Compare with a .ktx2 or .png |
| Ctrl+Q | Quit |
| `[` `]` | Previous / next layer |
| Shift+`[` Shift+`]` | Previous / next cubemap face |
| `,` `.` | Larger / smaller mip level |
| C | Colour; again for colour with alpha |
| R G B A | One channel, as grey |
| T | Tile 3×3 |
| O | Overview |
| I | Back to the image |
| M | Lit material |
| D | Difference |
| F | Frame the image |
| 1 | Actual size |
| L + drag | Move the light (lit view) |

ASTC, ETC2, BC6H and float formats open and show their info, but the canvas
says it can't decode them yet.

## License

Apache-2.0, see `LICENSE`. The bundled DejaVu Sans font keeps its own license,
in `assets/DejaVuSans-LICENSE`.
