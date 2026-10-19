"""Fills web/assets and web/data from the repository, so the video sources only track code and a few small crops.

python3 tools/prep_assets.py [repo_root]        (default: four levels up, i.e. the repository that holds Docs/video/src)

- web/assets/tex  ← Constellate/Resources/Textures (FX_*.png, Floor_Grid.png; Sky_Dark / Sky_Tint downsized to 2048×1024 JPEG)
- web/assets/glb  ← Constellate/Resources/Assets3D/*.usdz via tools/convert_usdz.py (needs usd-core + trimesh)
- web/assets/img  ← Docs/images (visionOS dashboard screenshot, icon) and Blender/renders/node_stars.png
                     (hero_icon / hero_wordmark / hero_tagline are crops of Docs/images/hero.png, tracked in src)
- web/data/graph.js ← Blender/data/orbitnotes_*.json via tools/prep_data.py
"""
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

SRC = Path(__file__).resolve().parents[1]
REPO = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else SRC.parents[2]
WEB = SRC / "web"
tex, glb, img = WEB / "assets/tex", WEB / "assets/glb", WEB / "assets/img"
for d in (tex, glb, img, WEB / "data"):
    d.mkdir(parents=True, exist_ok=True)

T = REPO / "Constellate/Resources/Textures"
for name in ["FX_Beam.png", "FX_CardGlow.png", "FX_EdgeRamp.png", "FX_Glow.png", "FX_Ring.png", "FX_Spark.png", "Floor_Grid.png"]:
    shutil.copy2(T / name, tex / name)
for name in ["Sky_Dark", "Sky_Tint"]:
    Image.open(T / f"{name}.png").convert("RGB").resize((2048, 1024), Image.LANCZOS).save(tex / f"{name}_2k.jpg", quality=92)

subprocess.run([sys.executable, str(SRC / "tools/convert_usdz.py"), str(REPO / "Constellate/Resources/Assets3D"), str(glb)], check=True)

shutil.copy2(REPO / "Docs/images/screenshot-visionos-dashboard.png", img)
shutil.copy2(REPO / "Docs/images/icon-256.png", img)
shutil.copy2(REPO / "Blender/renders/node_stars.png", img)

subprocess.run([sys.executable, str(SRC / "tools/prep_data.py"), str(REPO / "Blender/data"), str(WEB / "data/graph.js")], check=True)
print("assets ready in", WEB / "assets")
