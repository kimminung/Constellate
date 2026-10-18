"""Platform app icons rendered in Blender (Cycles/Metal, 128 samples, OIDN, AgX, bloom).

One shared scene -> several outputs from the SAME orthographic camera:
  iOS/iPadOS  AppIcon-1024.png (light), AppIcon-1024-dark.png, AppIcon-1024-tinted.png (grayscale, transparent)
  macOS       mac_1024.png (rounded-rect 3-D tile, 10 % margin, transparent) -> sips to mac_16..mac_1024
  visionOS    AppIcon.solidimagestack Back/Middle/Front .png (Back opaque, Middle+Front transparent)
  previews    Blender/renders/icon_macos.png, Blender/renders/icon_sheet.png (1600x600)

Scene units: 1.0 = icon width (1024 px). Camera looks along +Y; x right, z up, y depth.
Collections: Back (backdrop, floor hint, relation lines, stars), Middle (cards, cluster orbs, rings),
Front (host orb), MacTile (rounded tile), Lights.

Run:  /Applications/Blender.app/Contents/MacOS/Blender --background --python render_icons.py -- [--sheet-only]
"""
from __future__ import annotations

import math
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import constellate_lib as L  # noqa: E402
import build_assets as A  # noqa: E402

P = L.PALETTE
SAMPLES = 128
SIZE = 1024
STACK_DIR = os.path.join(L.ROOT, "Constellate", "Assets.xcassets", "AppIcon.solidimagestack")
TMP = os.path.join(L.RENDERS_DIR, "_icon_tmp")

IOS_LIGHT = os.path.join(L.ICON_DIR, "AppIcon-1024.png")
IOS_DARK = os.path.join(L.ICON_DIR, "AppIcon-1024-dark.png")
IOS_TINTED = os.path.join(L.ICON_DIR, "AppIcon-1024-tinted.png")
MAC_1024 = os.path.join(L.ICON_DIR, "mac_1024.png")
MAC_PREVIEW = os.path.join(L.RENDERS_DIR, "icon_macos.png")
SHEET = os.path.join(L.RENDERS_DIR, "icon_sheet.png")
VISION = {k: os.path.join(STACK_DIR, f"{k}.solidimagestacklayer", "Content.imageset", f"{k}.png") for k in ("Back", "Middle", "Front")}

GLINT_HEX = [P["cyan"], P["amber"], P["pink"], P["cyan"], P["amber"], P["pink"], P["lavender"]]


# ---------------------------------------------------------------------------- helpers
def coll(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def move_to(objs, name):
    c = coll(name)
    for o in objs:
        for uc in list(o.users_collection):
            uc.objects.unlink(o)
        c.objects.link(o)
    return objs


def set_visible(name, visible):
    coll(name).hide_render = not visible


def radial_material(name, centre_hex, mid_hex, edge_hex="#000000", scale=1.35, coat=0.0, roughness=0.3, scale_vec=None):
    """Emissive radial gradient (object space) with optional glossy coat (for the mac tile face)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = 0.08
    bsdf.inputs["Specular IOR Level"].default_value = 0.5 if coat else 0.0
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapn = nt.nodes.new("ShaderNodeMapping")
    mapn.inputs["Scale"].default_value = scale_vec or (scale, scale, scale)
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.interpolation = "EASE"
    cr.elements[0].position = 0.0
    cr.elements[0].color = L.hex_to_linear(edge_hex)
    cr.elements[1].position = 1.0
    cr.elements[1].color = L.hex_to_linear(centre_hex)
    e = cr.elements.new(0.5)
    e.color = L.hex_to_linear(mid_hex)
    nt.links.new(coord.outputs["Object"], mapn.inputs["Vector"])
    nt.links.new(mapn.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def rounded_rect_mesh(name, side, radius, segments=24, location=(0, 0, 0)):
    """Rounded square in the XZ plane facing -Y (the camera). Analytic polygon -> no operator surprises."""
    h = side / 2
    pts = []
    for cx, cz, a0 in ((h - radius, h - radius, 0), (-(h - radius), h - radius, 90), (-(h - radius), -(h - radius), 180), (h - radius, -(h - radius), 270)):
        for i in range(segments + 1):
            a = math.radians(a0 + 90 * i / segments)
            pts.append((cx + radius * math.cos(a), 0.0, cz + radius * math.sin(a)))
    faces = [tuple(reversed(range(len(pts))))]  # normal towards -Y
    return L.add_mesh(name, pts, faces, location=location)


def rect_frame(name, w, h, thickness, location, rotation, mat):
    """Rectangular outline (plane + wireframe modifier) used as a card border glint."""
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=location)
    f = bpy.context.active_object
    f.name = name
    f.scale = (w, h, 1.0)
    f.rotation_euler = rotation
    L.apply_transforms([f])
    L.wireframe(f, thickness=thickness)
    return L.assign(f, mat)


# ---------------------------------------------------------------------------- scene
def build_scene(dark=False):
    L.GLASS_TRANSMISSION = True
    sc = L.reset_scene()
    L.setup_cycles(sc, samples=SAMPLES, denoise=True, view_transform="AgX")
    sc.render.image_settings.color_mode = "RGBA"
    sc.cycles.transparent_max_bounces = 24
    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    sc.world = world
    rng = random.Random(42)
    glint_gain = 1.4 if dark else 1.0

    # ---- Back: backdrop plane (radial space), floor hint, stars, relation lines
    bpy.ops.mesh.primitive_plane_add(size=3.0, location=(0, 1.6, 0), rotation=(math.pi / 2, 0, 0))
    back = bpy.context.active_object
    back.name = "Backdrop"
    if dark:
        back.data.materials.append(radial_material("BackdropDark", "#0B0D1E", "#030409", "#000000", scale=1.7))
    else:
        back.data.materials.append(radial_material("Backdrop", "#303A8A", "#121845", "#030410", scale=1.45))
    move_to([back], "Back")

    # floor hint: faint lavender elliptical glow low in the frame (an ortho front camera can't see a real floor)
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 1.55, -0.30), rotation=(math.pi / 2, 0, 0))
    fh = bpy.context.active_object
    fh.name = "FloorHint"
    fh.scale = (0.9, 0.16, 1.0)
    L.apply_transforms([fh])
    # gradient must reach 0 at the plane's edge (local x +-0.45, z +-0.08) -> anisotropic mapping scale
    fh_mat = radial_material("FloorHint", "#2A3150", "#141833", "#000000", scale_vec=(2.3, 1.0, 13.0))
    fh_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.45
    fh_mat.surface_render_method = "BLENDED"
    # make the plane additive-ish: mix with transparent by the gradient
    nt = fh_mat.node_tree
    ramp = [n for n in nt.nodes if n.type == "VALTORGB"][0]
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    bsdf = nt.nodes["Principled BSDF"]
    grad = [n for n in nt.nodes if n.type == "TEX_GRADIENT"][0]
    nt.links.new(grad.outputs["Fac"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(bsdf.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    fh.data.materials.append(fh_mat)
    move_to([fh], "Back")

    # stars: tiny emissive spheres just in front of the backdrop
    star_mat = L.make_material("Star", base="#FFFFFF", emission="#DDE3FF", strength=12.0 * glint_gain)
    inner, outer = [], []
    for i in range(110):
        x, z = rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5)
        if math.hypot(x, z) < 0.24:  # keep the orb area clean
            continue
        r = rng.choice([0.0011, 0.0013, 0.0016, 0.0022])
        s = L.add_sphere(f"Star{i}", r, location=(x, 1.5 - rng.uniform(0, 0.1), z), segments=8, rings=6)
        L.assign(s, star_mat)
        (inner if (abs(x) < 0.39 and abs(z) < 0.39) else outer).append(s)
    move_to(inner, "Back")
    move_to(outer, "BackOuter")

    # ---- Middle: code cards with border glints, cluster orbs, orbit rings
    card_mat = L.make_material("CardBase", base="#0E1220", roughness=0.35)
    card_mat.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.7
    cards_spec = [  # (x, z, depth y, yaw, pitch, w, h)
        (-0.33, 0.27, 0.12, 0.35, 0.10, 0.125, 0.085),
        (0.34, 0.30, 0.18, -0.30, 0.05, 0.105, 0.072),
        (0.37, -0.05, 0.05, -0.45, -0.08, 0.120, 0.080),
        (-0.37, -0.10, 0.08, 0.40, -0.05, 0.110, 0.074),
        (0.20, -0.34, 0.14, -0.20, -0.18, 0.115, 0.078),
        (-0.17, -0.35, 0.10, 0.25, -0.15, 0.100, 0.068),
        (0.02, 0.38, 0.20, 0.05, 0.18, 0.095, 0.064),
    ]
    middle, centres = [], []
    for i, (x, z, y, yaw, pitch, w, h) in enumerate(cards_spec):
        rot = (math.pi / 2 + pitch, 0.0, yaw)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z))
        c = bpy.context.active_object
        c.name = f"Card{i}"
        c.scale = (w, h, 0.006)
        c.rotation_euler = rot
        L.apply_transforms([c])
        L.bevel(c, width=0.004, segments=3)
        L.shade_smooth(c)
        L.assign(c, card_mat)
        glint = L.make_material(f"Glint{i}", base="#FFFFFF", emission=GLINT_HEX[i], strength=2.6 * glint_gain)
        glint["glint"] = True
        # frame sits 1 mm in front of the card face (card local -Z after the X rotation == towards camera)
        n = Vector((0, -1, 0))
        n.rotate(c.rotation_euler)
        fr = rect_frame(f"Frame{i}", w * 0.94, h * 0.90, 0.0035, Vector((x, y, z)) + n * 0.0045, rot, glint)
        # two faint "code lines" on the card face
        for k in range(2):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=Vector((x, y, z)) + n * 0.0045)
            ln = bpy.context.active_object
            ln.name = f"Line{i}_{k}"
            ln.scale = (w * (0.55 - 0.18 * k), 0.004, 0.001)
            ln.rotation_euler = rot
            L.apply_transforms([ln])
            off = Vector((-(w * 0.12 + 0.012 * k), 0, (0.014 if k == 0 else -0.004)))
            off.rotate(c.rotation_euler)
            ln.location = ln.location + off
            L.assign(ln, L.make_material(f"LineMat{i}_{k}", base="#F4F6FB", emission="#F4F6FB", strength=0.9))
            middle.append(ln)
        middle += [c, fr]
        centres.append(Vector((x, y, z)))

    # relation lines (Back): faint cylinders between neighbouring cards, slightly behind them
    rel_mat = L.make_material("Relation", base=P["slate"], emission=P["slate"], strength=0.7)
    rels = []
    pairs = [(0, 6), (6, 1), (1, 2), (2, 4), (4, 5), (5, 3), (3, 0), (0, 1), (3, 5)]
    for a, b in pairs[:8]:
        pa, pb = centres[a] + Vector((0, 0.05, 0)), centres[b] + Vector((0, 0.05, 0))
        mid = (pa + pb) / 2
        d = pb - pa
        bpy.ops.mesh.primitive_cylinder_add(radius=0.0013, depth=d.length, vertices=8, location=mid)
        cyl = bpy.context.active_object
        cyl.name = f"Rel{a}{b}"
        cyl.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        L.assign(cyl, rel_mat)
        rels.append(cyl)
    move_to(rels, "Back")

    # cluster orbs (scaled 0.35 -> r 0.063)
    for i, pos in enumerate([(-0.30, 0.30, 0.03), (0.30, 0.40, -0.24)]):
        objs = A.build_cluster_orb(origin=(0, 0, 0), name=f"Cluster{i}")
        holder = L.add_empty(f"ClusterHolder{i}", location=pos, scale=0.35)
        for o in objs:
            o.parent = holder
        middle += objs + [holder]

    # orbit rings
    ring_mat = L.make_material("Orbit", base="#FFFFFF", emission=P["lavender"], strength=0.9)
    r1 = L.add_torus("Orbit0", 0.31, 0.0016, location=(0, 0.1, 0), rotation=(math.radians(78), 0, math.radians(-18)), major_segments=160, minor_segments=6)
    r2 = L.add_torus("Orbit1", 0.40, 0.0012, location=(0, 0.12, 0), rotation=(math.radians(100), 0, math.radians(22)), major_segments=200, minor_segments=6)
    L.assign(r1, ring_mat)
    ring_mat2 = L.make_material("Orbit2", base="#FFFFFF", emission=P["cyan"], strength=0.5)
    L.assign(r2, ring_mat2)
    middle += [r1, r2]
    move_to(middle, "Middle")

    # ---- Front: host orb, scaled 1.5 (shell r 0.2 -> 40 % of the icon width)
    orb = A.build_host_orb(origin=(0, 0, 0))
    oh = L.add_empty("OrbHolder", location=(0, 0, 0), scale=1.5)
    for o in orb:
        o.parent = oh
        # icon-only tweak: tame the core so the four bands stay readable at icon size
        for m in o.data.materials:
            if m.name.startswith("Core"):
                m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.6
    move_to(orb + [oh], "Front")

    # ---- MacTile: rounded-rect glass tile behind the content (hidden except for the macOS render)
    tile = rounded_rect_mesh("MacTile", 0.824, 0.824 * 0.224, location=(0, 0.26, 0))
    solid = tile.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.06
    solid.offset = -1.0  # extrude away from the camera (+Y)
    solid.use_even_offset = True
    L.apply_modifier(tile, solid)
    bv = tile.modifiers.new("Bevel", "BEVEL")
    bv.width = 0.010
    bv.segments = 4
    bv.limit_method = "ANGLE"
    bv.angle_limit = math.radians(40)
    L.apply_modifier(tile, bv)
    L.shade_smooth(tile)
    tile_mat = radial_material("TileFace", "#262D66", "#0C0F24", "#05060F", scale=1.25, coat=1.0, roughness=0.18)
    tile.data.materials.append(tile_mat)
    move_to([tile], "MacTile")

    # ---- Lights (always on)
    lights = [
        L.add_area_light("Key", (0.9, -1.2, 1.1), "#FFFFFF", energy=90, size=1.2, target=(0, 0, 0)),
        L.add_area_light("Fill", (-1.2, -0.8, -0.2), P["lavender"], energy=30, size=1.6, target=(0, 0, 0)),
        L.add_area_light("RimTL", (-0.9, -0.3, 1.2), "#DDE3FF", energy=45, size=0.4, target=(0, 0.26, 0)),
        L.add_area_light("RimBR", (0.9, -0.3, -1.1), P["cyan"], energy=25, size=0.4, target=(0, 0.26, 0)),
    ]
    move_to(lights, "Lights")

    cam = L.add_camera(location=(0, -4.0, 0), target=(0, 0, 0), lens=50)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.0
    cam.data.clip_start = 0.1
    cam.data.clip_end = 20
    return sc


def add_icon_glare(scene, strength=0.45, threshold=1.0, size=8):
    """Bloom that also writes its luminance into alpha, so glow survives in transparent layers."""
    try:
        ng = bpy.data.node_groups.new("IconComp", "CompositorNodeTree")
        ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = ng.nodes.new("CompositorNodeRLayers")
        rl.scene = scene
        glare = ng.nodes.new("CompositorNodeGlare")
        glare.inputs["Type"].default_value = "Bloom"
        glare.inputs["Quality"].default_value = "High"
        glare.inputs["Threshold"].default_value = threshold
        glare.inputs["Strength"].default_value = strength
        glare.inputs["Size"].default_value = size
        glare.inputs["Smoothness"].default_value = 0.2
        ng.links.new(rl.outputs["Image"], glare.inputs["Image"])
        bw = ng.nodes.new("CompositorNodeRGBToBW")
        ng.links.new(glare.outputs["Glare"], bw.inputs["Image"])
        out = ng.nodes.new("NodeGroupOutput")
        try:
            # glow alpha = clamp((bw(glare) - floor) * gain): the floor kills the wide low-level haze
            sub = ng.nodes.new("ShaderNodeMath")
            sub.operation = "SUBTRACT"
            sub.inputs[1].default_value = 0.03
            ng.links.new(bw.outputs[0], sub.inputs[0])
            gain = ng.nodes.new("ShaderNodeMath")
            gain.operation = "MULTIPLY"
            gain.inputs[1].default_value = 1.6
            gain.use_clamp = True
            ng.links.new(sub.outputs[0], gain.inputs[0])
            mx = ng.nodes.new("ShaderNodeMath")
            mx.operation = "MAXIMUM"
            ng.links.new(rl.outputs["Alpha"], mx.inputs[0])
            ng.links.new(gain.outputs[0], mx.inputs[1])
            clamp = ng.nodes.new("ShaderNodeMath")
            clamp.operation = "MINIMUM"
            clamp.inputs[1].default_value = 1.0
            ng.links.new(mx.outputs[0], clamp.inputs[0])
            sa = ng.nodes.new("CompositorNodeSetAlpha")
            sa.inputs["Type"].default_value = "Replace Alpha"
            ng.links.new(glare.outputs["Image"], sa.inputs["Image"])
            ng.links.new(clamp.outputs[0], sa.inputs["Alpha"])
            ng.links.new(sa.outputs["Image"], out.inputs[0])
            mode = "math-max"
        except Exception as e:  # fallback: alpha-over the glow (alpha = bw(glare)) under the image
            print("[constellate] icon glare: Math node unavailable, using AlphaOver chain:", e)
            sa = ng.nodes.new("CompositorNodeSetAlpha")
            sa.inputs["Type"].default_value = "Replace Alpha"
            ng.links.new(glare.outputs["Glare"], sa.inputs["Image"])
            ng.links.new(bw.outputs[0], sa.inputs["Alpha"])
            ao = ng.nodes.new("CompositorNodeAlphaOver")
            ng.links.new(sa.outputs["Image"], ao.inputs["Background"])
            ng.links.new(rl.outputs["Image"], ao.inputs["Foreground"])
            ng.links.new(ao.outputs["Image"], out.inputs[0])
            mode = "alpha-over"
        scene.compositing_node_group = ng
        scene.render.use_compositing = True
        return mode
    except Exception as e:
        print("[constellate] icon glare unavailable:", e)
        scene.render.use_compositing = False
        return None


# ---------------------------------------------------------------------------- image post-processing
def read_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * img.channels, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, img.channels)[::-1].copy()  # top row first; byte PNG values are as stored (sRGB, straight)
    bpy.data.images.remove(img)
    if px.shape[2] == 3:
        px = np.concatenate([px, np.ones((h, w, 1), np.float32)], axis=2)
    return px


def write_rgba(path, px):
    """Straight-alpha RGBA PNG; fully transparent pixels get RGB 0 so naive viewers/resamplers don't fringe."""
    px = np.clip(px, 0, 1).copy()
    px[..., :3] *= (px[..., 3:4] > 0.004)
    L.write_png(path, (px * 255 + 0.5).astype(np.uint8).tobytes(), px.shape[1], px.shape[0], 4)


def clean_transparent(path):
    """Re-write a Blender-rendered RGBA PNG through write_rgba (zero RGB under alpha ~0)."""
    write_rgba(path, read_png(path))


def rounded_mask(size, inner, radius):
    """Anti-aliased rounded-square mask (inner px square centred in size px canvas)."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) + 0.5
    cx = cy = size / 2
    hx = np.abs(xx - cx) - (inner / 2 - radius)
    hy = np.abs(yy - cy) - (inner / 2 - radius)
    d = np.sqrt(np.maximum(hx, 0) ** 2 + np.maximum(hy, 0) ** 2) + np.minimum(np.maximum(hx, hy), 0) - radius
    return np.clip(0.5 - d, 0, 1)


def circle_mask(size, diameter):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) + 0.5
    d = np.sqrt((xx - size / 2) ** 2 + (yy - size / 2) ** 2) - diameter / 2
    return np.clip(0.5 - d, 0, 1)


def to_tinted(src, dst):
    """Apple 'tinted' appearance: grayscale content on transparent background."""
    px = read_png(src)
    lin = np.where(px[..., :3] <= 0.04045, px[..., :3] / 12.92, ((px[..., :3] + 0.055) / 1.055) ** 2.4)
    lum = 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]
    lum = np.clip(lum * 1.25, 0, 1)
    g = np.where(lum <= 0.0031308, lum * 12.92, 1.055 * np.power(np.maximum(lum, 1e-9), 1 / 2.4) - 0.055)
    out = np.stack([g, g, g, px[..., 3]], axis=-1)
    write_rgba(dst, out)


# ---------------------------------------------------------------------------- renders
def render(sc, path, transparent, visible, w=SIZE, h=SIZE):
    for name in ("Back", "BackOuter", "Middle", "Front", "MacTile"):
        set_visible(name, name in visible)
    sc.render.film_transparent = transparent
    sc.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    t0 = time.time()
    size = L.render_to(sc, path, w, h)
    print(f"[constellate] icon render {os.path.relpath(path, L.ROOT)}: {size} bytes in {time.time() - t0:.1f}s")
    return path


def render_all_icons():
    L.ensure_dirs()
    os.makedirs(TMP, exist_ok=True)
    for k in VISION:
        os.makedirs(os.path.dirname(VISION[k]), exist_ok=True)

    # --- light scene: iOS light, tinted source, macOS tile, visionOS layers
    sc = build_scene(dark=False)
    mode = add_icon_glare(sc)
    print("[constellate] icon glare mode:", mode)
    render(sc, IOS_LIGHT, False, {"Back", "BackOuter", "Middle", "Front"})
    tinted_src = os.path.join(TMP, "tinted_src.png")
    # tinted source: same content on a transparent background (backdrop + floor hint hidden)
    bpy.data.objects["Backdrop"].hide_render = True
    bpy.data.objects["FloorHint"].hide_render = True
    render(sc, tinted_src, True, {"Back", "BackOuter", "Middle", "Front"})
    to_tinted(tinted_src, IOS_TINTED)
    bpy.data.objects["Backdrop"].hide_render = False
    bpy.data.objects["FloorHint"].hide_render = False
    # macOS tile: backdrop hidden, tile visible, outer stars hidden; then clip to the rounded rect
    bpy.data.objects["Backdrop"].hide_render = True
    mac_raw = os.path.join(TMP, "mac_raw.png")
    render(sc, mac_raw, True, {"Back", "Middle", "Front", "MacTile"})
    px = read_png(mac_raw)
    px[..., 3] = np.minimum(px[..., 3], rounded_mask(SIZE, 824, 824 * 0.224))
    write_rgba(MAC_1024, px)
    write_rgba(MAC_PREVIEW, px)
    bpy.data.objects["Backdrop"].hide_render = False
    # visionOS layers (same camera)
    render(sc, VISION["Back"], False, {"Back", "BackOuter"})
    render(sc, VISION["Middle"], True, {"Middle"})
    render(sc, VISION["Front"], True, {"Front"})
    clean_transparent(VISION["Middle"])
    clean_transparent(VISION["Front"])

    # --- dark scene
    sc = build_scene(dark=True)
    add_icon_glare(sc, strength=0.5)
    render(sc, IOS_DARK, False, {"Back", "BackOuter", "Middle", "Front"})


# ---------------------------------------------------------------------------- preview sheet
def render_sheet():
    """1600x600 sheet: iOS light / dark / tinted, macOS tile, visionOS parallax composite."""
    os.makedirs(TMP, exist_ok=True)
    # visionOS layers cropped to the circle, Back opaque
    circ = circle_mask(SIZE, 1000)
    layer_paths = {}
    for k in ("Back", "Middle", "Front"):
        px = read_png(VISION[k])
        px[..., 3] = np.minimum(px[..., 3], circ)
        layer_paths[k] = os.path.join(TMP, f"vision_{k}.png")
        write_rgba(layer_paths[k], px)

    sc = L.reset_scene()
    L.setup_cycles(sc, samples=48, denoise=True, view_transform="Standard")
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("SheetWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = L.hex_to_linear("#101320")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = world

    def image_plane(name, path, x, z, size, y=0.0, bg_hex=None, bg_size=None):
        if bg_hex:
            bpy.ops.mesh.primitive_plane_add(size=1.0, location=(x, y + 0.05, z), rotation=(math.pi / 2, 0, 0))
            b = bpy.context.active_object
            b.scale = (bg_size or size * 1.18, bg_size or size * 1.18, 1)
            L.apply_transforms([b])
            bm = L.make_material(f"{name}_bg", base=bg_hex, emission=bg_hex, strength=1.0)
            b.data.materials.append(bm)
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(x, y, z), rotation=(math.pi / 2, 0, 0))
        p = bpy.context.active_object
        p.name = name
        p.scale = (size, size, 1)
        L.apply_transforms([p])
        mat = bpy.data.materials.new(f"{name}_mat")
        mat.use_nodes = True
        mat.surface_render_method = "BLENDED"
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 1.0
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(path, check_existing=True)
        tex.image.alpha_mode = "STRAIGHT"
        tex.interpolation = "Cubic"
        nt.links.new(tex.outputs["Color"], em.inputs["Color"])
        nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        p.data.materials.append(mat)
        return p

    label_mat = L.make_material("Label", base="#F4F6FB", emission="#F4F6FB", strength=1.0)
    sub_mat = L.make_material("Sub", base="#8A93A6", emission="#8A93A6", strength=1.0)
    xs = [-6.4, -3.2, 0.0, 3.2, 6.4]
    S = 2.7  # 270 px icons on a 320 px pitch
    image_plane("ios_light", IOS_LIGHT, xs[0], 0.4, S)
    image_plane("ios_dark", IOS_DARK, xs[1], 0.4, S)
    image_plane("ios_tinted", IOS_TINTED, xs[2], 0.4, S, bg_hex="#3A3D4A", bg_size=S * 1.1)
    image_plane("mac", MAC_1024, xs[3], 0.4, S * 1.08, bg_hex="#D9DBE3", bg_size=S * 1.1)
    # visionOS: three layers offset to show parallax, Front nearest the camera
    image_plane("vision_back", layer_paths["Back"], xs[4] - 0.16, 0.4 - 0.09, S * 0.92, y=0.0)
    image_plane("vision_middle", layer_paths["Middle"], xs[4], 0.4, S * 0.92, y=-0.1)
    image_plane("vision_front", layer_paths["Front"], xs[4] + 0.16, 0.4 + 0.09, S * 0.92, y=-0.2)
    for x, title, sub in zip(xs, ["iOS / iPadOS", "iOS dark", "iOS tinted", "macOS", "visionOS"],
                             ["light appearance", "luminosity: dark", "luminosity: tinted (grayscale)", "rounded tile, 10 % margin", "Front / Middle / Back layers"]):
        t = L.add_text(f"T_{title}", title, size=0.34, location=(x, -0.2, -1.95), rotation=(math.pi / 2, 0, 0))
        L.assign(t, label_mat)
        s = L.add_text(f"S_{title}", sub, size=0.21, location=(x, -0.2, -2.40), rotation=(math.pi / 2, 0, 0))
        L.assign(s, sub_mat)
    cam = L.add_camera(location=(0, -10, 0), target=(0, 0, 0), lens=50)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 16.0
    t0 = time.time()
    size = L.render_to(sc, SHEET, 1600, 600)
    print(f"[constellate] icon render {os.path.relpath(SHEET, L.ROOT)}: {size} bytes in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--sheet-only" not in argv:
        render_all_icons()
    render_sheet()
