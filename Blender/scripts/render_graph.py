"""Cycles renders of the constellation itself, from ConstellateKit snapshots.

Inputs   Blender/data/orbitnotes_<style>.json — written by ConstellateKit's SnapshotTests
         (`cd ConstellateKit && CONSTELLATE_SNAPSHOT_DIR=../Blender/data swift test --filter SnapshotTests`).
         Every position, colour, glyph, arc polyline, dash flag and legend label comes from the Swift code the
         app runs, so these images show the real layouts — not an illustration of them.

Outputs  (Blender/renders/)
  layout_<style>.png     one render per layout style: celestial, shells, sphere, treeRadial, wall, spiral
  layout_celestial_eye.png  the default layout from the viewer's spot (what the headset shows)
  layout_gallery.png     3 × 2 contact sheet of the six (README / PRD-Design §7)
  node_stars.png         glyph legend: the 12 role stars, the two hub stars and the cycle halo
  relation_legend.png    every relation kind as drawn: colour, dash, arrowhead, flow particles, label
  Docs/images/hero.png   README hero: the celestial constellation over the meeting stage + title block

Run
  Blender --background --python render_graph.py -- [celestial shells …] [--eye] [--gallery] [--stars] [--legend] [--hero] [--quick]
  (no arguments = everything; --quick = small, few samples, for iterating)

Scene language (matches the app): cards are procedural miniatures of the real code cards (band stripe in the
layer colour, title, subtitle, syntax-coloured code lines), each with its role star above the top-left corner;
relations are tubes in their fixed relation colours (dashed for type-system kinds, arrowheads on flow kinds),
tree lines are thin and quiet; the floor is the astrolabe whose rings sit under the depth shells.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

import constellate_lib as L  # noqa: E402
import build_graph_assets as G  # noqa: E402
import render_assets as RA  # noqa: E402

P = L.PALETTE
DATA_DIR = os.path.join(L.ROOT, "Blender", "data")
STYLES = ["celestial", "shells", "sphere", "treeRadial", "wall", "spiral"]
CAPTIONS = {
    "celestial": ("CELESTIAL", "distance = tree depth  ·  azimuth = subtree  ·  elevation = layer  ·  outward = recent"),
    "shells": ("SHELLS", "radius = tree depth  ·  angle = subtree  ·  height = layer"),
    "sphere": ("SPHERE", "Fibonacci dome in path order  ·  folders as outer hubs"),
    "treeRadial": ("TREE RADIAL", "rings = depth  ·  angle ∝ files in subtree  ·  height = layer"),
    "wall": ("WALL", "columns · rows = path order  ·  folders head their block"),
    "spiral": ("SPIRAL", "height and turn = path order"),
}
W, H, SAMPLES = 1600, 1000, 48
RENDER_TUBE_SCALE = 2.6      # tubes are 2–3 mm in the headset; thicken them so they read at render scale
CARD_ASPECT = G.CARD_H       # 352 / 512

# CodePalette.standard (ConstellateKit) for the miniature card text, so renders match the app's cards.
CODE = {"plain": "#F4F6FB", "comment": "#8A93A6", "keyword": "#FF7AB6", "type": "#5EE1FF", "string": "#B8FF7A",
        "number": "#B89CFF", "function": "#FFD166", "card": "#0E1220", "border": "#2A3150"}


def rk_to_bl(p):
    """RealityKit Y-up metres → Blender Z-up (RealityKit −Z = Blender +Y)."""
    return Vector((p[0], -p[2], p[1]))


def load_snapshot(style):
    with open(os.path.join(DATA_DIR, f"orbitnotes_{style}.json")) as f:
        return json.load(f)


def _font(korean=False):
    """A CJK-capable font for Korean labels: Blender's bundled Noto Sans CJK (identical on every machine), else a
    system font (macOS Apple SD Gothic Neo / Linux Noto CJK). Latin text uses Blender's default font (Inter)."""
    if not korean:
        return None
    candidates = []
    try:
        fonts_dir = bpy.utils.system_resource("DATAFILES", path="fonts")
        if fonts_dir:
            candidates.append(os.path.join(fonts_dir, "Noto Sans CJK Regular.woff2"))
    except Exception:
        pass
    candidates += ["/System/Library/Fonts/AppleSDGothicNeo.ttc", "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
                   "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc"]
    for path in candidates:
        if os.path.exists(path):
            try:
                return bpy.data.fonts.load(path, check_existing=True)
            except Exception:
                pass
    return None


def text(name, body, size, location, rotation=(math.pi / 2, 0, 0), color="#E8ECF6", strength=1.6, align="LEFT", font=None,
         glyph_height=None):
    """Emissive text. `glyph_height` (metres) rescales the object so its ink is that tall — CJK fonts carry very
    different metrics from Blender's built-in font, so Korean labels are sized by measurement, not by `size`."""
    o = L.add_text(name, body, size=size, location=location, rotation=rotation)
    o.data.align_x = align
    if font is not None:
        o.data.font = font
    L.assign(o, L.make_material(f"{name}Mat", base="#000000", roughness=1.0, emission=color, strength=strength))
    if glyph_height:
        bpy.context.view_layer.update()
        h = o.dimensions.y
        if h > 1e-6:
            k = glyph_height / h
            o.scale = (k, k, k)
    return o


# ============================================================================ materials
def card_material():
    """One material for every card: a procedural miniature of TextureFactory.cardImage.
    Per card: Object Info Color = layer colour, Alpha = 1 file/type (code lines) or 0.5 hub (title only),
    Random = text layout seed."""
    mat = bpy.data.materials.new("CardMini")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    info = nt.nodes.new("ShaderNodeObjectInfo")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    F = L.Field(nt)
    u, v, _ = F.separate(coord.outputs["Object"])
    hw, hh = 0.5, CARD_ASPECT / 2
    band = info.outputs["Color"]
    rnd = info.outputs["Random"]
    is_file = F.gt(info.outputs["Alpha"], 0.75)

    d = F.rounded_rect_sdf(u, v, hw - 0.003, hh - 0.003, G.CARD_R)
    inside = F.smoothstep(F.mul(d, -1.0), -0.002, 0.002)
    rim = F.mul(F.gauss(F.add(d, 0.006), 0.005), 0.8)
    stripe = F.lt(u, -hw + 12 / 512)
    header = F.mul(F.smoothstep(v, hh - 0.18, hh), 0.22)
    left = -0.44
    title = F.mul(F.between(v, 0.226, 0.262), F.between(u, left, F.add(left + 0.22, F.mul(rnd, 0.42))))
    sub = F.mul(F.between(v, 0.181, 0.199), F.between(u, left, F.add(left + 0.16, F.mul(F.fract(F.mul(rnd, 7.3)), 0.2))))
    divider = F.mul(F.between(v, 0.146, 0.150), F.between(u, left, 0.46))

    # code lines: index k from the top, per-line indent/length, per-token colour
    step, top = 0.058, 0.105
    k = F.floor(F.div(F.sub(top + step / 2, v), step))
    k = F.max(k, 0.0)
    line_v = F.sub(top, F.mul(k, step))
    on_line = F.mul(F.lt(F.abs(F.sub(v, line_v)), 0.0105), F.lt(k, 7.0))
    on_line = F.mul(on_line, F.gt(v, -hh + 0.03))
    r1 = F.white_noise(F.combine(k, F.mul(rnd, 97.0), 1.0))
    r2 = F.white_noise(F.combine(k, F.mul(rnd, 97.0), 2.0))
    indent = F.mul(F.floor(F.mul(r1, 3.0)), 0.045)
    start = F.add(left, indent)
    length = F.add(0.12, F.mul(r2, 0.6))
    in_len = F.between(u, start, F.add(start, length))
    token_w = 0.072
    tk = F.floor(F.div(F.sub(u, start), token_w))
    in_token = F.lt(F.fract(F.div(F.sub(u, start), token_w)), 0.84)
    tcol = F.white_noise(F.combine(tk, k, F.mul(rnd, 31.0)))
    token_color = F.ramp(tcol, [(0.0, CODE["keyword"]), (0.2, CODE["keyword"]), (0.21, CODE["type"]), (0.4, CODE["type"]),
                                (0.41, CODE["plain"]), (0.7, CODE["plain"]), (0.71, CODE["function"]), (0.8, CODE["function"]),
                                (0.81, CODE["string"]), (0.92, CODE["string"]), (0.93, CODE["number"]), (1.0, CODE["number"])],
                         interpolation="CONSTANT")
    code = F.mul(F.mul(F.mul(on_line, in_len), in_token), is_file)

    color = F.rgb(CODE["card"])
    color = F.vadd(color, F.vscale(band, F.add(F.add(stripe, header), rim)))
    color = F.vadd(color, F.vscale(F.rgb(CODE["plain"]), F.mul(title, 0.9)))
    color = F.vadd(color, F.vscale(F.rgb(CODE["comment"]), sub))
    color = F.vadd(color, F.vscale(F.rgb(CODE["border"]), divider))
    color = F.vadd(color, F.vscale(token_color, F.mul(code, 0.8)))

    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.15
    nt.links.new(color, em.inputs["Color"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(F.mul(inside, 0.94), mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    mat.surface_render_method = "BLENDED"
    return mat


def star_material():
    """Shared by all star glyphs: base + emission in the object colour; emission scaled by Object Info Alpha (glow)."""
    mat = L.make_material("StarMini", base="#FFFFFF", roughness=0.35)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    info = nt.nodes.new("ShaderNodeObjectInfo")
    F = L.Field(nt)
    nt.links.new(info.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(info.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(F.add(1.2, F.mul(info.outputs["Alpha"], 3.4)), bsdf.inputs["Emission Strength"])
    return mat


_arc_mats: dict = {}


def arc_material(color_hex, opacity, strength=2.4):
    key = (color_hex, round(opacity, 3))
    if key in _arc_mats:
        return _arc_mats[key]
    mat = bpy.data.materials.new(f"Arc_{color_hex}_{opacity:.2f}")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = L.hex_to_linear(color_hex)
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = min(1.0, opacity * 1.15)
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    mat.surface_render_method = "BLENDED"
    _arc_mats[key] = mat
    return mat


# ============================================================================ geometry
def unit_card_mesh():
    """Unit card (width 1, height 352/512) in the XY plane facing +Z, like MeshFactory.unitCard."""
    bm = bmesh.new()
    hw, hh = 0.5, CARD_ASPECT / 2
    vs = [bm.verts.new(v) for v in ((-hw, -hh, 0), (hw, -hh, 0), (hw, hh, 0), (-hw, hh, 0))]
    bm.faces.new(vs)
    me = bpy.data.meshes.new("UnitCard")
    bm.to_mesh(me)
    bm.free()
    return me


def glyph_prototypes():
    """One hidden mesh per glyph (built by build_graph_assets), re-oriented so the glyph's front is local +Z and its
    up local +Y — the same frame as a card, as in the app (the USDZ root's −90° X rotation does this there)."""
    protos = {}
    fix = Matrix.Rotation(math.radians(-90), 4, "X")   # Blender −Y (glyph front) → +Z, +Z (glyph up) → +Y
    items = list(G.GLYPHS.items()) + [("Star_Halo", (G._halo, "halo"))]
    for name, (fn, _) in items:
        o = fn(name)
        o.data.transform(fix)
        o.data.name = "Proto_" + name
        o.hide_render = True
        o.hide_viewport = True
        protos[name] = o.data
    return protos


def polyline_curve(name, pieces, radius, mat):
    """One curve object holding many POLY splines (all pieces share radius + material)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 1
    cu.use_fill_caps = True
    for pts in pieces:
        if len(pts) < 2:
            continue
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, p in enumerate(pts):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
    o = bpy.data.objects.new(name, cu)
    L.link(o)
    o.data.materials.append(mat)
    return o


def _cumulative(points):
    acc = [0.0]
    for a, b in zip(points, points[1:]):
        acc.append(acc[-1] + (b - a).length)
    return acc


def _at(points, acc, s):
    for i in range(1, len(acc)):
        if acc[i] >= s:
            span = max(acc[i] - acc[i - 1], 1e-6)
            return points[i - 1].lerp(points[i], (s - acc[i - 1]) / span)
    return points[-1].copy()


def dashes(points, dash=0.06, gap=0.045):
    """Port of EdgeSceneBuilder.dashes (constant metric dash / gap)."""
    acc = _cumulative(points)
    total = acc[-1]
    out, s0 = [], 0.0
    while s0 < total:
        s1 = min(total, s0 + dash)
        piece = [_at(points, acc, s0)] + [points[i] for i, c in enumerate(acc) if s0 < c < s1] + [_at(points, acc, s1)]
        if s1 - s0 > 0.004:
            out.append(piece)
        s0 = s1 + gap
    return out


def arrow_cone(bm, points, tube_radius):
    """Port of EdgeSceneBuilder.appendArrow: cone tip a little before the end (portfolio t ≈ 0.96)."""
    acc = _cumulative(points)
    total = acc[-1]
    length = max(0.028, tube_radius * 7)
    if total <= length * 2:
        return
    tip_f = max(0.5, 1 - (0.06 + length * 0.2) / total)
    tip = _at(points, acc, tip_f * total)
    back = _at(points, acc, (tip_f - length / total) * total)
    d = (tip - back).normalized()
    r = max(0.0095, tube_radius * 3.3)
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=0.0, depth=length)
    m = Matrix.Translation(tip - d * (length / 2)) @ rot
    bmesh.ops.transform(bm, matrix=m, verts=res["verts"])


def tube_radius(relation, emphasis):
    """Port of EdgeSceneBuilder.tubeRadius (weight 1)."""
    if relation == "contains":
        return 0.0011 if emphasis == "faint" else 0.0016
    base = 0.0021 if relation in ("uses", "imports") else 0.0031
    return base * {"faint": 0.8, "normal": 1.0, "focus": 1.6}.get(emphasis, 1.0)


# ============================================================================ scene
def fit_camera(points, azimuth=22.0, elevation=20.0, lens=30.0, fill=0.92):
    """Perspective fit: the closest camera on the (azimuth, elevation) ray from the points' centre that keeps every
    point inside `fill` of the frame, then a lens shift that centres the projected extent."""
    pts = [Vector(p) for p in points]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (lo + hi) / 2
    radius = max((p - center).length for p in pts)
    tan_h = math.tan(math.atan(36.0 / 2 / lens))   # vertical extent follows from W/H in project()
    az, el = math.radians(azimuth), math.radians(elevation)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))

    def project(dist, sx=0.0, sy=0.0):
        loc = center + d * dist
        inv = (center - loc).to_track_quat("-Z", "Y").to_matrix().inverted()
        xs, ys = [], []
        for p in pts:
            q = inv @ (p - loc)
            if q.z > -0.05:
                return None
            xs.append(q.x / -q.z / tan_h - 2 * sx)
            ys.append(q.y / -q.z / tan_h * (W / H) - 2 * sy * (W / H))
        return min(xs), max(xs), min(ys), max(ys)

    sx = sy = 0.0
    for _ in range(3):
        lo_d, hi_d = radius * 0.2, radius * 8
        for _ in range(40):
            mid = (lo_d + hi_d) / 2
            e = project(mid, sx, sy)
            if e and max(abs(e[0]), abs(e[1])) <= fill and max(abs(e[2]), abs(e[3])) <= fill:
                hi_d = mid
            else:
                lo_d = mid
        e = project(hi_d, sx, sy)
        sx += (e[0] + e[1]) / 4
        sy += (e[2] + e[3]) / 4 * (H / W)
    cam = L.add_camera("GraphCam", lens=lens)
    cam.location = center + d * hi_d
    L.look_at(cam, center)
    cam.data.shift_x, cam.data.shift_y = sx, sy
    cam.data.clip_end = 1000
    return cam


def eye_camera(lens=16.0, pitch=12.0, eye=1.45):
    """The headset view: standing at the origin, looking forward (RealityKit −Z = Blender +Y)."""
    cam = L.add_camera("EyeCam", location=(0, -0.2, eye), lens=lens)
    cam.rotation_euler = Euler((math.radians(90 + pitch), 0, 0))
    cam.data.clip_start = 0.05
    cam.data.clip_end = 1000
    return cam


def _soft_veil(name, width, height, core_u=0.30, core_v=0.22, strength=0.72, color="#04060D"):
    """Dark, semi-transparent plane that is solid over its core (|u| < core_u, |v| < core_v in the plane's
    −0.5…0.5 object space) and fades to nothing at its edges — a backing for text drawn over busy geometry."""
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    veil = bpy.context.active_object
    veil.name = name
    veil.scale = (width, height, 1)
    mat = bpy.data.materials.new(name + "Mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    F = L.Field(nt)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    u, v, _ = F.separate(coord.outputs["Object"])
    alpha = F.mul(F.mul(F.smooth_edge(F.abs(u), core_u, 0.5), F.smooth_edge(F.abs(v), core_v, 0.5)), strength)
    transparent = nt.nodes.new("ShaderNodeBsdfTransparent")
    dark = nt.nodes.new("ShaderNodeEmission")
    dark.inputs["Color"].default_value = L.hex_to_linear(color)
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(alpha, mix.inputs["Fac"])
    nt.links.new(transparent.outputs[0], mix.inputs[1])
    nt.links.new(dark.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    mat.surface_render_method = "BLENDED"
    veil.data.materials.append(mat)
    return veil


def camera_caption(cam, title, subtitle, font=None, depth=0.06):
    """Caption pinned to the camera's top-left corner, on a soft dark veil so arcs and cards passing behind it
    (the sphere's outer hubs reach that corner) never run through the letters. Text and veil sit `depth` metres
    in front of the lens, closer than any geometry."""
    hfov = 2 * math.atan(36.0 / 2 / cam.data.lens)
    cam.data.clip_start = min(cam.data.clip_start, depth / 3)
    half_w = math.tan(hfov / 2) * depth          # frame half-width at `depth`
    half_h = half_w * H / W
    sx, sy = cam.data.shift_x * 2 * half_w, cam.data.shift_y * 2 * half_w
    t = text("CapTitle", title, 0.042, (0, 0, 0), rotation=(0, 0, 0), color="#E8ECF6", strength=2.0, font=font)
    s = text("CapSub", subtitle, 0.026, (0, 0, 0), rotation=(0, 0, 0), color="#A9B1CC", strength=1.5, font=font)
    left = -half_w + 0.05 * half_w + sx
    for o, dy in ((t, 0.06), (s, 0.112)):
        o.parent = cam
        o.location = (left, half_h - dy * half_w + sy, -depth)
        o.scale = (half_w,) * 3
        o.data.align_y = "TOP"
    bpy.context.view_layer.update()
    right = left + max(t.dimensions.x, s.dimensions.x)
    top = t.location.y
    bottom = s.location.y - s.dimensions.y
    # Nearly opaque over the text: emissive arcs are far brighter than 1.0 (linear), so a half-transparent
    # backing would still show them through the letters.
    pad = 0.035 * half_w
    veil = _soft_veil("CapVeil", (right - left + 2 * pad) / 0.6, (top - bottom + 2 * pad) / 0.44, strength=0.97)
    _camera_space(cam, veil, (left + right) / 2, (top + bottom) / 2, -depth * 1.004)


def build_constellation(snap, cam_location, tube_scale=RENDER_TUBE_SCALE):
    """Cards (billboarded to the camera), role stars at their top-left corners, relation tubes, arrowheads."""
    card_me = unit_card_mesh()
    cmat = card_material()
    smat = star_material()
    protos = glyph_prototypes()
    objs = []
    for n in snap["nodes"]:
        pos = rk_to_bl(n["position"])
        w = n["cardWidth"]
        card = bpy.data.objects.new("Card_" + n["id"][:40], card_me)
        L.link(card)
        card.data.materials.clear() if card.data.materials and False else None
        card.location = pos
        rot = (Vector(cam_location) - pos).to_track_quat("Z", "Y")
        card.rotation_mode = "QUATERNION"
        card.rotation_quaternion = rot
        card.scale = (w, w, w)
        hub = n["kind"] in ("folder", "module")
        card.color = (*L.hex_to_linear(n["layerColor"])[:3], 0.5 if hub else 1.0)
        objs.append(card)
        # star above the top-left corner (StarEncoder anchor: x = −w/2 + s·0.55, y = h/2 + s·0.65, z = +1 cm)
        s = n["starSize"]
        local = Vector((-w / 2 + s * 0.55, w * CARD_ASPECT / 2 + s * 0.65, 0.01))
        star = bpy.data.objects.new("Star_" + n["id"][:40], protos[n["glyph"]])
        L.link(star)
        star.rotation_mode = "QUATERNION"
        star.rotation_quaternion = rot
        star.location = pos + rot @ local
        star.scale = (s / 0.1,) * 3
        star.color = (*L.hex_to_linear(n["starColor"])[:3], n["starGlow"])
        objs.append(star)
    card_me.materials.append(cmat)
    for pr in protos.values():
        pr.materials.clear()
        pr.materials.append(smat)

    # relations: group pieces by (colour, opacity, radius)
    groups: dict = {}
    cones: dict = {}
    for a in snap["arcs"]:
        pts = [rk_to_bl(p) for p in a["points"]]
        r = tube_radius(a["relation"], a["emphasis"]) * tube_scale
        key = (a["color"], round(a["opacity"], 3), round(r, 5))
        groups.setdefault(key, []).extend(dashes(pts) if a["dashed"] else [pts])
        if a["relation"] != "contains" and a["flow"]:
            bm = cones.setdefault((a["color"], round(a["opacity"], 3)), bmesh.new())
            arrow_cone(bm, pts, r / tube_scale * 1.4)
    for i, ((color, opacity, r), pieces) in enumerate(groups.items()):
        objs.append(polyline_curve(f"Arcs{i}", pieces, r, arc_material(color, opacity, strength=1.6 if color == "#6B7390" else 2.6)))
    for i, ((color, opacity), bm) in enumerate(cones.items()):
        o = L._bm_object(f"Arrows{i}", bm)
        o.data.materials.append(arc_material(color, max(opacity, 0.7), strength=3.0))
        objs.append(o)
    return objs


def graph_scene(samples):
    _arc_mats.clear()   # datablocks die with the old scene
    sc = L.reset_scene()
    L.setup_cycles(sc, samples=samples, denoise=True, view_transform="AgX")
    sc.cycles.max_bounces = 4
    sc.cycles.transparent_max_bounces = 32
    L.set_world_image(sc, RA.SKY, strength=1.0)
    RA.add_floor(grid_span=24.0, grid_hex=P["grid"], grid_strength=2.4)
    L.add_glare(sc, threshold=0.9, strength=0.45, size=7)
    return sc


def render_layout(style, samples=SAMPLES, out_dir=None, view="overview"):
    """`overview`: a third-person three-quarter view of the whole constellation (gallery);
    `eye`: what the headset shows from the viewer's spot at the centre."""
    snap = load_snapshot(style)
    sc = graph_scene(samples)
    pts = [rk_to_bl(n["position"]) for n in snap["nodes"]]
    if view == "eye":
        cam = eye_camera()
    else:
        pts.append(Vector((0, 0, 0)))  # keep the viewer's spot (floor centre) in frame
        az = {"wall": 10.0, "spiral": 18.0}.get(style, 24.0)
        el = {"celestial": 26.0, "sphere": 24.0, "wall": 14.0, "spiral": 16.0}.get(style, 22.0)
        cam = fit_camera(pts, azimuth=az, elevation=el, lens=32.0)
    bpy.context.view_layer.update()
    # true tube size at eye level (tubes pass close to the viewer), thickened for the far overview
    build_constellation(snap, cam.matrix_world.translation, tube_scale=1.0 if view == "eye" else RENDER_TUBE_SCALE)
    title, sub = CAPTIONS[style]
    camera_caption(cam, title + ("  ·  eye level" if view == "eye" else ""), sub)
    suffix = "_eye" if view == "eye" else ""
    out = os.path.join(out_dir or L.RENDERS_DIR, f"layout_{style}{suffix}.png")
    t0 = time.time()
    L.render_to(sc, out, W, H)
    print(f"[constellate] render layout_{style}{suffix}: {len(snap['nodes'])} cards, {len(snap['arcs'])} arcs in {time.time() - t0:.1f}s")
    return out


# ============================================================================ legends
GLYPH_LABELS = {"Star_Folder": "Folder hub", "Star_Module": "Module (root)", "Star_Halo": "Cycle halo", "Star_Other": "Other"}
HUB_COLORS = {"Star_Folder": P["lavender"], "Star_Module": P["coreWhite"], "Star_Halo": "#FF5F6D"}


def render_node_stars(samples=SAMPLES, out_dir=None):
    snap = load_snapshot("celestial")
    roles = {r["glyph"]: r for r in snap["roles"]}
    sc = RA.studio(floor=False, glare=True)
    sc.cycles.samples = samples
    names = list(G.GLYPHS) + ["Star_Halo"]
    cols, gap_x, gap_y = 5, 0.36, 0.42
    objs = []
    for i, name in enumerate(names):
        fn = G.GLYPHS[name][0] if name in G.GLYPHS else G._halo
        o = fn(name)
        cx = (i % cols - (cols - 1) / 2) * gap_x
        cz = -(i // cols) * gap_y + gap_y
        o.scale = (2.4, 2.4, 2.4)
        o.rotation_euler = Euler((math.radians(-14), 0, math.radians(24)))
        o.location = (cx, 0, cz)
        color = HUB_COLORS.get(name) or roles.get(name, {}).get("color", "#8B93A5")
        L.assign(o, L.make_material(f"{name}Mat", base=color, roughness=0.32, emission=color, strength=1.4))
        label = GLYPH_LABELS.get(name) or roles.get(name, {}).get("label") or name.replace("Star_", "")
        objs += [o, text(f"Lbl{i}", label, 0.042, (cx, 0, cz - 0.17), align="CENTER", color="#DCE1F0", strength=1.5)]
    text("Title", "Node stars  —  shape = role · colour = layer · size = fan-in · glow = recency · ring = cycle",
         0.04, (0, 0, gap_y + 0.25), align="CENTER", color="#E8ECF6", strength=1.8)
    L.add_camera(location=(0, -6, 0.04), target=(0, 0, 0.04), lens=50, ortho_scale=2.34)
    out = os.path.join(out_dir or L.RENDERS_DIR, "node_stars.png")
    L.render_to(sc, out, 1600, 1000)
    print(f"[constellate] render node_stars -> {out}")
    return out


def render_relation_legend(samples=SAMPLES, out_dir=None):
    snap = load_snapshot("celestial")
    entries = snap["legend"]
    _arc_mats.clear()
    sc = L.reset_scene()
    L.setup_cycles(sc, samples=samples, denoise=True, view_transform="AgX")
    world = bpy.data.worlds.new("Legend")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = L.hex_to_linear("#0A0C16")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = world
    L.add_glare(sc, threshold=0.8, strength=0.5, size=7)
    font = _font(korean=True)
    row = 0.14
    top = row * (len(entries) - 1) / 2 - 0.05
    for i, e in enumerate(entries):
        z = top - i * row
        a, b = Vector((-0.35, 0, z - 0.02)), Vector((0.85, 0, z - 0.02))
        ctrl = (a + b) / 2 + Vector((0, 0, 0.07))
        pts = [a * (1 - t) ** 2 + ctrl * (2 * (1 - t) * t) + b * t * t for t in (k / 40 for k in range(41))]
        r = 0.0062
        pieces = dashes(pts, dash=0.06, gap=0.045) if e["dashed"] else [pts]
        polyline_curve(f"Leg{i}", pieces, r, arc_material(e["color"], 0.9, strength=3.0))
        if e["flow"]:
            bm = bmesh.new()
            arrow_cone(bm, pts, r * 1.05)
            o = L._bm_object(f"LegArrow{i}", bm)
            o.data.materials.append(arc_material(e["color"], 1.0, strength=3.4))
            for f in (0.22, 0.5, 0.72):   # flow particles, as the app animates them
                acc = _cumulative(pts)
                p = _at(pts, acc, f * acc[-1])
                dot = L.add_sphere(f"LegDot{i}_{f}", 0.011, location=p, segments=12, rings=6)
                L.assign(dot, L.make_material(f"LegDot{i}_{f}", base="#FFFFFF", emission=e["color"], strength=9.0))
        label = f"{e['labelEn']}"
        text(f"LegEn{i}", label, 0.05, (-1.25, 0, z - 0.035), color="#E8ECF6", strength=1.8)
        if font is not None:
            text(f"LegKo{i}", e["labelKo"], 0.05, (-0.8, 0, z - 0.035), color="#9AA3C0", strength=1.5, font=font, glyph_height=0.042)
        tags = ("dashed" if e["dashed"] else "solid") + (" · flow" if e["flow"] else "")
        text(f"LegTag{i}", tags, 0.032, (0.95, 0, z - 0.03), color="#7A84A6", strength=1.3)
    text("LegTitle", "Relations  —  colour = kind · dash = type-system · arrow + particles = flow", 0.048,
         (-1.25, 0, top + 0.16), color="#E8ECF6", strength=1.9)
    L.add_camera(location=(0.05, -6, 0.0), target=(0.05, 0, 0.0), lens=50, ortho_scale=2.95)
    out = os.path.join(out_dir or L.RENDERS_DIR, "relation_legend.png")
    L.render_to(sc, out, 1600, 1000)
    print(f"[constellate] render relation_legend -> {out}")
    return out


# ============================================================================ hero
def _camera_space(cam, obj, x, y, z=-1.0):
    """Parent `obj` to the camera (or to a HUD empty under it) at (x, y, z) in that space, unrotated."""
    obj.parent = cam
    obj.location = (x, y, z)
    obj.rotation_euler = (0, 0, 0)


def _pill(name, label, color, x, y, cam, height=0.034, font=None, strength=1.0):
    """Rounded outline + label in camera space (README platform pills); `cam` may be a HUD empty. `strength`
    scales the label's (1.8) and outline's (2.2) emission."""
    t = text(f"{name}Txt", label, height * 0.52, (0, 0, 0), rotation=(0, 0, 0), color="#E8ECF6", strength=1.8 * strength, align="CENTER", font=font)
    t.data.align_y = "CENTER"
    bpy.context.view_layer.update()
    w = max(t.dimensions.x + height * 1.1, height * 2.6)
    outer = L.rounded_rect_outline(w, height, height / 2, seg=8)
    inner = L.rounded_rect_outline(w - 0.003, height - 0.003, height / 2 - 0.0015, seg=8)
    ring = L.frame_from_outlines(f"{name}Ring", outer, inner, 0.0005)
    L.assign(ring, L.make_material(f"{name}RingMat", base="#000000", emission=color, strength=2.2 * strength))
    for o, dz in ((ring, 0.0), (t, 0.0005)):
        _camera_space(cam, o, x + w / 2, y, -1.0 + dz)
    return w


# Depth (metres in front of the lens) of the hero's title block; see render_hero.
HUD_DEPTH = 0.05


def render_hero(samples=SAMPLES, out_path=None, icon_path=None):
    """README hero (2400×1200): the default celestial constellation rising over the meeting stage — v2 assets,
    Milky Way sky, astrolabe floor — with the title block on the left. Text is rendered in Blender too, so the hero is
    reproducible from this script alone (Inter for Latin, bundled Noto Sans CJK for Korean)."""
    global W, H
    W0, H0 = W, H
    W, H = 2400, 1200
    try:
        snap = load_snapshot("celestial")
        sc = graph_scene(samples)
        # meeting stage at the viewer's spot, three participants on the far side, the host orb, a beacon
        A = RA.A
        objs = A.build_stage_ring(accent_hex=P["skyBlue"])
        seats = A.seat_positions(1.0)
        for i, (seat_idx, accent) in enumerate(((5, P["lavender"]), (0, P["cyan"]), (1, P["pink"]))):
            pos = seats[seat_idx]
            objs += A.build_avatar_bust(origin=(pos[0], pos[1], 0.0), name=f"Avatar{i}", accent_hex=accent, yaw_deg=RA._facing_yaw(pos))
        objs += A.build_host_orb(origin=(0.0, 0.55, 1.3))
        beacon_node = max(snap["nodes"], key=lambda n: (n["kind"] == "file", -n["position"][2] + n["position"][0] * 0.3))
        bpos = rk_to_bl(beacon_node["position"])
        objs += A.build_beacon(origin=(bpos.x, bpos.y, 0.0))

        # frame the whole sky from just outside it, low, then slide it right: the title block sits on the left
        pts = [rk_to_bl(n["position"]) for n in snap["nodes"]] + [Vector((0, 0, 0))]
        cam = fit_camera(pts, azimuth=28.0, elevation=10.0, lens=30.0, fill=0.78)
        cam.data.shift_x -= 0.37   # clears the tagline and the title's glow off the cloud's left edge
        bpy.context.view_layer.update()
        build_constellation(snap, cam.matrix_world.translation, tube_scale=1.25)

        # Title block = a HUD parented to the camera and scaled to HUD_DEPTH: coordinates below are written as if at
        # 1 m, but the block sits a few centimetres in front of the lens, so nothing in the scene can ever come
        # between it and the camera (framed from just outside the sky, the nearest cards are within a metre).
        hud = bpy.data.objects.new("HeroHUD", None)
        L.link(hud)
        hud.parent = cam
        hud.scale = (HUD_DEPTH,) * 3
        cam.data.clip_start = min(cam.data.clip_start, HUD_DEPTH / 4)

        # Dark veil over the left of the frame, fading out to the right, behind the whole title block (−1.05; text,
        # icon and pills at −0.999). Text strengths are absolute: only the title (1.6) crosses the glare threshold (0.9).
        half_w = math.tan(math.atan(36.0 / 2 / cam.data.lens))
        half_h = half_w * H / W
        sx = cam.data.shift_x * 2 * half_w
        bpy.ops.mesh.primitive_plane_add(size=1.0)
        veil = bpy.context.active_object
        veil.name = "Veil"
        veil.scale = (half_w * 2.2, half_h * 2.2, 1)
        vm = bpy.data.materials.new("VeilMat")
        vm.use_nodes = True
        nt = vm.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        F = L.Field(nt)
        coord = nt.nodes.new("ShaderNodeTexCoord")
        u, _, _ = F.separate(coord.outputs["Object"])
        alpha = F.mul(F.smooth_edge(u, -0.2, 0.06), 0.9)              # opaque on the left, gone past the middle
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = L.hex_to_linear("#04060D")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(alpha, mix.inputs["Fac"])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        vm.surface_render_method = "BLENDED"
        veil.data.materials.append(vm)
        _camera_space(hud, veil, sx, 0, -1.05)

        left = sx - half_w + 0.075 * half_w * 2
        top = half_h
        ko = _font(korean=True)
        icon = icon_path or os.path.join(L.ICON_DIR, "AppIcon-1024.png")
        size_icon = 0.085
        if os.path.exists(icon):
            bpy.ops.mesh.primitive_plane_add(size=1.0)
            plane = bpy.context.active_object
            plane.name = "HeroIcon"
            plane.scale = (size_icon, size_icon, 1)
            im = bpy.data.materials.new("HeroIconMat")
            im.use_nodes = True
            n2 = im.node_tree
            n2.nodes.clear()
            o2 = n2.nodes.new("ShaderNodeOutputMaterial")
            e2 = n2.nodes.new("ShaderNodeEmission")
            tex = n2.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(icon, check_existing=True)
            n2.links.new(tex.outputs["Color"], e2.inputs["Color"])
            # app-icon corners: radius 22.4 % of the side (render_icons.py's mac tile), anti-aliased over ~1 px
            F2 = L.Field(n2)
            c2 = n2.nodes.new("ShaderNodeTexCoord")
            u2, v2, _ = F2.separate(c2.outputs["Object"])
            mask = F2.smooth_edge(F2.rounded_rect_sdf(u2, v2, 0.5, 0.5, 0.224), -0.003, 0.003)
            clear = n2.nodes.new("ShaderNodeBsdfTransparent")
            cut = n2.nodes.new("ShaderNodeMixShader")
            n2.links.new(mask, cut.inputs["Fac"])
            n2.links.new(clear.outputs[0], cut.inputs[1])
            n2.links.new(e2.outputs[0], cut.inputs[2])
            n2.links.new(cut.outputs[0], o2.inputs["Surface"])
            plane.data.materials.append(im)
            _camera_space(hud, plane, left + size_icon / 2, top * 0.52, -1.0 + 0.001)
        title = text("HeroTitle", "Constellate", 0.082, (0, 0, 0), rotation=(0, 0, 0), color="#F4F6FB", strength=1.6)
        title.data.align_y = "CENTER"
        _camera_space(hud, title, left + size_icon + 0.03, top * 0.52, -1.0 + 0.001)
        lines = [
            ("HeroTag", "Walk your codebase as a living constellation.", 0.034, "#5EE1FF", 0.5, None, top * 0.28),
            ("HeroSub", "Relations by meaning · six sky layouts · on-device host AI · voice summon", 0.019, "#DCE1F0", 0.2, None, top * 0.17),
        ]
        for name, body, size, color, strength, font, y in lines:
            o = text(name, body, size, (0, 0, 0), rotation=(0, 0, 0), color=color, strength=strength, font=font)
            _camera_space(hud, o, left, y, -1.0 + 0.001)
        for i, body in enumerate(("팀이 이머시브 공간에서 코드 별자리를 함께 걷고, 관계의 의미를 읽고,",
                                  "방장의 온디바이스 AI에게 묻고, 말로 코드를 불러냅니다.")):
            o = text(f"HeroKo{i}", body, 0.016, (0, 0, 0), rotation=(0, 0, 0), color="#B8C0D8", strength=0.18, font=ko,
                     glyph_height=0.0165 if ko is not None else None)
            _camera_space(hud, o, left, top * (0.04 - 0.1 * i), -1.0 + 0.001)
        x = left
        for label, color in (("visionOS 27", P["lavender"]), ("iPadOS 27", P["cyan"]), ("macOS 27", P["amber"])):
            x += _pill(f"Pill{label.split()[0]}", label, color, x, top * -0.24, hud, height=0.028, strength=0.1) + 0.018

        out_path = out_path or os.path.join(L.DOCS_IMAGES_DIR, "hero.png")
        t0 = time.time()
        L.render_to(sc, out_path, W, H)
        print(f"[constellate] render hero -> {out_path} in {time.time() - t0:.1f}s")
        return out_path
    finally:
        W, H = W0, H0


# ============================================================================ gallery
def compose_gallery(styles=STYLES, out_dir=None, cols=3):
    out_dir = out_dir or L.RENDERS_DIR
    tiles = []
    for s in styles:
        path = os.path.join(out_dir, f"layout_{s}.png")
        if not os.path.exists(path):
            continue
        img = bpy.data.images.load(path, check_existing=False)
        w, h = img.size
        px = np.empty(w * h * img.channels, np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, img.channels)[::-1, :, :3]
        bpy.data.images.remove(img)
        tiles.append(px[: h - h % 2, : w - w % 2].reshape(h // 2, 2, w // 2, 2, 3).mean(axis=(1, 3)))
    if not tiles:
        return None
    th, tw = tiles[0].shape[:2]
    gap = 6
    rows = math.ceil(len(tiles) / cols)
    sheet = np.full((rows * th + (rows + 1) * gap, cols * tw + (cols + 1) * gap, 3), 0.03, np.float32)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        y, x = gap + r * (th + gap), gap + c * (tw + gap)
        sheet[y:y + th, x:x + tw] = t
    out = os.path.join(out_dir, "layout_gallery.png")
    L.write_png(out, (np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8).tobytes(), sheet.shape[1], sheet.shape[0], 3)
    print(f"[constellate] layout_gallery {sheet.shape[1]}x{sheet.shape[0]} -> {out}")
    return out


def main(argv):
    global W, H
    quick = "--quick" in argv
    samples = 12 if quick else SAMPLES
    if quick:
        W, H = 800, 500
    L.ensure_dirs()
    styles = [a for a in argv if a in STYLES]
    flags = {a for a in argv if a.startswith("--")} - {"--quick"}
    everything = not styles and not flags
    for s in (styles or (STYLES if everything else [])):
        render_layout(s, samples=samples)
    if everything or "--eye" in flags:
        render_layout("celestial", samples=samples, view="eye")
    if everything or "--gallery" in flags:
        compose_gallery()
    if everything or "--stars" in flags:
        render_node_stars(samples=samples)
    if everything or "--legend" in flags:
        render_relation_legend(samples=samples)
    if everything or "--hero" in flags:
        render_hero(samples=samples)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
