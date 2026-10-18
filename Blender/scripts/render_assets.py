"""Cycles renders for README / design PRD, plus the app icon.

Outputs (Blender/renders/): host_orb, cluster_orb, avatar_bust, beacon, review_pin, stage_ring,
pointer_dart, theme_dark, theme_tinted_ocean, asset_sheet (.png, 1280x960, <=64 samples).
Icon: Constellate/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (1024x1024).

Run standalone:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python render_assets.py -- [name ...] [--icon]
"""
from __future__ import annotations

import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import constellate_lib as L  # noqa: E402
import build_assets as A  # noqa: E402

P = L.PALETTE
SKY = os.path.join(L.TEXTURES_DIR, "Sky_Dark.png")
TINT = os.path.join(L.TEXTURES_DIR, "Sky_Tint.png")
GRID = os.path.join(L.TEXTURES_DIR, "Floor_Grid.png")
W, H = 1280, 960
SAMPLES = 64

OCEAN_HUE = 210
OCEAN_SKY_LO = L.hsl_to_hex(OCEAN_HUE, 0.30, 0.06)
OCEAN_SKY_HI = L.hsl_to_hex(OCEAN_HUE, 0.34, 0.17)
OCEAN_ACCENT = L.hsl_to_hex(OCEAN_HUE, 0.75, 0.72)
OCEAN_GRID = L.hsl_to_hex(OCEAN_HUE, 0.30, 0.24)


# ---------------------------------------------------------------------------- studio
def add_floor(size=120.0, grid_span=24.0, base_hex=P["floor"], grid_hex=P["grid"], grid_strength=2.0, z=0.0):
    """Large dark floor (edge stays beyond the camera) with the 24 m grid texture clipped in the centre."""
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    floor = bpy.context.active_object
    floor.name = "Floor"
    mat = bpy.data.materials.new("FloorMat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = L.hex_to_linear(base_hex)
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Specular IOR Level"].default_value = 0.6
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(GRID, check_existing=True)
    tex.image.alpha_mode = "STRAIGHT"
    tex.extension = "CLIP"
    uv = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    k = size / grid_span
    mapping.inputs["Scale"].default_value = (k, k, 1.0)
    mapping.inputs["Location"].default_value = (0.5 - 0.5 * k, 0.5 - 0.5 * k, 0.0)
    nt.links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    bsdf.inputs["Emission Color"].default_value = L.hex_to_linear(grid_hex)
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = grid_strength
    nt.links.new(tex.outputs["Alpha"], mul.inputs[0])
    nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
    floor.data.materials.append(mat)
    return floor


def studio(tinted=False, floor=True, floor_size=24.0, glare=True):
    """Fresh scene: Cycles, sky world, three area lights, optional grid floor."""
    L.GLASS_TRANSMISSION = True  # render-only glass
    sc = L.reset_scene()
    # AgX for presentation renders so HDR emissives (core strength 4) roll off instead of clipping to white.
    L.setup_cycles(sc, samples=SAMPLES, denoise=True, view_transform="AgX")
    if tinted:
        # Tinted rule: luminance map x horizon colour HSL(210,0.34,0.17); zenith/bottom fall to ~HSL(210,0.30,0.06)
        L.set_world_image(sc, TINT, strength=1.0, tint_hex=OCEAN_SKY_HI)
    else:
        L.set_world_image(sc, SKY, strength=1.0)
    # neutral key, lavender fill, cool-white rim (no cyan/green cast on the floor)
    key_hex, fill_hex, rim_hex = ("#FFFFFF", "#CFE3FF", "#FFFFFF") if tinted else ("#FFFFFF", "#B9B0FF", "#DDE3FF")
    L.add_area_light("Key", (3.0, -4.0, 4.5), key_hex, energy=600, size=3.0)
    L.add_area_light("Fill", (-4.5, -2.0, 2.0), fill_hex, energy=140, size=4.0)
    L.add_area_light("Rim", (0.5, 5.0, 3.0), rim_hex, energy=160, size=2.5)
    if floor:
        add_floor(grid_span=floor_size, grid_hex=OCEAN_GRID if tinted else P["grid"])
    if glare:
        L.add_glare(sc, threshold=1.2, strength=0.35, size=7)
    return sc


def _scale_lights(objs, factor):
    """Scale light positions/energy for very small subjects so the lighting stays soft."""
    for name in ("Key", "Fill", "Rim"):
        lo = bpy.data.objects.get(name)
        if lo:
            lo.location = Vector(lo.location) * factor
            lo.data.size *= factor
            lo.data.energy *= factor * factor
            L.look_at(lo, Vector((0, 0, 0)))


# ---------------------------------------------------------------------------- single assets
SINGLE = {
    # name: (builder, kwargs, subject height z, azimuth, elevation, margin, light scale)
    "host_orb": (A.build_host_orb, {"origin": (0, 0, 0.45)}, 30, 12, 1.15, 0.35),
    "cluster_orb": (A.build_cluster_orb, {"origin": (0, 0, 0.5)}, 30, 10, 1.15, 0.4),
    "avatar_bust": (A.build_avatar_bust, {"origin": (0, 0, 0), "yaw_deg": 180 + 25}, 25, 12, 1.2, 0.6),
    "beacon": (A.build_beacon, {"origin": (0, 0, 0)}, 30, 8, 1.1, 1.0),
    "review_pin": (A.build_review_pin, {"origin": (0, 0, 0)}, 35, 15, 1.3, 0.12),
    "stage_ring": (A.build_stage_ring, {"origin": (0, 0, 0)}, 20, 32, 1.05, 1.0),
    "pointer_dart": (A.build_pointer_dart, {"origin": (0, 0, 0.1)}, 40, 20, 1.3, 0.1),
}


def render_single(name):
    fn, kw, az, el, margin, lscale = SINGLE[name]
    sc = studio()
    objs = fn(**kw)
    if name == "pointer_dart":   # point the dart at the camera-ish, tilted down
        objs[0].rotation_euler = (math.radians(-20), 0, math.radians(200))
    if lscale != 1.0:
        _scale_lights(objs, lscale)
    cam = L.add_camera()
    L.frame_objects(cam, objs, azimuth_deg=az, elevation_deg=el, margin=margin, lens=50)
    cam.data.dof.use_dof = False
    out = os.path.join(L.RENDERS_DIR, f"{name}.png")
    t0 = time.time()
    size = L.render_to(sc, out, W, H)
    print(f"[constellate] render {name}: {size} bytes in {time.time() - t0:.1f}s")
    return out


# ---------------------------------------------------------------------------- theme compositions
def _facing_yaw(pos):
    """Yaw (deg) so the avatar's +Y front points at the origin from `pos`."""
    d = -Vector((pos[0], pos[1], 0.0))
    return math.degrees(math.atan2(d.y, d.x)) - 90.0


def build_theme_scene(tinted=False):
    sc = studio(tinted=tinted)
    accent_avatars = [OCEAN_ACCENT] * 3 if tinted else [P["lavender"], P["cyan"], P["pink"]]
    seat_accent = OCEAN_ACCENT if tinted else P["skyBlue"]
    objs = []
    objs += A.build_stage_ring(accent_hex=seat_accent)
    seats = A.seat_positions(1.0)
    for i, seat_idx in enumerate((5, 0, 1)):           # three seats on the far side, facing the camera
        pos = seats[seat_idx]
        objs += A.build_avatar_bust(origin=(pos[0], pos[1], 0.0), name=f"Avatar{i}",
                                    accent_hex=accent_avatars[i], yaw_deg=_facing_yaw(pos))
    objs += A.build_host_orb(origin=(0, 0, 1.25))
    for i, pos in enumerate([(-2.3, 2.6, 1.7), (2.7, 3.2, 2.2), (-3.4, 5.4, 2.5), (1.9, 6.4, 1.5)]):
        objs += A.build_cluster_orb(origin=pos, name=f"Cluster{i}")
    objs += A.build_beacon(origin=(4.2, 7.0, 0.0))
    cam = L.add_camera(location=(1.6, -5.6, 2.4), target=(0.1, 1.6, 1.0), lens=35)
    return sc, objs, cam


def render_theme(name, tinted):
    sc, objs, cam = build_theme_scene(tinted=tinted)
    out = os.path.join(L.RENDERS_DIR, f"{name}.png")
    t0 = time.time()
    size = L.render_to(sc, out, W, H)
    print(f"[constellate] render {name}: {size} bytes in {time.time() - t0:.1f}s")
    return out


# ---------------------------------------------------------------------------- asset sheet
SHEET = [
    ("HostOrb", A.build_host_orb, {}, "HostOrb\nr 0.12 m"),
    ("ClusterOrb", A.build_cluster_orb, {}, "ClusterOrb\nr 0.18 m"),
    ("Avatar_Bust", A.build_avatar_bust, {"yaw_deg": 180}, "Avatar_Bust\nh 0.45 m"),
    ("Beacon", A.build_beacon, {}, "Beacon\nh 3.0 m"),
    ("ReviewPin", A.build_review_pin, {}, "ReviewPin\nh 0.08 m"),
    ("Stage_Ring", A.build_stage_ring, {}, "Stage_Ring\nr 1.2 m"),
    ("Pointer_Dart", A.build_pointer_dart, {}, "Pointer_Dart\n0.05 m"),
]


def render_asset_sheet():
    sc = studio(floor=False)
    label_mat = L.make_material("Label", base="#F4F6FB", roughness=0.6, emission="#F4F6FB", strength=1.0)
    spacing = 0.78
    display = 0.52
    all_objs = []
    x0 = -spacing * (len(SHEET) - 1) / 2
    for i, (key, fn, kw, label) in enumerate(SHEET):
        objs = fn(**kw)
        lo, hi = L.bounds(objs)
        ext = hi - lo
        s = display / max(ext.x, ext.y, ext.z)
        holder = L.add_empty(f"Holder_{key}", location=(x0 + i * spacing, 0, 0.0), scale=s)
        for o in objs:
            o.parent = holder
        # centre the scaled asset vertically on z = 0.42
        centre_z = (lo.z + hi.z) / 2 * s
        holder.location.z = 0.42 - centre_z
        if key == "Pointer_Dart":
            holder.rotation_euler = (0, 0, math.radians(180))
        txt = L.add_text(f"Label_{key}", label, size=0.055, location=(x0 + i * spacing, 0, 0.02), rotation=(math.pi / 2, 0, 0))
        L.assign(txt, label_mat)
        all_objs += objs + [txt]
    # tabletop line under the row for grounding
    cam = L.add_camera(location=(0, -4.6, 0.9), target=(0, 0, 0.32), lens=50)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = spacing * len(SHEET) + 0.3
    _scale_lights(all_objs, 0.5)
    out = os.path.join(L.RENDERS_DIR, "asset_sheet.png")
    t0 = time.time()
    size = L.render_to(sc, out, W, H)
    print(f"[constellate] render asset_sheet: {size} bytes in {time.time() - t0:.1f}s")
    return out


# ---------------------------------------------------------------------------- app icon
def render_icon(out_path=None):
    out_path = out_path or os.path.join(L.ICON_DIR, "AppIcon-1024.png")
    L.GLASS_TRANSMISSION = True
    sc = L.reset_scene()
    L.setup_cycles(sc, samples=SAMPLES, denoise=True, view_transform="AgX")
    sc.world = bpy.data.worlds.new("IconWorld")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    # backdrop: radial indigo -> black
    bpy.ops.mesh.primitive_plane_add(size=4.0, location=(0, 1.2, 0), rotation=(math.pi / 2, 0, 0))
    back = bpy.context.active_object
    back.name = "Backdrop"
    bm = bpy.data.materials.new("Backdrop")
    bm.use_nodes = True
    nt = bm.node_tree
    nt.nodes.clear()
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    coord = nt.nodes.new("ShaderNodeTexCoord")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    mapn = nt.nodes.new("ShaderNodeMapping")
    mapn.inputs["Scale"].default_value = (1.35, 1.35, 1.35)
    nt.links.new(coord.outputs["Object"], mapn.inputs["Vector"])
    nt.links.new(mapn.outputs["Vector"], grad.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = L.hex_to_linear("#232A5E")
    e = ramp.color_ramp.elements.new(0.55)
    e.color = L.hex_to_linear("#0B0E22")
    nt.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], outn.inputs["Surface"])
    back.data.materials.append(bm)
    # orb
    orb = A.build_host_orb(origin=(0, 0, 0))
    # three "code card" glints
    glints = []
    for i, (pos, rot, hex_) in enumerate([
        ((-0.215, 0.25, 0.165), (0.25, 0.1, -0.3), P["cyan"]),
        ((0.235, 0.20, -0.105), (-0.2, -0.15, 0.35), P["pink"]),
        ((-0.145, 0.18, -0.215), (0.3, 0.2, 0.15), P["amber"]),
    ]):
        # NB: primitive_*_add ignores `scale` when `rotation` is also given -> set the object scale explicitly
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=pos)
        card = bpy.context.active_object
        card.name = f"Card{i}"
        card.scale = (0.052, 0.034, 1.0)
        card.rotation_euler = (math.pi / 2 + rot[0], rot[1], rot[2])
        L.apply_transforms([card])
        L.bevel(card, width=0.006, segments=3)
        cm = L.make_material(f"Card{i}", base="#0E1220", roughness=0.4, emission=hex_, strength=1.6, alpha=0.9)
        card.data.materials.append(cm)
        spark = L.add_sphere(f"Spark{i}", 0.0045, location=(pos[0] + 0.02, pos[1] - 0.01, pos[2] + 0.012), segments=16, rings=8)
        sm = L.make_material(f"Spark{i}", base="#FFFFFF", emission="#FFFFFF", strength=30.0)
        spark.data.materials.append(sm)
        glints += [card, spark]
    L.add_area_light("Key", (0.8, -1.0, 1.0), "#FFFFFF", energy=60, size=1.0)
    L.add_area_light("Fill", (-1.0, -0.6, -0.3), P["lavender"], energy=25, size=1.5)
    L.add_glare(sc, threshold=1.0, strength=0.5, size=8)
    cam = L.add_camera(location=(0, -3.0, 0), target=(0, 0, 0), lens=50)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.68
    t0 = time.time()
    size = L.render_to(sc, out_path, 1024, 1024)
    print(f"[constellate] render icon: {size} bytes in {time.time() - t0:.1f}s")
    return out_path


ALL = ["host_orb", "cluster_orb", "avatar_bust", "beacon", "review_pin", "stage_ring", "pointer_dart",
       "theme_dark", "theme_tinted_ocean", "asset_sheet"]


def render_all(names=None, icon=True):
    L.ensure_dirs()
    assert os.path.exists(SKY) and os.path.exists(GRID), "run build_textures.py first"
    names = names or ALL
    for n in names:
        if n in SINGLE:
            render_single(n)
        elif n == "theme_dark":
            render_theme(n, tinted=False)
        elif n == "theme_tinted_ocean":
            render_theme(n, tinted=True)
        elif n == "asset_sheet":
            render_asset_sheet()
    if icon:
        render_icon()


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    want_icon = "--icon" in argv or not argv
    names = [a for a in argv if not a.startswith("--")]
    if "--icon-only" in argv:
        render_icon()
    else:
        render_all(names or None, icon=want_icon)
