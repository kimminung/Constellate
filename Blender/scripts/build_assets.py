"""Build the seven Constellate USDZ assets.

Run standalone:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python build_assets.py -- [AssetName ...]

Each `build_*` function authors geometry in Blender Z-up space at an `origin` and returns the
list of created objects. The same functions are reused by render_assets.py so the renders use
exactly the materials that ship in the USDZ files.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import constellate_lib as L  # noqa: E402

P = L.PALETTE


def _shift(objs, origin):
    o = Vector(origin)
    for ob in objs:
        ob.location = ob.location + o
    return objs


# ---------------------------------------------------------------------------- 1. HostOrb
def build_host_orb(origin=(0, 0, 0), name="HostOrb"):
    core = L.make_material("Core", base="#FFFFFF", roughness=0.35, emission=P["coreWhite"], strength=4.0)
    glass = L.make_material("Glass", base="#E6E8FF", roughness=0.05, alpha=0.25, transmission=1.0, ior=1.45)
    band_hex = [P["lavender"], P["cyan"], P["pink"], "#FFFFFF"]
    objs = []
    objs.append(L.assign(L.add_sphere(f"{name}_Core", 0.085, segments=48, rings=24), core))
    tilts = [  # (major radius, euler rotation) – four different tilts
        (0.110, (math.radians(72), 0, math.radians(10))),
        (0.118, (math.radians(-55), math.radians(30), math.radians(70))),
        (0.125, (math.radians(20), math.radians(-65), math.radians(130))),
        (0.130, (math.radians(95), math.radians(60), math.radians(-40))),
    ]
    for i, (maj, rot) in enumerate(tilts):
        band = L.make_material(f"Band{i}", base="#FFFFFF", roughness=0.3, emission=band_hex[i], strength=3.0)
        t = L.add_torus(f"{name}_Band{i}", maj, 0.004, rotation=rot, major_segments=96, minor_segments=8)
        objs.append(L.assign(t, band))
    objs.append(L.assign(L.add_sphere(f"{name}_Shell", 0.135, segments=64, rings=32), glass))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 2. ClusterOrb
def build_cluster_orb(origin=(0, 0, 0), name="ClusterOrb"):
    glass = L.make_material("Glass", base="#DCE0FF", roughness=0.06, alpha=0.18, transmission=1.0, ior=1.4)
    shell = L.make_material("Shell", base=P["slate"], roughness=0.5, emission=P["slate"], strength=1.2)
    core = L.make_material("Core", base="#FFFFFF", roughness=0.35, emission=P["coreWhite"], strength=4.0)
    objs = []
    wire = L.add_icosphere(f"{name}_Lattice", 0.16, subdivisions=2)
    L.wireframe(wire, thickness=0.003)
    objs.append(L.assign(wire, shell))
    objs.append(L.assign(L.add_sphere(f"{name}_Core", 0.03, segments=32, rings=16), core))
    objs.append(L.assign(L.add_sphere(f"{name}_Shell", 0.18, segments=64, rings=32), glass))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 3. Avatar_Bust
def build_avatar_bust(origin=(0, 0, 0), name="Avatar", accent_hex=None, yaw_deg=0.0):
    """Body 0.40 m + name-plate ring 0.05 m above the head = 0.45 m total.

    Face points to Blender +Y, which the exporter's rotateX(-90) maps to USD/RealityKit **-Z**
    (entity forward), so `look(at:)` makes the avatar face its target."""
    accent_hex = accent_hex or P["skyBlue"]
    base = L.make_material("Base", base=P["baseDark"], roughness=0.8)
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.3, emission=accent_hex, strength=3.0)
    objs = []
    # shoulders: rounded slab 0.34 x 0.17 x 0.10
    sh = L.add_cube(f"{name}_Shoulders", size=(0.34, 0.17, 0.10), location=(0, 0, 0.05))
    L.apply_transforms([sh])
    L.bevel(sh, width=0.04, segments=6)
    L.shade_smooth(sh)
    objs.append(L.assign(sh, base))
    # neck
    objs.append(L.assign(L.add_cylinder(f"{name}_Neck", 0.035, 0.08, location=(0, 0, 0.13), vertices=32), base))
    # collar ring
    objs.append(L.assign(L.add_torus(f"{name}_Collar", 0.048, 0.005, location=(0, 0, 0.118), major_segments=64, minor_segments=8), accent))
    # head: low-poly sphere, slightly elongated, subdivision 2
    head = L.add_sphere(f"{name}_Head", 0.105, location=(0, 0, 0.285), segments=16, rings=10, scale=(1.0, 0.95, 1.12), smooth=False)
    L.apply_transforms([head])
    L.subdivide(head, levels=2)
    L.shade_smooth(head)
    objs.append(L.assign(head, base))
    # eyes: two small emissive dots on the face (front = +Y in Blender -> -Z in USD)
    rx, ry, rz = 0.105, 0.105 * 0.95, 0.105 * 1.12
    for sx in (-1, 1):
        ex, ez = sx * 0.036, 0.300
        ny = ry * math.sqrt(max(0.0, 1 - (ex / rx) ** 2 - ((ez - 0.285) / rz) ** 2))
        eye = L.add_sphere(f"{name}_Eye{'L' if sx < 0 else 'R'}", 0.009, location=(ex, ny * 1.015, ez), segments=16, rings=8)
        objs.append(L.assign(eye, accent))
    # floating name-plate ring 0.05 above head top (0.4025)
    objs.append(L.assign(L.add_torus(f"{name}_NamePlate", 0.14, 0.004, location=(0, 0, 0.45), major_segments=96, minor_segments=8), accent))
    if yaw_deg:
        for o in objs:
            o.rotation_euler = (o.rotation_euler.x, o.rotation_euler.y, o.rotation_euler.z + math.radians(yaw_deg))
            o.location = Vector((o.location.x * math.cos(math.radians(yaw_deg)) - o.location.y * math.sin(math.radians(yaw_deg)),
                                 o.location.x * math.sin(math.radians(yaw_deg)) + o.location.y * math.cos(math.radians(yaw_deg)),
                                 o.location.z))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 4. Beacon
def build_beacon(origin=(0, 0, 0), name="Beacon"):
    # one shared `Accent` (alpha 0.6) for pillar + rings so the material name stays fixed
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.3, emission=P["amber"], strength=5.0, alpha=0.6)
    glass = L.make_material("Glass", base="#DCE0FF", roughness=0.1, alpha=0.15, transmission=1.0)
    objs = []
    objs.append(L.assign(L.add_cylinder(f"{name}_Pillar", 0.05, 3.0, location=(0, 0, 1.5), radius_top=0.015, vertices=48), accent))
    objs.append(L.assign(L.add_torus(f"{name}_RingInner", 0.35, 0.006, location=(0, 0, 0.006), major_segments=96, minor_segments=8), accent))
    objs.append(L.assign(L.add_torus(f"{name}_RingOuter", 0.55, 0.006, location=(0, 0, 0.006), major_segments=128, minor_segments=8), accent))
    objs.append(L.assign(L.add_disc(f"{name}_Base", 0.6, location=(0, 0, 0.001), vertices=96), glass))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 5. ReviewPin
def build_review_pin(origin=(0, 0, 0), name="ReviewPin"):
    """Needle tip at origin, total height 0.08 m."""
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.3, emission=P["pink"], strength=3.0)
    base = L.make_material("Base", base=P["baseDark"], roughness=0.8)
    objs = []
    needle = L.add_cone(f"{name}_Needle", 0.004, 0.038, location=(0, 0, 0.019), rotation=(math.pi, 0, 0), vertices=24)
    objs.append(L.assign(needle, base))
    objs.append(L.assign(L.add_sphere(f"{name}_Head", 0.025, location=(0, 0, 0.055), segments=32, rings=16), accent))
    return _shift(objs, origin)


# ---------------------------------------------------------------------------- 6. Stage_Ring
def build_stage_ring(origin=(0, 0, 0), name="Stage", accent_hex=None, seat_radius=1.0):
    accent_hex = accent_hex or P["skyBlue"]
    shell = L.make_material("Shell", base=P["grid"], roughness=0.5, emission=P["grid"], strength=1.5)
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.4, emission=accent_hex, strength=0.8)
    glass = L.make_material("Glass", base="#DCE0FF", roughness=0.1, alpha=0.2, transmission=1.0)
    objs = []
    objs.append(L.assign(L.add_torus(f"{name}_Ring", 1.2, 0.02, location=(0, 0, 0.02), major_segments=160, minor_segments=10), shell))
    for i in range(6):
        a = math.radians(i * 60 + 90)  # seat 0 at -Y (front)
        x, y = seat_radius * math.cos(a), seat_radius * math.sin(a)
        objs.append(L.assign(L.add_disc(f"{name}_Seat{i}", 0.12, location=(x, y, 0.002), vertices=32), accent))
    objs.append(L.assign(L.add_disc(f"{name}_Centre", 0.3, location=(0, 0, 0.002), vertices=64), glass))
    return _shift(objs, origin)


def seat_positions(seat_radius=1.0):
    return [(seat_radius * math.cos(math.radians(i * 60 + 90)), seat_radius * math.sin(math.radians(i * 60 + 90)), 0.0) for i in range(6)]


# ---------------------------------------------------------------------------- 7. Pointer_Dart
def build_pointer_dart(origin=(0, 0, 0), name="PointerDart"):
    """Elongated octahedron 0.05 m long, tip towards Blender +Y (= USD/RealityKit -Z forward)."""
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.25, emission=P["pointer"], strength=3.0)
    r = 0.007
    verts = [(r, 0, 0), (0, 0, r), (-r, 0, 0), (0, 0, -r), (0, 0.036, 0), (0, -0.014, 0)]
    faces = []
    for i in range(4):
        a, b = i, (i + 1) % 4
        faces.append((b, 4, a))   # tip (+Y)
        faces.append((a, 5, b))   # tail (-Y)
    dart = L.add_mesh(f"{name}", verts, faces)
    return _shift([L.assign(dart, accent)], origin)


BUILDERS = {
    "HostOrb": (build_host_orb, "HostOrb"),
    "ClusterOrb": (build_cluster_orb, "ClusterOrb"),
    "Avatar_Bust": (build_avatar_bust, "Avatar"),
    "Beacon": (build_beacon, "Beacon"),
    "ReviewPin": (build_review_pin, "ReviewPin"),
    "Stage_Ring": (build_stage_ring, "Stage"),
    "Pointer_Dart": (build_pointer_dart, "PointerDart"),
}


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
        assert tris < 20000, f"{key}: {tris} tris exceeds budget"
        assert info["bytes"] < 2 * 1024 * 1024, f"{key}: file too large"
        report.append(info)
        print(f"[constellate] {key}: {tris} tris, {info['bytes']} bytes, up={info.get('upAxis')}, "
              f"materials={info.get('materials')}, bbox={info.get('bbox_min')}..{info.get('bbox_max')}")
    return report


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build_and_export(argv or None)
