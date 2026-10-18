# Constellate Blender pipeline (headless, Blender 5.2.2)

All 3D assets, textures, presentation renders and the app icon are produced by Python scripts driven
through Blender's CLI. No `.blend` files are kept; the scripts are the source of truth.

```
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
cd Constellate/Blender/scripts

# everything (assets -> textures -> renders -> icon); ~15 min on an M3 (sky render ~9 min)
$BLENDER --background --python build_all.py
./make_icon_set.sh                      # sips downscales for the macOS icon slots + Docs/images/icon-256.png

# pieces
$BLENDER --background --python build_assets.py                         # all 7 USDZ
$BLENDER --background --python build_assets.py -- HostOrb Beacon       # subset
$BLENDER --background --python build_textures.py                       # Sky_Dark (Cycles) + Sky_Tint + Floor_Grid
$BLENDER --background --python build_textures.py -- --fallback         # numpy sky instead of Cycles (seconds)
$BLENDER --background --python build_textures.py -- --derived-only     # only Sky_Tint + Floor_Grid from existing Sky_Dark
$BLENDER --background --python render_assets.py                        # all presentation renders
$BLENDER --background --python render_assets.py -- host_orb theme_dark # subset
$BLENDER --background --python render_icons.py                         # all platform icons + icon_sheet.png
$BLENDER --background --python render_icons.py -- --sheet-only         # only re-compose icon_sheet.png
./make_icon_set.sh                                                      # then: mac_* downscales + Docs/images/icon-256.png
```

`build_all.py` accepts `--skip-assets --skip-textures --skip-renders --skip-icons --legacy-icon --fallback-sky`.

## Files

| Script | Output |
|---|---|
| `constellate_lib.py` | shared helpers: palette, materials, primitives, USDZ export + verification, PNG writer, Cycles/Metal setup, glare, camera framing |
| `build_assets.py` | `Constellate/Resources/Assets3D/{HostOrb,ClusterOrb,Avatar_Bust,Beacon,ReviewPin,Stage_Ring,Pointer_Dart}.usdz` |
| `build_textures.py` | `Constellate/Resources/Textures/{Sky_Dark,Sky_Tint,Floor_Grid}.png` |
| `render_assets.py` | `Blender/renders/*.png` (1280x960); its single-icon path is legacy (`build_all.py --legacy-icon`) |
| `render_icons.py` | platform icons from one scene / one ortho camera: iOS `AppIcon-1024{,-dark,-tinted}.png`, macOS `mac_1024.png` (+ `Blender/renders/icon_macos.png`), visionOS `AppIcon.solidimagestack/*/Content.imageset/{Back,Middle,Front}.png`, preview `Blender/renders/icon_sheet.png` |
| `make_icon_set.sh` | `mac_16 … mac_512.png` (sips from `mac_1024.png`) + `Docs/images/icon-256.png` (from the iOS icon) |

## Conventions baked into the exporter

- Authored in Blender Z-up metres; exported with `convert_orientation` (up **Y**, forward **-Z**), which the
  exporter realises as a root `Xform` with `rotateXYZ(-90,0,0)`; stage metadata `upAxis = Y`, `metersPerUnit = 1`.
  Blender **+Y** becomes USD **-Z** (RealityKit entity forward): the avatar's face and the dart's tip point that way.
- `triangulate_meshes=True`, `export_materials=True`, `generate_preview_surface=True` -> `UsdPreviewSurface`.
  Emission strength is baked into `emissiveColor` (e.g. Core = #E9E4FF x 4).
- Blender 5.2's exporter ignores the Principled **Alpha** socket (it only maps transmission -> opacity), so
  `export_usdz()` re-opens the package with the bundled `pxr`, writes `inputs:opacity` for translucent
  materials and re-packages with `UsdUtils.CreateNewUsdzPackage`. Transmission is render-only
  (`constellate_lib.GLASS_TRANSMISSION`).
- Fixed material names (app swaps by name): `Core`, `Band0`…`Band3` (one material per host-orb band so each
  band keeps its own emissive colour in USD), `Shell`, `Accent`, `Glass`, `Base`.
- Every USDZ is verified: zip integrity, `upAxis`, materials, world bbox, triangle budget (< 20k), size (< 2 MB).
  `usdchecker --arkit` passes for all seven.

## Textures

- `Sky_Dark.png` 4096x2048: Cycles, panoramic equirectangular camera, pure-emission world
  (gradient #0A0B14 -> #121733 -> #05070F, Noise nebula tinted #1A1F4A, Voronoi-thresholded 1–2 px stars).
  32 samples, pixel filter 1.0, **denoise off on purpose** (no Monte-Carlo noise in an emission-only world;
  OIDN would smear the stars). `--fallback` reproduces the look with numpy in seconds.
- `Sky_Tint.png`: 8-bit grayscale luminance of the render, normalised so the brightest sky region = 1.0
  (measured on 8x8 block means so stars don't skew it). App multiplies by `HSL(H,0.34,0.17)`.
- `Floor_Grid.png` 2048x2048 straight-alpha RGBA: white RGB, 24 one-metre cells, stronger line every 4 m,
  smooth radial falloff to 0 at the edge. Written by `constellate_lib.write_png` (zlib), no colour management.

## Renders

Cycles on Metal, 64 samples, OIDN denoise, AgX view transform (so strength-4 emissives roll off), compositor
Bloom glare, world = `Sky_Dark.png` (dark) or `Sky_Tint.png` x `HSL(210,0.34,0.17)` (tinted Ocean, accents
`HSL(210,0.75,0.72)`), floor = dark plane with the grid texture emissive in `#2A3150`.

## App icons (`render_icons.py`)

One scene (1 unit = 1024 px, orthographic camera along +Y) with collections `Back` (radial backdrop, floor-hint
glow, relation lines, stars), `BackOuter` (stars outside the mac tile), `Middle` (7 code cards with cyan/amber/pink
border glints, 2 cluster orbs, 2 orbit rings), `Front` (host orb, scaled 1.5 -> 40 % of the width, core emission
tamed to 1.6 so the bands read), `MacTile` (analytic rounded-rect mesh, side 0.824, corner radius 22.4 %, solidified
+ bevelled, glossy coat for rim light). 128 samples, OIDN, AgX, bloom whose luminance is also written into alpha
(`SetAlpha` + shared Math nodes) so glow survives `film_transparent` layers.

| Output | How |
|---|---|
| `AppIcon-1024.png` | all collections, opaque |
| `AppIcon-1024-dark.png` | same from a rebuilt scene with near-black backdrop and glints x1.4 |
| `AppIcon-1024-tinted.png` | transparent render (backdrop hidden) -> Rec.709 luminance x1.25 -> grey RGBA |
| `mac_1024.png` | tile visible, backdrop hidden, transparent render, then numpy rounded-rect alpha clip (824 px / r 184.6) |
| visionOS `Back/Middle/Front.png` | same camera; Back opaque, Middle+Front transparent (fully transparent pixels get RGB 0) |
| `icon_sheet.png` | 1600x600 Cycles scene of image planes + labels; visionOS layers offset to show parallax, circle-cropped |

`Contents.json` of the appiconset lists the three iOS appearances (`luminosity: dark / tinted`) and points the
mac slots at `mac_*.png`; `AppIcon.solidimagestack` mirrors the CoulsonAndJarvis layer structure.
