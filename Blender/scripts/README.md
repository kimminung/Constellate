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
$BLENDER --background --python render_assets.py                        # all renders + icon
$BLENDER --background --python render_assets.py -- host_orb theme_dark # subset (no icon unless --icon)
$BLENDER --background --python render_assets.py -- --icon-only
```

`build_all.py` accepts `--skip-assets --skip-textures --skip-renders --skip-icon --fallback-sky`.

## Files

| Script | Output |
|---|---|
| `constellate_lib.py` | shared helpers: palette, materials, primitives, USDZ export + verification, PNG writer, Cycles/Metal setup, glare, camera framing |
| `build_assets.py` | `Constellate/Resources/Assets3D/{HostOrb,ClusterOrb,Avatar_Bust,Beacon,ReviewPin,Stage_Ring,Pointer_Dart}.usdz` |
| `build_textures.py` | `Constellate/Resources/Textures/{Sky_Dark,Sky_Tint,Floor_Grid}.png` |
| `render_assets.py` | `Blender/renders/*.png` (1280x960) and `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| `make_icon_set.sh` | `icon_16 … icon_1024.png` in the appiconset + `Docs/images/icon-256.png` |

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
