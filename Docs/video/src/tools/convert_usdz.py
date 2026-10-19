"""Convert the app's Blender-made USDZ assets to GLB for the three.js video renderer.

Every mesh prim becomes one glTF mesh named after the prim, with its bound USD material name kept as the glTF
material name (Core / Band0..3 / Shell / Glass / Accent / Base), so the renderer can re-shade slots the same way
the app does at runtime. World transforms are baked. For NodeStars the per-glyph row offset is removed (each glyph
is centred on its own prim origin, like NodeStarFactory.extractPrototypes).

Also writes assets/glb/materials.json with each material's UsdPreviewSurface inputs (diffuse, emissive, opacity...).
"""
import json
import os
import sys

import numpy as np
import trimesh
from pxr import Gf, Usd, UsdGeom, UsdShade

SRC = sys.argv[1] if len(sys.argv) > 1 else "assets/usdz"
DST = sys.argv[2] if len(sys.argv) > 2 else "assets/glb"
os.makedirs(DST, exist_ok=True)


def surface_inputs(material):
    out = {}
    if not material:
        return out
    for shader_prim in Usd.PrimRange(material.GetPrim()):
        shader = UsdShade.Shader(shader_prim)
        if not shader:
            continue
        sid = shader.GetIdAttr().Get() if shader.GetIdAttr() else None
        if sid != "UsdPreviewSurface":
            continue
        for inp in shader.GetInputs():
            val = inp.Get()
            if val is None and inp.HasConnectedSource():
                val = "<connected>"
            if isinstance(val, (Gf.Vec3f, Gf.Vec3d)):
                val = [float(v) for v in val]
            elif isinstance(val, (float, int, bool, str)):
                pass
            else:
                val = str(val)
            out[inp.GetBaseName()] = val
    return out


all_materials = {}
for name in sorted(os.listdir(SRC)):
    if not name.endswith(".usdz"):
        continue
    stage = Usd.Stage.Open(os.path.join(SRC, name))
    asset = name[:-5]
    scene = trimesh.Scene()
    cache = UsdGeom.XformCache(Usd.TimeCode.Default())
    mats = {}
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(prim)
        pts = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
        counts = np.array(mesh.GetFaceVertexCountsAttr().Get(), dtype=np.int64)
        idx = np.array(mesh.GetFaceVertexIndicesAttr().Get(), dtype=np.int64)
        orient = mesh.GetOrientationAttr().Get()
        faces = []
        o = 0
        for c in counts:
            poly = idx[o:o + c]
            for k in range(1, c - 1):
                tri = [poly[0], poly[k], poly[k + 1]]
                if orient == "leftHanded":
                    tri = [tri[0], tri[2], tri[1]]
                faces.append(tri)
            o += c
        m = np.array(cache.GetLocalToWorldTransform(prim), dtype=np.float64)  # row-vector convention
        homo = np.c_[pts, np.ones(len(pts))]
        world = homo @ m
        world = world[:, :3]
        if asset == "NodeStars":
            # Glyph prims sit in a row; keep rotation/scale, drop the translation (centre on the prim origin).
            world = world - m[3, :3]
        tm = trimesh.Trimesh(vertices=world, faces=np.array(faces), process=False)
        bound = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
        mat_name = bound.GetPrim().GetName() if bound else "Default"
        mats[mat_name] = surface_inputs(bound)
        tm.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(name=mat_name))
        # Glyph name = parent Xform name for NodeStars (Star_App/Star_App)
        node_name = prim.GetParent().GetName() if asset == "NodeStars" else prim.GetName()
        scene.add_geometry(tm, node_name=node_name, geom_name=node_name)
    out = os.path.join(DST, asset + ".glb")
    scene.export(out)
    all_materials[asset] = mats
    b = scene.bounds
    print(f"{asset}: {len(scene.geometry)} meshes, bounds {np.round(b, 3).tolist()} -> {out} ({os.path.getsize(out)} B)")

with open(os.path.join(DST, "materials.json"), "w") as f:
    json.dump(all_materials, f, indent=1)
print(json.dumps(all_materials, indent=1)[:4000])
