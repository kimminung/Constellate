"""Shared helpers for the Constellate Blender asset pipeline (Blender 5.2, headless).

Conventions
- Everything is authored in Blender's native Z-up / -Y-forward space in metres.
  `export_usdz()` converts to USD +Y up / -Z forward via `convert_orientation`.
- Colours are given as sRGB hex strings and decoded to linear for node sockets.
- Material names are FIXED so the app can swap them: Core, Band0..Band3, Shell,
  Accent, Glass, Base.  `make_material()` always creates a fresh datablock, so in
  composite render scenes Blender may suffix duplicates (`Accent.001`); only the
  per-asset export scenes need clean names and they start from an empty file.
"""
from __future__ import annotations

import math
import os
import struct
import zipfile
import zlib

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ASSETS_DIR = os.path.join(ROOT, "Constellate", "Resources", "Assets3D")
TEXTURES_DIR = os.path.join(ROOT, "Constellate", "Resources", "Textures")
RENDERS_DIR = os.path.join(ROOT, "Blender", "renders")
ICON_DIR = os.path.join(ROOT, "Constellate", "Assets.xcassets", "AppIcon.appiconset")
DOCS_IMAGES_DIR = os.path.join(ROOT, "Docs", "images")

# ----------------------------------------------------------------------------- palette
PALETTE = {
    "skyTop": "#05070F",
    "horizon": "#121733",
    "skyBottom": "#0A0B14",
    "floor": "#0B0E1A",
    "grid": "#2A3150",
    "lavender": "#9B8CFF",
    "cyan": "#58D7E8",
    "pink": "#FF8FD1",
    "amber": "#FFD166",
    "skyBlue": "#6FB6FF",
    "pointer": "#5EE1FF",
    "coreWhite": "#E9E4FF",
    "slate": "#6B7390",
    "baseDark": "#1A1F33",
}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c: float) -> float:
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def hex_to_srgb(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def hex_to_linear(h: str, alpha: float = 1.0):
    r, g, b = hex_to_srgb(h)
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


def hsl_to_hex(h: float, s: float, l: float) -> str:
    """HSL (h in degrees) -> sRGB hex, used for the tinted theme rule."""
    c = (1 - abs(2 * l - 1)) * s
    hp = (h % 360) / 60.0
    x = c * (1 - abs(hp % 2 - 1))
    r, g, b = {0: (c, x, 0), 1: (x, c, 0), 2: (0, c, x), 3: (0, x, c), 4: (x, 0, c), 5: (c, 0, x)}[int(hp) % 6]
    m = l - c / 2
    return "#%02X%02X%02X" % tuple(int(round((v + m) * 255)) for v in (r, g, b))


# ----------------------------------------------------------------------------- scene
def reset_scene():
    """Start from a completely empty file with metric units."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    sc.unit_settings.length_unit = "METERS"
    return sc


def ensure_dirs():
    for d in (ASSETS_DIR, TEXTURES_DIR, RENDERS_DIR, ICON_DIR, DOCS_IMAGES_DIR):
        os.makedirs(d, exist_ok=True)


def link(obj, collection=None):
    coll = collection or bpy.context.scene.collection
    if obj.name not in coll.objects:
        coll.objects.link(obj)
    return obj


# ----------------------------------------------------------------------------- materials
# Transmission is render-only: Blender's USD exporter turns Transmission Weight 1 into
# UsdPreviewSurface opacity 0 (overriding Alpha), so export scenes keep it off and rely on Alpha.
GLASS_TRANSMISSION = False


def make_material(name: str, base: str = "#808080", roughness: float = 0.5, emission: str | None = None,
                  strength: float = 0.0, alpha: float = 1.0, transmission: float = 0.0, ior: float = 1.45,
                  metallic: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hex_to_linear(base)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Alpha"].default_value = alpha
    bsdf.inputs["Transmission Weight"].default_value = transmission if GLASS_TRANSMISSION else 0.0
    bsdf.inputs["IOR"].default_value = ior
    if transmission > 0:
        bsdf.inputs["Specular IOR Level"].default_value = 0.8
    if emission is not None and strength > 0:
        bsdf.inputs["Emission Color"].default_value = hex_to_linear(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    else:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    if alpha < 1.0 or transmission > 0.0:
        mat.surface_render_method = "BLENDED"
        mat.use_transparency_overlap = True
    # the app tints via material slot; store intended accent as custom prop for reference
    if emission is not None:
        mat["constellate_emission_hex"] = emission
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


# ----------------------------------------------------------------------------- primitives
def _active():
    return bpy.context.active_object


def shade_smooth(obj):
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        bpy.ops.object.shade_smooth()
    return obj


def add_sphere(name, radius, location=(0, 0, 0), segments=48, rings=24, scale=(1, 1, 1), smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings, location=location, scale=scale)
    o = _active()
    o.name = name
    o.data.name = name
    return shade_smooth(o) if smooth else o


def add_icosphere(name, radius, subdivisions=2, location=(0, 0, 0)):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, subdivisions=subdivisions, location=location)
    o = _active()
    o.name = name
    o.data.name = name
    return o


def add_torus(name, major, minor, location=(0, 0, 0), rotation=(0, 0, 0), major_segments=64, minor_segments=12):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=major_segments,
                                     minor_segments=minor_segments, location=location, rotation=rotation)
    o = _active()
    o.name = name
    o.data.name = name
    return shade_smooth(o)


def add_cylinder(name, radius, depth, location=(0, 0, 0), rotation=(0, 0, 0), vertices=48, radius_top=None, smooth=True):
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices, location=location, rotation=rotation)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=radius_top, depth=depth, vertices=vertices,
                                        location=location, rotation=rotation)
    o = _active()
    o.name = name
    o.data.name = name
    return shade_smooth(o) if smooth else o


def add_cone(name, radius, depth, location=(0, 0, 0), rotation=(0, 0, 0), vertices=32):
    bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0.0, depth=depth, vertices=vertices, location=location, rotation=rotation)
    o = _active()
    o.name = name
    o.data.name = name
    return shade_smooth(o)


def add_disc(name, radius, location=(0, 0, 0), vertices=64):
    bpy.ops.mesh.primitive_circle_add(radius=radius, vertices=vertices, fill_type="TRIFAN", location=location)
    o = _active()
    o.name = name
    o.data.name = name
    return o


def add_cube(name, size=(1, 1, 1), location=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, scale=size)
    o = _active()
    o.name = name
    o.data.name = name
    return o


def add_mesh(name, verts, faces, location=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    o.location = location
    link(o)
    return o


def add_text(name, body, size=0.1, location=(0, 0, 0), rotation=(0, 0, 0), extrude=0.0):
    bpy.ops.object.text_add(location=location, rotation=rotation)
    o = _active()
    o.name = name
    o.data.body = body
    o.data.size = size
    o.data.align_x = "CENTER"
    o.data.align_y = "CENTER"
    o.data.extrude = extrude
    return o


def add_empty(name, location=(0, 0, 0), scale=1.0):
    e = bpy.data.objects.new(name, None)
    e.location = location
    e.scale = (scale, scale, scale)
    link(e)
    return e


# ----------------------------------------------------------------------------- modifiers
def apply_modifier(obj, mod):
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def subdivide(obj, levels=2, apply=True):
    m = obj.modifiers.new("Subdiv", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return apply_modifier(obj, m) if apply else obj


def bevel(obj, width=0.03, segments=5, apply=True):
    m = obj.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "NONE"
    return apply_modifier(obj, m) if apply else obj


def wireframe(obj, thickness=0.003, apply=True):
    m = obj.modifiers.new("Wire", "WIREFRAME")
    m.thickness = thickness
    m.use_even_offset = True
    m.use_replace = True
    m.use_boundary = True
    return apply_modifier(obj, m) if apply else obj


def apply_transforms(objs):
    with bpy.context.temp_override(selected_editable_objects=list(objs), active_object=objs[0], selected_objects=list(objs)):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def join(objs, name):
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=list(objs), selected_objects=list(objs)):
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


# ----------------------------------------------------------------------------- bmesh builders (refined assets)
# All builders return a new mesh object at the origin (Blender Z-up, metres). Flat-shaded unless `smooth=True`.
import bmesh  # noqa: E402


def _bm_object(name, bm, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = smooth
    o = bpy.data.objects.new(name, me)
    link(o)
    return o


def ring_band(name, radius, width, thickness, segments=128, smooth=True, chamfer=True):
    """Flat ribbon ring in the XY plane: rectangular profile `width` (radial) x `thickness` (Z), chamfered edges
    (8-point profile) or a plain box profile (`chamfer=False`, half the triangles) for small / distant rings."""
    bm = bmesh.new()
    w, t, c = width / 2, thickness / 2, min(width, thickness) * 0.18
    # profile (radial offset, z) – an octagon-ish chamfered rectangle
    if chamfer:
        prof = [(w, t - c), (w - c, t), (-w + c, t), (-w, t - c), (-w, -t + c), (-w + c, -t), (w - c, -t), (w, -t + c)]
    else:
        prof = [(w, t), (-w, t), (-w, -t), (w, -t)]
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new(((radius + dr) * ca, (radius + dr) * sa, dz)) for dr, dz in prof])
    n = len(prof)
    for i in range(segments):
        r0, r1 = rings[i], rings[(i + 1) % segments]
        for k in range(n):
            bm.faces.new((r0[k], r0[(k + 1) % n], r1[(k + 1) % n], r1[k]))
    return _bm_object(name, bm, smooth=smooth)


def box_verts(bm, center, x_axis, y_axis, z_axis, sx, sy, sz):
    """Adds a box (8 verts, 6 faces) with half-sizes along the given orthonormal axes."""
    cx, cy, cz = center
    vs = []
    for dz in (-1, 1):
        for dy in (-1, 1):
            for dx in (-1, 1):
                p = Vector((cx, cy, cz)) + x_axis * (dx * sx) + y_axis * (dy * sy) + z_axis * (dz * sz)
                vs.append(bm.verts.new(p))
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for q in f:
        bm.faces.new([vs[i] for i in q])


def tick_ring(name, radius, count, length, width, height, major_every=0, major_scale=1.8, z=0.0, inward=True):
    """`count` radial tick marks on a circle (XY plane); every `major_every`-th tick is longer."""
    bm = bmesh.new()
    for i in range(count):
        a = 2 * math.pi * i / count
        radial = Vector((math.cos(a), math.sin(a), 0))
        tangent = Vector((-math.sin(a), math.cos(a), 0))
        L = length * (major_scale if major_every and i % major_every == 0 else 1.0)
        center = radial * (radius - L / 2 if inward else radius + L / 2) + Vector((0, 0, z))
        box_verts(bm, center, radial, tangent, Vector((0, 0, 1)), L / 2, width / 2, height / 2)
    return _bm_object(name, bm)


def strut(bm, a, b, radius, sides=6):
    """Open cylinder between points a and b (added to an existing bmesh)."""
    a, b = Vector(a), Vector(b)
    d = (b - a)
    if d.length < 1e-6:
        return
    d.normalize()
    helper = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(helper).normalized()
    v = d.cross(u).normalized()
    ra, rb = [], []
    for k in range(sides):
        ang = 2 * math.pi * k / sides
        off = (u * math.cos(ang) + v * math.sin(ang)) * radius
        ra.append(bm.verts.new(a + off))
        rb.append(bm.verts.new(b + off))
    for k in range(sides):
        bm.faces.new((ra[k], ra[(k + 1) % sides], rb[(k + 1) % sides], rb[k]))


def bm_icosphere(bm, center, radius, subdivisions=1):
    """Adds a small icosphere to `bm` (used for lattice joints and constellation dots)."""
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=subdivisions, radius=radius)
    bmesh.ops.translate(tmp, verts=tmp.verts, vec=Vector(center))
    me = bpy.data.meshes.new("_tmp_ico")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def prism_from_outline(name, outline, depth, bevel=0.0, both_sides=True, smooth=False, holes=()):
    """Extrudes a closed 2-D outline (list of (x, y)) along Z by `depth` (centred). Optional pointed faces:
    `bevel` > 0 raises the centre of the top/bottom caps into a shallow pyramid for a faceted gem look."""
    bm = bmesh.new()
    h = depth / 2
    top = [bm.verts.new((x, y, h)) for x, y in outline]
    bot = [bm.verts.new((x, y, -h)) for x, y in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    if bevel > 0:
        ct = bm.verts.new((0, 0, h + bevel))
        cb = bm.verts.new((0, 0, -h - bevel))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((top[i], top[j], ct))
            bm.faces.new((bot[j], bot[i], cb))
    else:
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _bm_object(name, bm, smooth=smooth)


def frame_from_outlines(name, outer, inner, depth, smooth=False):
    """Extruded ring between two closed outlines with the same vertex count (frames, nuts, washers)."""
    bm = bmesh.new()
    h = depth / 2
    ot = [bm.verts.new((x, y, h)) for x, y in outer]
    ob = [bm.verts.new((x, y, -h)) for x, y in outer]
    it = [bm.verts.new((x, y, h)) for x, y in inner]
    ib = [bm.verts.new((x, y, -h)) for x, y in inner]
    n = len(outer)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))      # outer wall
        bm.faces.new((ib[j], ib[i], it[i], it[j]))      # inner wall
        bm.faces.new((ot[i], ot[j], it[j], it[i]))      # top
        bm.faces.new((ob[j], ob[i], ib[i], ib[j]))      # bottom
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _bm_object(name, bm, smooth=smooth)


def rounded_rect_outline(w, h, r, seg=6):
    """Closed outline of a rounded rectangle centred at the origin (counter-clockwise)."""
    pts = []
    r = min(r, w / 2, h / 2)
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def star_outline(points, r_outer, r_inner, rotation=90.0):
    out = []
    for i in range(points * 2):
        r = r_outer if i % 2 == 0 else r_inner
        a = math.radians(rotation + 180.0 * i / points)
        out.append((r * math.cos(a), r * math.sin(a)))
    return out


def circle_outline(r, n, rotation=0.0):
    return [(r * math.cos(math.radians(rotation + 360.0 * i / n)), r * math.sin(math.radians(rotation + 360.0 * i / n))) for i in range(n)]


def gear_outline(teeth, r_outer, r_inner, tooth_frac=0.45):
    """Gear silhouette: `teeth` trapezoid teeth between r_inner and r_outer."""
    pts = []
    for i in range(teeth):
        a0 = 2 * math.pi * i / teeth
        step = 2 * math.pi / teeth
        half = step * tooth_frac / 2
        for a, r in ((a0 - step / 2 + 0.02, r_inner), (a0 - half, r_inner), (a0 - half * 0.7, r_outer), (a0 + half * 0.7, r_outer), (a0 + half, r_inner)):
            pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def merge(objs, name):
    """Joins objects into the first one (materials preserved per face)."""
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        objs[0].data.name = name
        return objs[0]
    return join(objs, name)


# ----------------------------------------------------------------------------- stats / export
def tri_count(objs) -> int:
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for o in objs:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        n += len(me.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
    return n


def bounds(objs):
    """World-space (min, max) over mesh objects."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if o.type not in {"MESH", "FONT"}:
            continue
        eo = o.evaluated_get(dg)
        for c in eo.bound_box:
            w = eo.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def export_usdz(objs, filepath: str, root_name: str):
    """Export `objs` to a .usdz, +Y up / -Z forward, triangulated, metres."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    if os.path.exists(filepath):
        os.remove(filepath)
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.wm.usd_export(
        filepath=filepath,
        selected_objects_only=True,
        export_materials=True,
        generate_preview_surface=True,
        generate_materialx_network=False,
        export_textures_mode="NEW",
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        triangulate_meshes=True,
        quad_method="SHORTEST_DIAGONAL",
        ngon_method="BEAUTY",
        export_uvmaps=True,
        export_normals=True,
        export_mesh_colors=False,
        export_lights=False,
        export_cameras=False,
        export_animation=False,
        export_hair=False,
        export_subdivision="TESSELLATE",
        root_prim_path="/" + root_name,
        convert_scene_units="METERS",
        export_custom_properties=True,
        author_blender_name=False,
        convert_world_material=False,
    )
    assert os.path.exists(filepath) and os.path.getsize(filepath) > 0, f"export failed: {filepath}"
    # Blender 5.2's exporter ignores the Principled "Alpha" socket (opacity = 1 - transmission only),
    # so patch UsdPreviewSurface opacity for translucent materials after the fact.
    alphas = {}
    for o in objs:
        if o.type != "MESH":
            continue
        for m in o.data.materials:
            if m is None or not m.use_nodes:
                continue
            b = m.node_tree.nodes.get("Principled BSDF")
            if b is not None and b.inputs["Alpha"].default_value < 0.999:
                alphas[m.name] = float(b.inputs["Alpha"].default_value)
    if alphas:
        patch_usdz_opacity(filepath, alphas)
    return filepath


def patch_usdz_opacity(filepath: str, alphas: dict):
    """Unpack the single-layer usdz, set inputs:opacity per material name, repackage in place."""
    import shutil
    import tempfile
    from pxr import Sdf, Usd, UsdShade, UsdUtils

    tmp = tempfile.mkdtemp(prefix="cst_usdz_")
    try:
        with zipfile.ZipFile(filepath) as z:
            z.extractall(tmp)
            layer = [n for n in z.namelist() if n.endswith((".usdc", ".usda", ".usd"))][0]
        layer_path = os.path.join(tmp, layer)
        stage = Usd.Stage.Open(layer_path)
        patched = []
        for prim in stage.Traverse():
            if prim.IsA(UsdShade.Material) and prim.GetName() in alphas:
                for child in prim.GetChildren():
                    if child.IsA(UsdShade.Shader):
                        attr = child.GetAttribute("inputs:opacity")
                        if not attr:
                            attr = child.CreateAttribute("inputs:opacity", Sdf.ValueTypeNames.Float)
                        attr.Set(alphas[prim.GetName()])
                        patched.append(prim.GetName())
        stage.GetRootLayer().Save()
        del stage
        out_tmp = os.path.join(tmp, "repacked.usdz")
        ok = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(layer_path), out_tmp)
        assert ok, "usdz repackaging failed"
        shutil.copyfile(out_tmp, filepath)
        print(f"[constellate] patched opacity in {os.path.basename(filepath)}: " + ", ".join(f"{k}={alphas[k]}" for k in patched))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def verify_usdz(filepath: str) -> dict:
    """Zip-validate and introspect the exported stage via Blender's bundled pxr."""
    info = {"path": filepath, "bytes": os.path.getsize(filepath)}
    with zipfile.ZipFile(filepath) as z:
        info["zip_entries"] = z.namelist()
        bad = z.testzip()
        assert bad is None, f"corrupt zip member {bad}"
    try:
        from pxr import Usd, UsdGeom, UsdShade
        stage = Usd.Stage.Open(filepath)
        info["upAxis"] = UsdGeom.GetStageUpAxis(stage)
        info["metersPerUnit"] = UsdGeom.GetStageMetersPerUnit(stage)
        meshes, mats = [], []
        for prim in stage.Traverse():
            if prim.IsA(UsdGeom.Mesh):
                meshes.append(prim.GetPath().pathString)
            elif prim.IsA(UsdShade.Material):
                mats.append(prim.GetName())
        info["meshes"] = meshes
        info["materials"] = mats
        bbox = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ["default", "render"]).ComputeWorldBound(stage.GetPseudoRoot())
        r = bbox.ComputeAlignedRange()
        info["bbox_min"] = tuple(round(v, 4) for v in r.GetMin())
        info["bbox_max"] = tuple(round(v, 4) for v in r.GetMax())
    except Exception as e:  # pragma: no cover - diagnostics only
        info["pxr_error"] = repr(e)
    return info


def check_arkit(filepath: str):
    """`usdchecker --arkit` equivalent via pxr's ComplianceChecker when this USD build ships it.
    Returns (passed, messages) or (None, reason) when the checker is unavailable."""
    try:
        from pxr import UsdUtils
        checker_cls = getattr(UsdUtils, "ComplianceChecker", None)
        if checker_cls is None:
            return None, "ComplianceChecker not available in this USD build"
        c = checker_cls(arkit=True, skipARKitRootLayerCheck=False, rootPackageOnly=False, skipVariants=False, verbose=False)
        # Sdr shader definitions are missing from some pip builds; that generic rule is not ARKit-specific.
        try:
            c.CheckCompliance(filepath)
        except Exception:
            c = checker_cls(arkit=True, skipARKitRootLayerCheck=False, rootPackageOnly=False, skipVariants=False, verbose=False)
            c._rules = [r for r in c._rules if type(r).__name__ != "ShaderPropertyTypeConformanceChecker"]
            c.CheckCompliance(filepath)
        problems = list(c.GetErrors()) + list(c.GetFailedChecks())
        return (len(problems) == 0), problems
    except Exception as e:  # pragma: no cover
        return None, repr(e)


# ----------------------------------------------------------------------------- PNG writer
def write_png(path: str, rgba_u8, width: int, height: int, channels: int = 4):
    """Write a straight-alpha (non-premultiplied) 8-bit PNG from a flat bytes buffer (row 0 = top)."""
    color_type = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    raw = bytearray()
    stride = width * channels
    mv = memoryview(rgba_u8)
    for y in range(height):
        raw += b"\x00"
        raw += mv[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    return path


# ----------------------------------------------------------------------------- render setup
def setup_cycles(scene, samples=64, denoise=True, use_gpu=True, filter_size=1.5, view_transform="Standard"):
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = denoise
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.max_bounces = 8
    scene.cycles.transparent_max_bounces = 16
    scene.cycles.transmission_bounces = 8
    scene.render.filter_size = filter_size
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = view_transform
    except TypeError:
        scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 60
    scene.cycles.device = "CPU"
    if use_gpu:
        try:
            prefs = bpy.context.preferences.addons["cycles"].preferences
            prefs.compute_device_type = "METAL"
            prefs.get_devices()
            any_gpu = False
            for d in prefs.devices:
                d.use = d.type == "METAL"
                any_gpu |= d.use
            if any_gpu:
                scene.cycles.device = "GPU"
        except Exception as e:  # pragma: no cover
            print("[constellate] Metal unavailable, using CPU:", e)
    return scene


def add_glare(scene, threshold=1.0, strength=0.6, size=7):
    """Compositor bloom. Blender 5 uses a node-group based compositor; fall back silently if API differs."""
    try:
        ng = bpy.data.node_groups.new("ConstellateComp", "CompositorNodeTree")
        if hasattr(ng, "interface"):
            ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = ng.nodes.new("CompositorNodeRLayers")
        rl.scene = scene
        glare = ng.nodes.new("CompositorNodeGlare")
        # Blender 5.x: type/quality are menu *sockets*
        if "Type" in glare.inputs:
            glare.inputs["Type"].default_value = "Bloom"
            glare.inputs["Quality"].default_value = "High"
        elif hasattr(glare, "glare_type"):
            glare.glare_type = "BLOOM"
        for key, val in (("Threshold", threshold), ("Strength", strength), ("Size", size), ("Smoothness", 0.2), ("Saturation", 0.9)):
            if key in glare.inputs:
                try:
                    glare.inputs[key].default_value = val
                except Exception:
                    pass
        out = ng.nodes.new("NodeGroupOutput")
        ng.links.new(rl.outputs["Image"], glare.inputs["Image"])
        ng.links.new(glare.outputs["Image"], out.inputs[0])
        scene.compositing_node_group = ng
        scene.render.use_compositing = True
        return True
    except Exception as e:
        print("[constellate] glare compositor unavailable:", e)
        scene.render.use_compositing = False
        return False


def add_camera(name="Camera", location=(0, -3, 1), target=(0, 0, 0), lens=50.0, ortho_scale=None):
    cam_data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cam_data)
    link(cam)
    cam.location = location
    if ortho_scale is not None:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho_scale
    cam_data.lens = lens
    cam_data.clip_start = 0.005
    cam_data.clip_end = 500
    look_at(cam, target)
    bpy.context.scene.camera = cam
    return cam


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def frame_objects(cam, objs, azimuth_deg=35.0, elevation_deg=18.0, margin=1.25, lens=50.0):
    """Place `cam` so the bounding sphere of `objs` fits the frame."""
    lo, hi = bounds(objs)
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 1e-3)
    sc = bpy.context.scene
    cam.data.lens = lens
    aspect = sc.render.resolution_x / sc.render.resolution_y
    hfov = cam.data.angle if aspect >= 1 else 2 * math.atan(math.tan(cam.data.angle / 2) * aspect)
    vfov = 2 * math.atan(math.tan(hfov / 2) / aspect) if aspect >= 1 else cam.data.angle
    fov = min(hfov, vfov)
    dist = radius * margin / math.sin(fov / 2)
    az = math.radians(azimuth_deg)
    el = math.radians(elevation_deg)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = center + d * dist
    look_at(cam, center)
    return center, radius


def add_area_light(name, location, color_hex="#FFFFFF", energy=300.0, size=2.0, target=(0, 0, 0)):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy = energy
    ld.size = size
    ld.color = hex_to_linear(color_hex)[:3]
    lo = bpy.data.objects.new(name, ld)
    link(lo)
    lo.location = location
    look_at(lo, target)
    return lo


def set_world_image(scene, image_path: str, strength=1.0, tint_hex: str | None = None):
    """World = equirect image (optionally multiplied by a tint colour). Returns the world."""
    world = bpy.data.worlds.new("ConstellateWorld")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    tex = nt.nodes.new("ShaderNodeTexEnvironment")
    tex.image = bpy.data.images.load(image_path, check_existing=True)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Generated"], tex.inputs["Vector"])
    if tint_hex:
        # Sky_Tint stores sRGB-encoded luminance; keep the default sRGB decode, then multiply by the hue colour
        tex.image.colorspace_settings.name = "sRGB"
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        mul.inputs[7].default_value = hex_to_linear(tint_hex)
        nt.links.new(tex.outputs["Color"], mul.inputs[6])
        nt.links.new(mul.outputs[2], bg.inputs["Color"])
    else:
        nt.links.new(tex.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    scene.world = world
    return world


def render_to(scene, filepath: str, width: int, height: int):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.filepath = filepath
    bpy.ops.render.render(write_still=True)
    assert os.path.exists(filepath) and os.path.getsize(filepath) > 0, f"render failed: {filepath}"
    return os.path.getsize(filepath)


# ----------------------------------------------------------------------------- shader fields
class Field:
    """Tiny expression builder over Cycles shader nodes (material *or* world node trees).

    Scalars are output sockets or Python floats; vectors/colours are sockets or 3-tuples. It keeps procedural
    textures readable as formulas — `F.gauss(F.sub(r, 0.4), 0.028)` instead of a dozen hand-wired Math nodes —
    while everything still renders in Cycles (CPU here, Metal on a Mac) exactly as a hand-built node tree would.
    """

    def __init__(self, nt):
        self.nt = nt

    # -- plumbing
    def _set(self, sock, v):
        if isinstance(v, (int, float)):
            sock.default_value = float(v)
        elif isinstance(v, tuple):
            sock.default_value = v if len(sock.default_value) == len(v) else (*v, 1.0)[:len(sock.default_value)]
        else:
            self.nt.links.new(v, sock)

    def _op(self, op, a, b=None):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        self._set(n.inputs[0], a)
        if b is not None:
            self._set(n.inputs[1], b)
        return n.outputs[0]

    # -- scalar maths
    def add(self, a, b): return self._op("ADD", a, b)
    def sub(self, a, b): return self._op("SUBTRACT", a, b)
    def mul(self, a, b): return self._op("MULTIPLY", a, b)
    def div(self, a, b): return self._op("DIVIDE", a, b)
    def min(self, a, b): return self._op("MINIMUM", a, b)
    def max(self, a, b): return self._op("MAXIMUM", a, b)
    def gt(self, a, b): return self._op("GREATER_THAN", a, b)
    def lt(self, a, b): return self._op("LESS_THAN", a, b)
    def floor(self, a): return self._op("FLOOR", a)
    def fract(self, a): return self._op("FRACT", a)
    def abs(self, a): return self._op("ABSOLUTE", a)
    def sqrt(self, a): return self._op("SQRT", a)
    def exp(self, a): return self._op("EXPONENT", a)
    def pow(self, a, b): return self._op("POWER", a, b)
    def sq(self, a): return self.mul(a, a)
    def clamp01(self, a): return self.min(self.max(a, 0.0), 1.0)

    def gauss(self, x, sigma):
        """exp(−(x/σ)²)"""
        return self.exp(self.mul(self.sq(self.div(x, sigma)), -1.0))

    def tail(self, x, scale):
        """exp(−|x|/s)"""
        return self.exp(self.mul(self.div(self.abs(x), scale), -1.0))

    def length(self, x, y):
        return self.sqrt(self.add(self.sq(x), self.sq(y)))

    def smoothstep(self, x, e0, e1):
        """0 below e0, 1 above e1, Hermite in between."""
        t = self.clamp01(self.div(self.sub(x, e0), e1 - e0))
        return self.mul(self.sq(t), self.sub(3.0, self.mul(t, 2.0)))

    def smooth_edge(self, d, inner, outer):
        """1 below `inner`, 0 beyond `outer` (a soft window)."""
        return self.sub(1.0, self.smoothstep(d, inner, outer))

    def lerp(self, a, b, t):
        return self.add(a, self.mul(self.sub(b, a), t))

    def rounded_rect_sdf(self, x, y, hw, hh, r):
        """Signed distance to a rounded rectangle (half extents hw × hh, corner radius r)."""
        qx = self.add(self.sub(self.abs(x), hw), r)
        qy = self.add(self.sub(self.abs(y), hh), r)
        outside = self.length(self.max(qx, 0.0), self.max(qy, 0.0))
        inside = self.min(self.max(qx, qy), 0.0)
        return self.sub(self.add(outside, inside), r)

    # -- vectors / colours
    def _vop(self, op, a, b=None):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = op
        self._set(n.inputs[0], a)
        if b is not None:
            self._set(n.inputs[1], b)
        return n

    def vadd(self, a, b): return self._vop("ADD", a, b).outputs["Vector"]
    def vmul(self, a, b): return self._vop("MULTIPLY", a, b).outputs["Vector"]
    def normalize(self, v): return self._vop("NORMALIZE", v).outputs["Vector"]
    def dot(self, a, b): return self._vop("DOT_PRODUCT", a, b).outputs["Value"]

    def vscale(self, v, s):
        n = self._vop("SCALE", v)
        self._set(n.inputs["Scale"], s)
        return n.outputs["Vector"]

    @staticmethod
    def rgb(hex_str):
        """sRGB hex → linear (r, g, b) tuple for colour constants."""
        return hex_to_linear(hex_str)[:3]

    def ramp(self, fac, stops, interpolation="LINEAR"):
        """ColorRamp from [(position, hex), …] → colour socket."""
        n = self.nt.nodes.new("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.interpolation = interpolation
        stops = sorted(stops)
        cr.elements[0].position, cr.elements[0].color = stops[0][0], hex_to_linear(stops[0][1])
        cr.elements[1].position, cr.elements[1].color = stops[-1][0], hex_to_linear(stops[-1][1])
        for pos, hx in stops[1:-1]:
            e = cr.elements.new(pos)
            e.color = hex_to_linear(hx)
        self._set(n.inputs["Fac"], fac)
        return n.outputs["Color"]

    def combine(self, x, y, z=0.0):
        n = self.nt.nodes.new("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            self._set(n.inputs[i], v)
        return n.outputs["Vector"]

    def between(self, x, lo, hi):
        """1 where lo < x < hi (hard edges; the renderer's pixel filter anti-aliases)."""
        return self.mul(self.gt(x, lo), self.lt(x, hi))

    def separate(self, v):
        n = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self._set(n.inputs[0], v)
        return n.outputs["X"], n.outputs["Y"], n.outputs["Z"]

    # -- textures
    def noise(self, vec, scale, detail=6.0, roughness=0.55, lacunarity=2.0, distortion=0.0, kind="FBM"):
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        try:
            n.noise_type = kind
        except Exception:
            pass
        self._set(n.inputs["Vector"], vec)
        for key, val in (("Scale", scale), ("Detail", detail), ("Roughness", roughness), ("Lacunarity", lacunarity), ("Distortion", distortion)):
            if key in n.inputs:
                n.inputs[key].default_value = val
        return n.outputs["Fac"]

    def white_noise(self, vec):
        """Deterministic hash of a 3-D vector → 0…1 (per-line / per-token randomness)."""
        n = self.nt.nodes.new("ShaderNodeTexWhiteNoise")
        n.noise_dimensions = "3D"
        self._set(n.inputs["Vector"], vec)
        return n.outputs["Value"]

    def voronoi(self, vec, scale, randomness=1.0):
        """F1 Euclidean cells; returns (distance in cell units, per-cell random colour)."""
        n = self.nt.nodes.new("ShaderNodeTexVoronoi")
        n.feature = "F1"
        n.distance = "EUCLIDEAN"
        self._set(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = randomness
        return n.outputs["Distance"], n.outputs["Color"]
