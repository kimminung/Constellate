"""Build the seven Constellate USDZ assets — v2 "observatory instruments" design.

Run standalone:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python build_assets.py -- [AssetName ...]

Design language (Docs/PRD-Design-Constellate.md §9): every asset reads as a precise astronomical instrument —
chamfered ribbon rings instead of plain tori, engraved tick marks, faceted gems, a tiny constellation inside each
orb — in dark, desaturated bodies (environment rule: chroma <= 0.16, L <= 0.30) with light only in the fixed
emissive slots. Material names are unchanged (`Core`, `Band0`…`Band3`, `Shell`, `Accent`, `Glass`, `Base`) and
`Accent` keeps one of the exported accent colours (#6FB6FF / #FFD166 / #FF8FD1 / #5EE1FF), because
`AssetLoader.retintAccent` finds accent materials by name *or* by that colour.

Each `build_*` function authors geometry in Blender Z-up space at an `origin` and returns the created objects.
The same functions are reused by render_assets.py so the renders use exactly the shipped materials.
"""
from __future__ import annotations

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

import constellate_lib as L  # noqa: E402

P = L.PALETTE


def _shift(objs, origin):
    o = Vector(origin)
    for ob in objs:
        ob.location = ob.location + o
    return objs


def _rotate(obj, euler):
    obj.rotation_euler = Euler(euler)
    return obj


# ---------------------------------------------------------------------------- shared pieces
def _armillary_ring(name, radius, width, thickness, mat, rotation=(0, 0, 0), segments=96):
    ring = L.ring_band(name, radius, width, thickness, segments=segments)
    _rotate(ring, rotation)
    return L.assign(ring, mat)


def _constellation(name, radius, count, seed, dot_radius, line_radius, dot_mat, line_mat, chain=True):
    """A small constellation on a sphere: `count` dots, linked as a chain plus one branch (like a star chart)."""
    rnd = random.Random(seed)
    golden = math.pi * (3 - math.sqrt(5))
    pts = []
    for i in range(count):
        y = 1 - (i + 0.5) / count * 2
        r = math.sqrt(max(0.0, 1 - y * y))
        a = golden * i * 2.3 + rnd.uniform(-0.25, 0.25)
        pts.append(Vector((math.cos(a) * r, math.sin(a) * r, y * 0.85)).normalized() * radius)
    bm = bmesh.new()
    for p in pts:
        L.bm_icosphere(bm, p, dot_radius, subdivisions=1)
    dots = L._bm_object(f"{name}_Dots", bm, smooth=True)
    L.assign(dots, dot_mat)
    bm = bmesh.new()
    order = sorted(range(count), key=lambda i: math.atan2(pts[i].y, pts[i].x))
    pairs = list(zip(order, order[1:])) if chain else []
    if count > 4:
        pairs.append((order[1], order[-2]))
    for a, b in pairs:
        L.strut(bm, pts[a], pts[b], line_radius, sides=4)
    lines = L._bm_object(f"{name}_Lines", bm)
    L.assign(lines, line_mat)
    return [dots, lines]


# ---------------------------------------------------------------------------- 1. HostOrb
def build_host_orb(origin=(0, 0, 0), name="HostOrb"):
    """Armillary core: emissive icosphere core, four chamfered armillary rings (equator, two meridians, a 23.4°
    ecliptic) in the band colours, a 72-tick dial on the equator, a nine-star constellation drawn inside, and the
    glass shell. Read through the app's procedural glass + spinning bands, it reads as an instrument, not a bulb."""
    core = L.make_material("Core", base="#FFFFFF", roughness=0.3, emission=P["coreWhite"], strength=4.0)
    glass = L.make_material("Glass", base="#E6E8FF", roughness=0.04, alpha=0.22, transmission=1.0, ior=1.45)
    band_hex = [P["lavender"], P["cyan"], P["pink"], "#FFFFFF"]
    bands = [L.make_material(f"Band{i}", base="#FFFFFF", roughness=0.25, emission=band_hex[i], strength=3.0) for i in range(4)]
    objs = []
    bpy.ops.mesh.primitive_ico_sphere_add(radius=0.054, subdivisions=3)
    c = bpy.context.active_object
    c.name = c.data.name = f"{name}_Core"
    objs.append(L.assign(L.shade_smooth(c), core))
    objs.append(_armillary_ring(f"{name}_Equator", 0.112, 0.0075, 0.0028, bands[0]))
    objs.append(_armillary_ring(f"{name}_MeridianA", 0.117, 0.0062, 0.0024, bands[1], rotation=(math.radians(90), 0, math.radians(18))))
    objs.append(_armillary_ring(f"{name}_MeridianB", 0.117, 0.0062, 0.0024, bands[2], rotation=(math.radians(90), 0, math.radians(108))))
    objs.append(_armillary_ring(f"{name}_Ecliptic", 0.123, 0.0048, 0.0022, bands[3], rotation=(math.radians(23.44), math.radians(8), 0)))
    ticks = L.tick_ring(f"{name}_Dial", 0.1075, 72, 0.0042, 0.0011, 0.0022, major_every=6, major_scale=1.9)
    objs.append(L.assign(ticks, bands[3]))
    objs += _constellation(f"{name}_Sky", 0.092, 9, seed=7, dot_radius=0.0042, line_radius=0.00065, dot_mat=core, line_mat=bands[3])
    objs.append(L.assign(L.add_sphere(f"{name}_Shell", 0.135, segments=48, rings=24), glass))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 2. ClusterOrb
def build_cluster_orb(origin=(0, 0, 0), name="ClusterOrb"):
    """A mini constellation in a glass sphere: a geodesic lattice with beveled struts and joint 'stars' (a few
    lit brighter), two tilted orbit rings and a small core. Up to 120 of these are on screen, so ~5k triangles."""
    glass = L.make_material("Glass", base="#DCE0FF", roughness=0.05, alpha=0.16, transmission=1.0, ior=1.4)
    shell = L.make_material("Shell", base=P["slate"], roughness=0.45, emission=P["slate"], strength=1.3)
    core = L.make_material("Core", base="#FFFFFF", roughness=0.35, emission=P["coreWhite"], strength=4.0)
    objs = []
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=0.158)
    verts = [v.co.copy() for v in tmp.verts]
    edges = [(e.verts[0].co.copy(), e.verts[1].co.copy()) for e in tmp.edges]
    tmp.free()
    bm = bmesh.new()
    for a, b in edges:
        L.strut(bm, a, b, 0.0021, sides=5)
    for v in verts:
        L.bm_icosphere(bm, v, 0.0058, subdivisions=0)
    lattice = L._bm_object(f"{name}_Lattice", bm, smooth=False)
    objs.append(L.assign(lattice, shell))
    rnd = random.Random(11)
    bm = bmesh.new()
    for v in rnd.sample(verts, 7):
        L.bm_icosphere(bm, v * 1.0, 0.0092, subdivisions=1)
    stars = L._bm_object(f"{name}_Stars", bm, smooth=True)
    objs.append(L.assign(stars, core))
    objs.append(_armillary_ring(f"{name}_OrbitA", 0.108, 0.0046, 0.0018, shell, rotation=(math.radians(68), 0, math.radians(20)), segments=48))
    objs.append(_armillary_ring(f"{name}_OrbitB", 0.094, 0.0040, 0.0016, shell, rotation=(math.radians(-38), math.radians(52), 0), segments=48))
    bpy.ops.mesh.primitive_ico_sphere_add(radius=0.03, subdivisions=2)
    c = bpy.context.active_object
    c.name = c.data.name = f"{name}_Core"
    objs.append(L.assign(L.shade_smooth(c), core))
    objs.append(L.assign(L.add_sphere(f"{name}_Shell", 0.18, segments=40, rings=20), glass))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 3. Avatar_Bust
def build_avatar_bust(origin=(0, 0, 0), name="Avatar", accent_hex=None, yaw_deg=0.0):
    """Stylised meeting participant: tapered shoulders with accent piping, a helmet-like head with a wrap-around
    visor (the accent glow reads from any seat), a headset with mic boom (it is a voice app), collar ring and the
    floating name-plate ring 0.05 m above the head. Height 0.45 m, bottom at z = 0.

    Face points to Blender +Y, which the exporter's rotateX(-90) maps to USD/RealityKit **-Z** (entity forward)."""
    accent_hex = accent_hex or P["skyBlue"]
    base = L.make_material("Base", base=P["baseDark"], roughness=0.42, metallic=0.35)
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.3, emission=accent_hex, strength=3.0)
    objs = []
    # Torso: the upper half of a flattened ellipsoid — rounded shoulders falling away to the sides, closed by a
    # flat base so the bust stands on the stage pad.
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=20, radius=1.0)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
    bmesh.ops.scale(bm, vec=(0.172, 0.108, 0.138), verts=bm.verts)
    rim = [e for e in bm.edges if e.is_boundary]
    bmesh.ops.edgeloop_fill(bm, edges=rim)
    torso = L._bm_object(f"{name}_Torso", bm, smooth=True)
    objs.append(L.assign(torso, base))
    # Chest emblem: a small faceted hexagon on the sternum, facing forward (+Y).
    emblem = L.prism_from_outline(f"{name}_Emblem", L.circle_outline(0.016, 6, rotation=30), 0.004, bevel=0.003)
    emblem.rotation_euler = (math.radians(-90 + 32), 0, 0)
    emblem.location = (0, 0.088, 0.078)
    objs.append(L.assign(emblem, accent))
    objs.append(L.assign(L.add_cylinder(f"{name}_Neck", 0.034, 0.075, location=(0, 0, 0.145), vertices=32), base))
    collar = L.ring_band(f"{name}_Collar", 0.046, 0.007, 0.006, segments=48)
    collar.location = (0, 0, 0.122)
    objs.append(L.assign(collar, accent))
    # Head: egg, subdivided.
    head = L.add_sphere(f"{name}_Head", 0.104, location=(0, 0, 0.29), segments=20, rings=12, scale=(1.0, 0.96, 1.12), smooth=False)
    L.apply_transforms([head])
    L.subdivide(head, levels=1)
    L.shade_smooth(head)
    objs.append(L.assign(head, base))
    # Visor: a curved strip around the front of the head at eye height (±78°), following the egg's surface.
    bm = bmesh.new()
    seg, half = 28, math.radians(78)
    rows = [(-0.014, 0.0), (0.014, 0.0)]          # (dz, outward)
    rings = []
    for i in range(seg + 1):
        a = -half + 2 * half * i / seg + math.pi / 2   # centred on +Y
        col = []
        for dz, _ in rows:
            z = 0.300 + dz
            # ellipsoid radius at height z, slightly outside the surface
            k = max(0.0, 1 - ((z - 0.29) / (0.104 * 1.12)) ** 2)
            rx, ry = 0.104 * math.sqrt(k) + 0.003, 0.104 * 0.96 * math.sqrt(k) + 0.003
            for out in (0.0, 0.004):
                col.append(bm.verts.new(((rx + out) * math.cos(a), (ry + out) * math.sin(a), z)))
        rings.append(col)
    for i in range(seg):
        a, b = rings[i], rings[i + 1]
        # columns: [bottom-in, bottom-out, top-in, top-out]
        bm.faces.new((a[1], b[1], b[3], a[3]))   # outer face
        bm.faces.new((a[0], a[2], b[2], b[0]))   # inner face
        bm.faces.new((a[2], a[3], b[3], b[2]))   # top
        bm.faces.new((a[0], b[0], b[1], a[1]))   # bottom
    visor = L._bm_object(f"{name}_Visor", bm, smooth=True)
    objs.append(L.assign(visor, accent))
    # Headset: ear pods with accent rims, a band over the head, a mic boom to the mouth.
    for sx in (-1, 1):
        pod = L.add_cylinder(f"{name}_EarPod{'L' if sx < 0 else 'R'}", 0.03, 0.022, location=(sx * 0.109, 0.0, 0.29), rotation=(0, math.radians(90), 0), vertices=24)
        objs.append(L.assign(pod, base))
        rim = L.ring_band(f"{name}_EarRim{'L' if sx < 0 else 'R'}", 0.028, 0.005, 0.004, segments=32)
        rim.rotation_euler = (0, math.radians(90), 0)
        rim.location = (sx * 0.121, 0.0, 0.29)
        objs.append(L.assign(rim, accent))
    band = L.ring_band(f"{name}_HeadBand", 0.118, 0.008, 0.008, segments=48)
    band.rotation_euler = (math.radians(90), 0, 0)   # ear to ear, over the crown
    band.scale = (1.0, 1.0, 1.0)
    band.location = (0, -0.004, 0.30)
    L.apply_transforms([band])
    # keep only the upper half of the band
    bm = bmesh.new()
    bm.from_mesh(band.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.0], context="VERTS")
    bm.to_mesh(band.data)
    bm.free()
    band.location = (0, -0.004, 0.30)
    objs.append(L.assign(band, base))
    bm = bmesh.new()
    boom = [Vector((-0.118, 0.0, 0.282)), Vector((-0.112, 0.045, 0.262)), Vector((-0.085, 0.085, 0.246)), Vector((-0.045, 0.104, 0.240))]
    for a, b in zip(boom, boom[1:]):
        L.strut(bm, a, b, 0.0032, sides=6)
    boom_obj = L._bm_object(f"{name}_MicBoom", bm, smooth=True)
    objs.append(L.assign(boom_obj, base))
    mic = L.add_sphere(f"{name}_Mic", 0.0075, location=tuple(boom[-1]), segments=12, rings=6)
    objs.append(L.assign(mic, accent))
    # Floating name-plate ring 0.05 above the head top (~0.406).
    plate = L.ring_band(f"{name}_NamePlate", 0.14, 0.006, 0.004, segments=96)
    plate.location = (0, 0, 0.45)
    objs.append(L.assign(plate, accent))
    if yaw_deg:
        rot = Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
        for o in objs:
            o.matrix_world = rot @ o.matrix_world
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 4. Beacon
def build_beacon(origin=(0, 0, 0), name="Beacon"):
    """Summon beacon, 3 m: a hot core beam (Core) inside a warm translucent sheath (Glass), three 'tractor' rings
    shrinking upward, a faceted gem at the top and an engraved floor medallion (concentric rings + 48 ticks).
    Only `Accent` is re-tinted by the app (theme beacon colour); core and sheath keep their warm white."""
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.3, emission=P["amber"], strength=5.0)
    core = L.make_material("Core", base="#FFFFFF", roughness=0.3, emission="#FFF2D4", strength=7.0, alpha=0.92)
    glass = L.make_material("Glass", base="#FFE2A8", roughness=0.1, emission="#FFD166", strength=0.6, alpha=0.16, transmission=1.0)
    base = L.make_material("Base", base=P["baseDark"], roughness=0.5, metallic=0.4)
    objs = []
    objs.append(L.assign(L.add_cylinder(f"{name}_Beam", 0.014, 3.0, location=(0, 0, 1.5), radius_top=0.0035, vertices=24), core))
    objs.append(L.assign(L.add_cylinder(f"{name}_Sheath", 0.068, 2.96, location=(0, 0, 1.49), radius_top=0.016, vertices=32), glass))
    for i, (z, r) in enumerate(((0.55, 0.25), (1.35, 0.175), (2.25, 0.115))):
        ring = L.ring_band(f"{name}_Lift{i}", r, 0.012, 0.006, segments=48, chamfer=False)
        ring.location = (0, 0, z)
        objs.append(L.assign(ring, accent))
    gem = L.prism_from_outline(f"{name}_Gem", L.circle_outline(0.03, 6), 0.012, bevel=0.03)
    gem.location = (0, 0, 3.0)
    objs.append(L.assign(gem, core))
    disc = L.add_cylinder(f"{name}_Medallion", 0.6, 0.012, location=(0, 0, 0.006), vertices=96)
    objs.append(L.assign(disc, base))
    for i, r in enumerate((0.35, 0.55)):
        ring = L.ring_band(f"{name}_Ring{i}", r, 0.012, 0.006, segments=72, chamfer=False)
        ring.location = (0, 0, 0.014)
        objs.append(L.assign(ring, accent))
    ticks = L.tick_ring(f"{name}_Ticks", 0.53, 48, 0.035, 0.006, 0.004, major_every=4, major_scale=1.7, z=0.014)
    objs.append(L.assign(ticks, accent))
    return _shift(objs, origin)


def _brilliant(name, radius, location=(0, 0, 0), facets=8):
    """Round-brilliant-style gem with its axis vertical: table, crown, girdle and a pointed pavilion."""
    bm = bmesh.new()
    girdle = [bm.verts.new((radius * math.cos(2 * math.pi * k / facets), radius * math.sin(2 * math.pi * k / facets), 0.0)) for k in range(facets)]
    table = [bm.verts.new((0.56 * radius * math.cos(2 * math.pi * (k + 0.5) / facets), 0.56 * radius * math.sin(2 * math.pi * (k + 0.5) / facets), 0.36 * radius)) for k in range(facets)]
    culet = bm.verts.new((0, 0, -0.9 * radius))
    for k in range(facets):
        a, b = girdle[k], girdle[(k + 1) % facets]
        t0, tm = table[(k - 1) % facets], table[k]
        bm.faces.new((a, b, tm))            # crown kite halves
        bm.faces.new((a, tm, t0))
        bm.faces.new((b, a, culet))         # pavilion
    bm.faces.new(table)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    gem = L._bm_object(name, bm)
    gem.location = location
    return gem


# ---------------------------------------------------------------------------- 5. ReviewPin
def build_review_pin(origin=(0, 0, 0), name="ReviewPin"):
    """Map pin as a jewel: steel needle (tip at the origin), accent collar, and a faceted octagonal gem head that
    faces forward (−Z in RealityKit), total height 0.08 m."""
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.18, emission=P["pink"], strength=3.0)
    base = L.make_material("Base", base=P["baseDark"], roughness=0.25, metallic=0.85)
    objs = []
    needle = L.add_cone(f"{name}_Needle", 0.0034, 0.042, location=(0, 0, 0.021), rotation=(math.pi, 0, 0), vertices=16)
    objs.append(L.assign(needle, base))
    collar = L.ring_band(f"{name}_Collar", 0.0052, 0.0035, 0.003, segments=24)
    collar.location = (0, 0, 0.0425)
    objs.append(L.assign(collar, accent))
    objs.append(L.assign(L.add_cylinder(f"{name}_Stem", 0.0024, 0.012, location=(0, 0, 0.049), vertices=12), base))
    objs.append(L.assign(_brilliant(f"{name}_Gem", 0.0175, location=(0, 0, 0.0625)), accent))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 6. Stage_Ring
def build_stage_ring(origin=(0, 0, 0), name="Stage", accent_hex=None, seat_radius=1.0):
    """Meeting stage as an astrolabe: a chamfered main band with a glowing inlay, 72 engraved degree ticks
    (long every 30°), six hexagonal seat pads with accent rings, and a glass centre with an eight-ray compass rose."""
    accent_hex = accent_hex or P["skyBlue"]
    shell = L.make_material("Shell", base=P["grid"], roughness=0.45, emission=P["grid"], strength=1.5)
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.4, emission=accent_hex, strength=0.9)
    glass = L.make_material("Glass", base="#DCE0FF", roughness=0.08, alpha=0.2, transmission=1.0)
    base = L.make_material("Base", base=P["baseDark"], roughness=0.5, metallic=0.4)
    objs = []
    band = L.ring_band(f"{name}_Ring", 1.2, 0.06, 0.014, segments=160)
    band.location = (0, 0, 0.012)
    objs.append(L.assign(band, shell))
    inlay = L.ring_band(f"{name}_Inlay", 1.2, 0.011, 0.016, segments=160, chamfer=False)
    inlay.location = (0, 0, 0.013)
    objs.append(L.assign(inlay, accent))
    ticks = L.tick_ring(f"{name}_Ticks", 1.165, 72, 0.028, 0.004, 0.003, major_every=6, major_scale=2.0, z=0.006)
    objs.append(L.assign(ticks, accent))
    for i in range(6):
        a = math.radians(i * 60 + 90)  # seat 0 at +Y (in front of the camera in renders)
        x, y = seat_radius * math.cos(a), seat_radius * math.sin(a)
        pad = L.prism_from_outline(f"{name}_Seat{i}", L.circle_outline(0.12, 6, rotation=30), 0.01)
        pad.location = (x, y, 0.005)
        objs.append(L.assign(pad, base))
        ring = L.ring_band(f"{name}_SeatRing{i}", 0.092, 0.008, 0.004, segments=36, chamfer=False)
        ring.location = (x, y, 0.0115)
        objs.append(L.assign(ring, accent))
    objs.append(L.assign(L.add_disc(f"{name}_Centre", 0.3, location=(0, 0, 0.002), vertices=64), glass))
    bm = bmesh.new()
    for k in range(8):
        a = math.radians(k * 45)
        radial, tangent = Vector((math.cos(a), math.sin(a), 0)), Vector((-math.sin(a), math.cos(a), 0))
        length = 0.26 if k % 2 == 0 else 0.16
        L.box_verts(bm, radial * (0.05 + length / 2) + Vector((0, 0, 0.004)), radial, tangent, Vector((0, 0, 1)), length / 2, 0.0035, 0.0015)
    rose = L._bm_object(f"{name}_Rose", bm)
    objs.append(L.assign(rose, accent))
    return _shift(objs, origin)


def seat_positions(seat_radius=1.0):
    return [(seat_radius * math.cos(math.radians(i * 60 + 90)), seat_radius * math.sin(math.radians(i * 60 + 90)), 0.0) for i in range(6)]


# ---------------------------------------------------------------------------- 7. Pointer_Dart
def build_pointer_dart(origin=(0, 0, 0), name="PointerDart"):
    """Laser-pointer tip: a hexagonal crystal bipyramid 0.05 m long, tip towards Blender +Y (= RealityKit −Z),
    with a thin collar at the waist."""
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.2, emission=P["pointer"], strength=3.0)
    bm = bmesh.new()
    r = 0.0072
    waist = [bm.verts.new((r * math.cos(math.radians(60 * k)), 0.0, r * math.sin(math.radians(60 * k)))) for k in range(6)]
    tip = bm.verts.new((0, 0.036, 0))
    tail = bm.verts.new((0, -0.014, 0))
    for k in range(6):
        a, b = waist[k], waist[(k + 1) % 6]
        bm.faces.new((b, a, tip))
        bm.faces.new((a, b, tail))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    dart = L._bm_object(f"{name}", bm)
    collar = L.ring_band(f"{name}_Collar", 0.0078, 0.0016, 0.0016, segments=18, chamfer=False)
    collar.rotation_euler = (math.radians(90), 0, 0)
    L.apply_transforms([collar])
    merged = L.merge([dart, collar], name)
    return _shift([L.assign(merged, accent)], origin)


BUILDERS = {
    "HostOrb": (build_host_orb, "HostOrb"),
    "ClusterOrb": (build_cluster_orb, "ClusterOrb"),
    "Avatar_Bust": (build_avatar_bust, "Avatar"),
    "Beacon": (build_beacon, "Beacon"),
    "ReviewPin": (build_review_pin, "ReviewPin"),
    "Stage_Ring": (build_stage_ring, "Stage"),
    "Pointer_Dart": (build_pointer_dart, "PointerDart"),
}

# Triangle budgets (Docs/PRD-Design-Constellate.md §9). ClusterOrb is instanced up to 120 times.
BUDGETS = {"HostOrb": 14000, "ClusterOrb": 6500, "Avatar_Bust": 9500, "Beacon": 6000, "ReviewPin": 1200, "Stage_Ring": 9000, "Pointer_Dart": 300}


def build_and_export(names=None):
    L.ensure_dirs()
    report = []
    for key, (fn, root) in BUILDERS.items():
        if names and key not in names:
            continue
        L.reset_scene()
        objs = fn()
        tris = L.tri_count(objs)
        path = os.path.join(L.ASSETS_DIR, f"{key}.usdz")
        L.export_usdz(objs, path, root)
        info = L.verify_usdz(path)
        info["tris"] = tris
        assert tris < BUDGETS.get(key, 20000), f"{key}: {tris} tris exceeds budget {BUDGETS.get(key)}"
        assert info["bytes"] < 2 * 1024 * 1024, f"{key}: file too large"
        ok, problems = L.check_arkit(path)
        info["arkit"] = ok
        report.append(info)
        print(f"[constellate] {key}: {tris} tris, {info['bytes']} bytes, up={info.get('upAxis')}, "
              f"materials={info.get('materials')}, bbox={info.get('bbox_min')}..{info.get('bbox_max')}, arkit={ok if ok is not None else 'n/a'}"
              + ("" if ok in (True, None) else f" {problems[:3]}"))
    return report


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build_and_export(argv or None)
