# Constellate Blender pipeline (headless, Blender 5.2.2)

All 3D assets, effect sprites, environment textures, presentation renders, constellation renders and the app icon
are produced by Python scripts driven through Blender's CLI. No `.blend` files are kept; the scripts are the
source of truth.

```
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
cd Constellate/Blender/scripts

# everything: assets -> star glyphs + FX -> textures -> renders -> constellation renders -> icons
$BLENDER --background --python build_all.py          # ≈ 70 min + icons on a 2-core CPU without a GPU (see below)
./make_icon_set.sh                                    # sips downscales for the macOS icon slots + Docs/images/icon-256.png

# pieces
$BLENDER --background --python build_assets.py                         # the 7 meeting USDZ
$BLENDER --background --python build_assets.py -- HostOrb Beacon       # subset
$BLENDER --background --python build_graph_assets.py                   # NodeStars.usdz + FX_*.png
$BLENDER --background --python build_graph_assets.py -- --fx-only FX_Ring.png
$BLENDER --background --python build_textures.py                       # Sky_Dark (Cycles) + Sky_Tint + Floor_Grid
$BLENDER --background --python build_textures.py -- --floor-only       # just the astrolabe floor (seconds)
$BLENDER --background --python build_textures.py -- --fallback         # numpy sky instead of Cycles (seconds)
$BLENDER --background --python build_textures.py -- --derived-only     # only Sky_Tint + Floor_Grid from existing Sky_Dark
$BLENDER --background --python render_assets.py -- host_orb theme_dark # presentation renders (subset)
$BLENDER --background --python render_graph.py                         # layout gallery + legends from Blender/data
$BLENDER --background --python render_graph.py -- celestial --eye --quick   # iterate on one layout fast
$BLENDER --background --python render_graph.py -- sphere --gallery     # re-render one layout, recompose the gallery
$BLENDER --background --python render_graph.py -- --hero              # README hero only (Docs/images/hero.png)
$BLENDER --background --python render_icons.py                         # all platform icons + icon_sheet.png
```

Measured on a 2-core cloud CPU (Cycles on CPU, no GPU): Cycles sky ≈ 5 min, the ten presentation renders ≈ 21 min,
the constellation renders (six layouts, eye view, gallery, two legends) ≈ 36 min, the hero ≈ 6 min; the asset, glyph,
sprite and floor builds are small next to these (the icons were not re-rendered in v2, so they are not timed). On a Mac the scripts switch Cycles to Metal automatically, which is much
faster. While iterating, `--quick` (800×500, 12 samples) renders a layout in about half a minute.

`build_all.py` accepts `--skip-assets --skip-graph --skip-textures --skip-renders --skip-graph-renders --skip-icons
--legacy-icon --fallback-sky`.

## Files

| Script | Output |
|---|---|
| `constellate_lib.py` | shared helpers: palette, materials, bmesh builders (ribbon rings, tick rings, struts, prisms from outlines, frames, stars, gears), USDZ export + verification + ARKit check, PNG writer, Cycles/Metal setup, glare, camera framing, and `Field` — a tiny expression builder over shader math nodes used for every procedural texture |
| `build_assets.py` | `Constellate/Resources/Assets3D/{HostOrb,ClusterOrb,Avatar_Bust,Beacon,ReviewPin,Stage_Ring,Pointer_Dart}.usdz` (v2 "observatory instruments") |
| `build_graph_assets.py` | `Assets3D/NodeStars.usdz` (15 glyph prims) + `Resources/Textures/FX_{Glow,Spark,Ring,Beam,EdgeRamp,CardGlow}.png` |
| `build_textures.py` | `Resources/Textures/{Sky_Dark,Sky_Tint,Floor_Grid}.png` |
| `render_assets.py` | `Blender/renders/*.png` asset + theme renders (1280x960); its single-icon path is legacy (`--legacy-icon`) |
| `render_graph.py` | `Blender/renders/{layout_<style>,layout_celestial_eye,layout_gallery,node_stars,relation_legend}.png` from `Blender/data/*.json`, and the README hero `Docs/images/hero.png` (`--hero`; title block rendered as Blender text) |
| `render_icons.py` | platform icons from one scene / one ortho camera (iOS light/dark/tinted, macOS tile, visionOS layers) + `icon_sheet.png` |
| `make_icon_set.sh` | `mac_16 … mac_512.png` (sips from `mac_1024.png`) + `Docs/images/icon-256.png` |

`Blender/data/orbitnotes_<style>.json` are `ConstellationSnapshot`s written by ConstellateKit's tests
(`cd ConstellateKit && CONSTELLATE_SNAPSHOT_DIR=../Blender/data swift test --filter SnapshotTests`): node
positions, card widths, glyphs, colours, every relation arc polyline exactly as `EdgeSceneBuilder` draws it, and
the relation / role legends. `render_graph.py` therefore renders the layouts the app really computes.

## Conventions baked into the exporter

- Authored in Blender Z-up metres; exported with `convert_orientation` (up **Y**, forward **-Z**), which the
  exporter realises as a root `Xform` with `rotateXYZ(-90,0,0)`; stage metadata `upAxis = Y`, `metersPerUnit = 1`.
  Blender **+Y** becomes USD **-Z** (RealityKit entity forward): the avatar's face and the dart's tip point that way.
- `triangulate_meshes=True`, `export_materials=True`, `generate_preview_surface=True` -> `UsdPreviewSurface`.
  Emission strength is baked into `emissiveColor` (e.g. Core = #E9E4FF x 4).
- Blender 5.2's exporter ignores the Principled **Alpha** socket (it only maps transmission -> opacity), so
  `export_usdz()` re-opens the package with `pxr`, writes `inputs:opacity` for translucent materials and
  re-packages with `UsdUtils.CreateNewUsdzPackage`. Transmission is render-only (`GLASS_TRANSMISSION`).
- Fixed material names (app swaps by name): `Core`, `Band0`…`Band3`, `Shell`, `Accent`, `Glass`, `Base`. `Accent`
  keeps one of the exported accent colours (#6FB6FF / #FFD166 / #FF8FD1 / #5EE1FF) because
  `AssetLoader.retintAccent` matches by name *or* by that colour.
- Every USDZ is verified: zip integrity, `upAxis`, materials, world bbox, per-asset triangle budget, size (< 2 MB),
  and the ARKit compliance checker (`usdchecker --arkit` rules; `check_arkit()` runs it when the USD build ships
  `UsdUtils.ComplianceChecker`). All eight files pass.

## Meeting assets v2 — "observatory instruments"

Every asset reads as a precise astronomical instrument: chamfered ribbon rings instead of plain tori, engraved
tick marks, faceted gems, a small constellation inside each orb — dark desaturated bodies (environment rule), light
only in the fixed emissive slots.

| Asset | Design | Triangles (budget) |
|---|---|---|
| `HostOrb` | armillary core: icosphere core (r 0.054), equator + two meridians + 23.4° ecliptic rings in Band0…3, 72-tick dial, nine-star constellation inside, glass shell r 0.135 | 9 788 (14 000) |
| `ClusterOrb` | geodesic lattice with bevelled struts and joint "stars", two tilted orbit rings, small core, glass | 3 816 (6 500) |
| `Avatar_Bust` | tapered shoulders with accent piping, helmet head with wrap-around visor, headset + mic boom, collar ring, name-plate ring | 7 042 (9 500) |
| `Beacon` | hot core beam inside a translucent sheath, three shrinking "tractor" rings, faceted top gem, engraved floor medallion | 3 500 (6 000) |
| `ReviewPin` | steel needle, accent collar, round-brilliant gem head | 488 (1 200) |
| `Stage_Ring` | astrolabe band with glowing inlay, 72 degree ticks, six hexagonal seat pads, glass centre with compass rose | 6 712 (9 000) |
| `Pointer_Dart` | hexagonal crystal bipyramid with a waist collar | 156 (300) |

## Graph assets (`build_graph_assets.py`)

**`NodeStars.usdz`** — one prim per glyph, laid out in a row (x = i · 0.16 m), largest dimension ≈ 0.1 m, flat-shaded,
≤ 220 triangles each because the app clones one per code node. Names match `CodeRole.style.glyph` /
`CodeNode.starGlyphName`; the app bakes the root rotation into one prototype per glyph and drops the row offset.

| Prim | Shape | Meaning |
|---|---|---|
| `Star_App` | 8-point compass star | entry point |
| `Star_View` | rounded window frame + title bar | UI |
| `Star_Controller` | hexagonal dial with hub and spokes | coordinates views |
| `Star_ViewModel` | elongated diamond | between view and model |
| `Star_Model` | chamfered block standing on a corner | data |
| `Star_Service` | six-tooth faceted gear | does work |
| `Star_Extension` | plus | adds to a type |
| `Star_Test` | tetrahedron | a check |
| `Star_Doc` | page with folded corner and text lines | documentation |
| `Star_Config` | hex nut | settings |
| `Star_Script` | `>_` prompt | runs |
| `Star_Other` | icosahedron | anything else |
| `Star_Folder` | four-point sparkle with an orbit | folder hub |
| `Star_Module` | six-point star in a double (armillary) orbit | project root |
| `Star_Halo` | thin ring with four ticks | file is on the selected dependency cycle (app tints #FF5F6D) |

**FX sprites** — each is an emission plane whose strength is a small field built with `constellate_lib.Field`
(Gaussian cores, exponential tails, a rounded-rectangle signed-distance field), rendered by Cycles through an
orthographic camera to linear EXR and stored as straight-alpha white (`RGB = 255, A = field`), the Floor_Grid
convention, so the app tints one texture with any colour. No view transform sits between the formula and the alpha.

| File | Size | Field | App use |
|---|---|---|---|
| `FX_Glow.png` | 256² | Gaussian core + exponential halo, windowed to 0 at the border | flow particles; host-orb aura (premultiplied for additive) |
| `FX_Spark.png` | 256² | point core + four thin diffraction spikes + four faint diagonals | particles on focused relations |
| `FX_Ring.png` | 512² | soft ring at r 0.4, fine inner line at 0.33, faint fill | beacon ripples |
| `FX_Beam.png` | 64×512 | bright core + soft sheath across, base flare, fades upward | beacon shaft (two crossed quads) |
| `FX_EdgeRamp.png` | 256×8 | 0.28 → 1 along u, short drop under the arrowhead | relation tubes: brightness rises toward the target |
| `FX_CardGlow.png` | 580×424 | card outline SDF: crisp rim just outside + soft outer glow | selection / highlight halo behind a card |

## Textures (`build_textures.py`)

- **`Sky_Dark.png`** 4096x2048: Cycles, panoramic equirectangular camera, a pure-emission world written as one
  `Field` graph: smooth B-spline gradient with a soft peak at the horizon (no flat band) and wide horizon haze in the
  grid colour; a **Milky Way** whose bulge sits in front of the viewer 18° above the horizon, crossing the sky at
  58°, with clumpy star clouds and filamentary dust rifts; two low-chroma nebula layers (indigo, plum); **four star
  magnitude classes** (unresolved grain inside the band / faint field / mid / bright with a subtle halo) with power-law
  brightness and blue-white → warm temperature tints. Denser stars inside the band, dimmer below the horizon.
  12 samples, pixel filter 1.0, **denoise off on purpose** (no Monte-Carlo noise in an emission-only world; OIDN would
  smear the stars). Measured on 16×16 block medians: OKLab L ≤ 0.29, chroma ≤ 0.06 (rule: L ≤ 0.30, chroma ≤ 0.16).
  `--fallback` keeps the older numpy look for machines without Cycles.
- **`Sky_Tint.png`**: 8-bit grayscale luminance of the render, normalised so the brightest sky region = 1.0
  (8x8 block means so stars don't skew it). The app multiplies it by the theme hue.
- **`Floor_Grid.png`** 2048x2048 (24 m) straight-alpha white — an **astrolabe**: rings at the layout's depth shells
  (1.6 m + 1.25 m · k: in the Shells layout ring k sits right under folder depth k + 1; in Celestial it is that depth's distance from the eye) with 5°/15° ticks, faint half-shell circles, 24 spokes
  (cardinals brighter), a faint 1 m grid near the centre for scale, a reticle at the origin, a bezel at 11 m, and a
  smooth radial fade. Lines are anti-aliased analytically (distance in pixels).

## Renders

`render_assets.py`: Cycles (Metal on a Mac), 64 samples, OIDN, AgX, compositor bloom, world = `Sky_Dark.png` (dark)
or `Sky_Tint.png` x `HSL(210,0.34,0.17)` (Ocean), floor = dark plane with the astrolabe emissive in `#2A3150`.

`render_graph.py` (48 samples, 1600x1000): cards are procedural miniatures of `TextureFactory.cardImage` — band
stripe and rim in the layer colour, title / subtitle bars, syntax-coloured code lines in `CodePalette.standard`
(per-card layout seeded by Object Info Random) — billboarded to the camera, each with its role star above the
top-left corner (`StarEncoder.anchor`). Relations are bevelled curves in their fixed colours, dashed exactly like
`EdgeSceneBuilder.dashes`, with arrowheads on flow kinds; tubes are thickened 2.6× for the overview (true size at
eye level). The overview camera is a perspective fit (binary search on distance + lens shift to centre the
projected extent). Korean legend labels use a CJK font when one is installed (Apple SD Gothic Neo / Noto CJK) and are
sized by measured ink height. Captions and the hero's title block are parented to the camera a few centimetres in
front of the lens (the hero through a scaled `HeroHUD` empty, so its coordinates still read "as if at 1 m"), each on a
soft dark veil: fitted cameras sit just outside the sky, and bright emissive arcs behind a half-transparent backing
would otherwise still run through the letters.

## App icons (`render_icons.py`)

One scene (1 unit = 1024 px, orthographic camera along +Y) with collections `Back` (radial backdrop, floor-hint
glow, relation lines, stars), `BackOuter` (stars outside the mac tile), `Middle` (7 code cards with cyan/amber/pink
border glints, 2 cluster orbs, 2 orbit rings), `Front` (host orb, scaled 1.5 -> 40 % of the width, core emission
tamed to 1.6 so the bands read), `MacTile` (analytic rounded-rect mesh, side 0.824, corner radius 22.4 %, solidified
+ bevelled, glossy coat for rim light). 128 samples, OIDN, AgX, bloom whose luminance is also written into alpha
(`SetAlpha` + shared Math nodes) so glow survives `film_transparent` layers. The icons were not re-rendered in the
v2 asset round (the icon keeps the v1 host orb until `render_icons.py` is run again).

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
