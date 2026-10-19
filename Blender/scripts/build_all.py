"""One-shot pipeline: USDZ assets -> graph assets + FX -> textures -> renders -> graph renders -> app icon.

  /Applications/Blender.app/Contents/MacOS/Blender --background --python build_all.py -- [options]

Options
  --skip-assets     don't rebuild Constellate/Resources/Assets3D/*.usdz (meeting assets)
  --skip-graph      don't rebuild NodeStars.usdz and the FX_*.png sprites (build_graph_assets.py)
  --skip-textures   don't re-render Sky_Dark / Sky_Tint / Floor_Grid (reuse existing files)
  --skip-renders    don't produce Blender/renders/*.png (asset + theme renders)
  --skip-graph-renders  don't render the layout gallery / legends from Blender/data/*.json (render_graph.py)
  --skip-icons      don't run render_icons.py (iOS light/dark/tinted, macOS tile, visionOS layers, icon sheet)
  --legacy-icon     also render the old single AppIcon via render_assets.py (superseded by render_icons.py)
  --fallback-sky    generate the sky with numpy instead of Cycles (fast, ~seconds)
"""
from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import constellate_lib as L  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
t0 = time.time()
L.ensure_dirs()

if "--skip-assets" not in argv:
    import build_assets
    build_assets.build_and_export()

if "--skip-graph" not in argv:
    import build_graph_assets
    build_graph_assets.export_node_stars()
    build_graph_assets.build_fx()

if "--skip-textures" not in argv:
    import build_textures
    build_textures.build_textures(force_fallback="--fallback-sky" in argv)

if "--skip-renders" not in argv:
    import render_assets
    render_assets.render_all(names=None, icon="--legacy-icon" in argv)

if "--skip-graph-renders" not in argv:
    import render_graph
    render_graph.main([])

if "--skip-icons" not in argv:
    import render_icons
    render_icons.render_all_icons()
    render_icons.render_sheet()

print(f"[constellate] build_all finished in {time.time() - t0:.0f}s")
print("[constellate] NOTE: macOS icon downscales (mac_16..mac_512.png) + Docs/images/icon-256.png are produced by make_icon_set.sh (sips).")
