"""Graph assets for the constellation: node star glyphs + effect sprites (pipeline v2).

Outputs
  Constellate/Resources/Assets3D/NodeStars.usdz     15 prims: `Star_<Role>` ×12, `Star_Folder`, `Star_Module`, `Star_Halo`
  Constellate/Resources/Textures/FX_Glow.png        soft radial glow (flow particles, orb aura, star bloom)     256²
  Constellate/Resources/Textures/FX_Spark.png       hot core + 4 diffraction spikes (focused-flow particles)     256²
  Constellate/Resources/Textures/FX_Ring.png        ripple ring with a fine inner line (beacon / summon wave)   512²
  Constellate/Resources/Textures/FX_Beam.png        vertical light-pillar falloff (beacon pillar)               64×512
  Constellate/Resources/Textures/FX_EdgeRamp.png    along-edge ramp, u = 0 source … 1 target (relation tubes)   256×8
  Constellate/Resources/Textures/FX_CardGlow.png    rounded-rect glow frame behind a code card (selection)      580×424

Run standalone (also part of build_all.py):
  /Applications/Blender.app/Contents/MacOS/Blender --background --python build_graph_assets.py -- [--stars-only | --fx-only] [FX_Name.png …]

Sprites are *rendered* by Cycles: each is an emission plane whose strength is a small field built from shader math
nodes (Gaussian cores, exponential tails, a rounded-rectangle distance field …) and seen by an orthographic camera.
The render is written as linear EXR and converted to a straight-alpha white PNG (`RGB = 255, A = field`) — the
same convention as Floor_Grid.png — so the app tints one texture with any theme or relation colour. What the field
says is exactly what the alpha channel gets (no view transform in between), which keeps the sprites tunable.

Glyphs are flat-shaded crystals ≤ 220 triangles each because the app clones one per code node (up to ~2500).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

import constellate_lib as L  # noqa: E402

P = L.PALETTE
S = 0.05            # glyph half-size: the largest dimension is ≈ 0.1 m (the app rescales per node)
GLYPH_BUDGET = 220  # triangles per glyph

# Card geometry shared with the app (TextureFactory.cardWidth/Height = 512×352, corner radius 22 px).
CARD_W, CARD_H, CARD_R = 1.0, 352 / 512, 22 / 512
CARD_GLOW_MARGIN = 0.08  # glow quad = card + this margin on every side (fraction of card width) → 1.16 × 0.8475

# ============================================================================ glyphs
GLYPHS: dict = {}


def glyph(name, about):
    def deco(fn):
        GLYPHS[name] = (fn, about)
        return fn
    return deco


def _face_front(obj):
    """Flat glyphs are modelled in XY; turn them so their face points at Blender −Y = RealityKit +Z (the card front)."""
    obj.rotation_euler = Euler((math.radians(90), 0, 0))
    L.apply_transforms([obj])
    return obj


def orbit(name, radius, width, thickness, segments):
    """Thin orbit ribbon in the XY plane: only the two flat faces (4 tris per segment) — at glyph scale the side
    walls are sub-pixel, and dropping them halves the cost of every ring."""
    bm = bmesh.new()
    w, t = width / 2, thickness / 2
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new(((radius + dr) * ca, (radius + dr) * sa, dz)) for dr, dz in ((w, t), (-w, t), (-w, -t), (w, -t))])
    for i in range(segments):
        r0, r1 = rings[i], rings[(i + 1) % segments]
        bm.faces.new((r0[0], r1[0], r1[1], r0[1]))   # top, normal +Z
        bm.faces.new((r0[3], r0[2], r1[2], r1[3]))   # bottom, normal −Z
    return L._bm_object(name, bm)


@glyph("Star_App", "8-point compass star: the entry point")
def _app(name):
    return _face_front(L.prism_from_outline(name, L.star_outline(8, S, 0.42 * S), 0.16 * S, bevel=0.24 * S))


@glyph("Star_View", "rounded window frame: UI")
def _view(name):
    outer = L.rounded_rect_outline(2 * S, 1.45 * S, 0.3 * S, seg=3)
    inner = L.rounded_rect_outline(1.36 * S, 0.84 * S, 0.12 * S, seg=3)
    title_bar = L.prism_from_outline(name + "_Bar", [(-0.68 * S, 0.3 * S), (0.68 * S, 0.3 * S), (0.68 * S, 0.42 * S), (-0.68 * S, 0.42 * S)], 0.16 * S)
    return _face_front(L.merge([L.frame_from_outlines(name, outer, inner, 0.22 * S), title_bar], name))


@glyph("Star_Controller", "hexagonal dial with a hub: coordinates views")
def _controller(name):
    ring = L.frame_from_outlines(name + "_Ring", L.circle_outline(S, 6, 30), L.circle_outline(0.58 * S, 6, 30), 0.22 * S)
    hub = L.prism_from_outline(name + "_Hub", L.circle_outline(0.26 * S, 6), 0.2 * S, bevel=0.12 * S)
    bm = bmesh.new()
    for k in range(3):  # three spokes hub → ring
        a = math.radians(90 + 120 * k)
        d = Vector((math.cos(a), math.sin(a), 0))
        L.box_verts(bm, d * (0.42 * S), d, Vector((-d.y, d.x, 0)), Vector((0, 0, 1)), 0.17 * S, 0.06 * S, 0.07 * S)
    spokes = L._bm_object(name + "_Spokes", bm)
    return _face_front(L.merge([ring, hub, spokes], name))


@glyph("Star_ViewModel", "elongated diamond: between view and model")
def _viewmodel(name):
    bm = bmesh.new()
    w = [bm.verts.new((0.62 * S * math.cos(math.radians(45 + 90 * k)), 0.62 * S * math.sin(math.radians(45 + 90 * k)), 0)) for k in range(4)]
    top, bot = bm.verts.new((0, 0, S)), bm.verts.new((0, 0, -S))
    for k in range(4):
        a, b = w[k], w[(k + 1) % 4]
        bm.faces.new((a, b, top))
        bm.faces.new((b, a, bot))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return L._bm_object(name, bm)  # tip along Blender Z = RealityKit +Y


@glyph("Star_Model", "chamfered data block")
def _model(name):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.32 * S)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.16 * S, segments=1, affect="EDGES", profile=0.5)
    o = L._bm_object(name, bm)
    o.rotation_euler = Euler((math.radians(35.26), 0, math.radians(45)))  # stand on a corner: reads as a 3-D block
    L.apply_transforms([o])
    return o


@glyph("Star_Service", "six-tooth gear: does work")
def _service(name):
    return _face_front(L.prism_from_outline(name, L.gear_outline(6, S, 0.76 * S), 0.26 * S, bevel=0.16 * S))


@glyph("Star_Extension", "plus sign: adds to a type")
def _extension(name):
    bm = bmesh.new()
    t = 0.2 * S
    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    L.box_verts(bm, (0, 0, 0), X, Y, Z, S, t, t)
    L.box_verts(bm, (0, 0, 0), X, Y, Z, t, t, S)
    return L._bm_object(name, bm)


@glyph("Star_Test", "tetrahedron: a check")
def _test(name):
    bm = bmesh.new()
    a = 0.66 * S
    vs = [bm.verts.new(v) for v in ((a, a, a), (a, -a, -a), (-a, a, -a), (-a, -a, a))]
    for f in ((0, 1, 2), (0, 3, 1), (0, 2, 3), (1, 3, 2)):
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = L._bm_object(name, bm)
    # one face down, apex up — a little pyramid
    o.rotation_euler = Euler((math.radians(-54.74), 0, math.radians(45)))
    L.apply_transforms([o])
    return o


@glyph("Star_Doc", "page with a folded corner")
def _doc(name):
    w, h, f = 0.72 * S, 0.95 * S, 0.34 * S
    page = L.prism_from_outline(name + "_Page", [(-w, -h), (w, -h), (w, h - f), (w - f, h), (-w, h)], 0.16 * S)
    bm = bmesh.new()
    z = 0.09 * S
    tri = [bm.verts.new(v) for v in ((w - f, h, z), (w - f, h - f, z), (w, h - f, z))]
    bm.faces.new(tri)
    for k in range(3):  # three text lines embossed on the page
        y = 0.38 * S - k * 0.32 * S
        short = 0.1 * S if k == 2 else 0.0
        L.box_verts(bm, (-0.08 * S - short, y, z), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), 0.46 * S - short, 0.05 * S, 0.02 * S)
    marks = L._bm_object(name + "_Marks", bm)
    return _face_front(L.merge([page, marks], name))


@glyph("Star_Config", "hex nut: settings")
def _config(name):
    return _face_front(L.frame_from_outlines(name, L.circle_outline(S, 6), L.circle_outline(0.46 * S, 6), 0.42 * S))


@glyph("Star_Script", "chevron prompt: runs")
def _script(name):
    t = 0.36 * S
    chevron = L.prism_from_outline(name + "_Chevron", [(-0.85 * S, S), (-0.85 * S + t, S), (0.5 * S, 0), (-0.85 * S + t, -S),
                                                       (-0.85 * S, -S), (0.5 * S - t * 1.15, 0)], 0.26 * S)
    cursor = L.prism_from_outline(name + "_Cursor", [(0.36 * S, -S), (S, -S), (S, -0.72 * S), (0.36 * S, -0.72 * S)], 0.26 * S)
    return _face_front(L.merge([chevron, cursor], name))


@glyph("Star_Other", "icosahedron: anything else")
def _other(name):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.9 * S)
    return L._bm_object(name, bm)


@glyph("Star_Folder", "four-point sparkle with an orbit: folder hub")
def _folder(name):
    star = L.prism_from_outline(name + "_Star", L.star_outline(4, S, 0.24 * S), 0.1 * S, bevel=0.2 * S)
    ring = orbit(name + "_Orbit", 0.7 * S, 0.08 * S, 0.03 * S, 24)
    return _face_front(L.merge([star, ring], name))


@glyph("Star_Module", "six-point star in a double orbit: the project root")
def _module(name):
    star = L.prism_from_outline(name + "_Star", L.star_outline(6, 0.82 * S, 0.36 * S), 0.12 * S, bevel=0.2 * S)
    r1 = orbit(name + "_Orbit1", 0.95 * S, 0.06 * S, 0.03 * S, 24)
    r2 = orbit(name + "_Orbit2", 0.64 * S, 0.045 * S, 0.03 * S, 18)
    r2.rotation_euler = Euler((math.radians(62), 0, math.radians(20)))  # tilted inner orbit = a tiny armillary
    L.apply_transforms([r2])
    return _face_front(L.merge([star, r1, r2], name))


def _halo(name):
    """Thin ring drawn around a glyph that sits on a dependency cycle (tinted #FF5F6D by the app)."""
    ring = orbit(name, 1.3 * S, 0.07 * S, 0.02 * S, 28)
    ticks = bmesh.new()
    for k in range(4):  # four short ticks: reads as "loop / warning" even when tiny
        a = math.radians(45 + 90 * k)
        d = Vector((math.cos(a), math.sin(a), 0))
        L.box_verts(ticks, d * (1.3 * S), d, Vector((-d.y, d.x, 0)), Vector((0, 0, 1)), 0.16 * S, 0.035 * S, 0.012 * S)
    return _face_front(L.merge([ring, L._bm_object(name + "_Ticks", ticks)], name))


def build_node_stars(origin=(0, 0, 0), spacing=0.16, colors=None, with_halo=True):
    """All glyphs in a row (x = index · spacing). The app clones a prim by name and drops its translation."""
    accent = L.make_material("Accent", base="#FFFFFF", roughness=0.3, emission=P["pointer"], strength=2.4)
    objs = []
    names = list(GLYPHS.items())
    for i, (gname, (fn, _)) in enumerate(names):
        o = fn(gname)
        o.name = gname
        o.data.name = gname
        if colors:
            c = colors[i % len(colors)]
            L.assign(o, L.make_material(f"Star{i}", base=c, roughness=0.3, emission=c, strength=2.4))
        else:
            L.assign(o, accent)
        o.location = Vector(origin) + Vector((i * spacing, 0, 0))
        objs.append(o)
    if with_halo:
        h = _halo("Star_Halo")
        h.data.name = "Star_Halo"
        mat = (L.make_material("Glass", base="#FFFFFF", roughness=0.3, emission="#FF5F6D", strength=2.0) if not colors
               else L.make_material("HaloRender", base="#FF5F6D", roughness=0.3, emission="#FF5F6D", strength=2.4))
        L.assign(h, mat)
        h.location = Vector(origin) + Vector((len(names) * spacing, 0, 0))
        objs.append(h)
    return objs


def export_node_stars():
    L.reset_scene()
    objs = build_node_stars()
    tris = {o.name: L.tri_count([o]) for o in objs}
    over = {k: v for k, v in tris.items() if v > GLYPH_BUDGET}
    assert not over, f"glyphs over the {GLYPH_BUDGET}-triangle budget: {over}"
    path = os.path.join(L.ASSETS_DIR, "NodeStars.usdz")
    L.export_usdz(objs, path, "NodeStars")
    info = L.verify_usdz(path)
    ok, problems = L.check_arkit(path)
    print(f"[constellate] NodeStars: {len(objs)} prims, {sum(tris.values())} tris (max {max(tris.values())}), {info['bytes']} bytes, "
          f"materials={info.get('materials')}, arkit={ok if ok is not None else 'n/a'}" + ("" if ok in (True, None) else f" {problems[:3]}"))
    for k, v in tris.items():
        print(f"    {k:<16} {v:>4} tris  {GLYPHS.get(k, (None, 'cycle halo'))[1]}")
    return path


# ============================================================================ FX sprites
def _sprite_scene(width, height, plane_w, plane_h, field_fn, name):
    """Black world, ortho camera framing a plane_w × plane_h emission plane whose strength is `field_fn(F, x, y)`
    with x, y in plane units (centre = 0). Returns the scene."""
    sc = L.reset_scene()
    L.setup_cycles(sc, samples=16, denoise=False, filter_size=1.0, view_transform="Standard")
    sc.cycles.use_adaptive_sampling = False
    sc.render.use_compositing = False
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0, 0, 0, 1)
    bg.inputs["Strength"].default_value = 0.0
    sc.world = world
    cam = L.add_camera("SpriteCam", location=(0, 0, 5), target=(0, 0, 0), ortho_scale=max(plane_w, plane_h))
    cam.rotation_euler = Euler((0, 0, 0))  # look straight down −Z, +Y up in the image
    sc.render.resolution_x, sc.render.resolution_y = width, height
    sc.render.resolution_percentage = 100

    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
    plane = bpy.context.active_object
    plane.name = name
    plane.scale = (plane_w, plane_h, 1)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], sep.inputs["Vector"])
    F = L.Field(nt)
    x = F.mul(sep.outputs["X"], plane_w)   # object space is −0.5…0.5 → plane units
    y = F.mul(sep.outputs["Y"], plane_h)
    nt.links.new(field_fn(F, x, y), em.inputs["Strength"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    plane.data.materials.append(mat)
    return sc


def _render_alpha_png(sc, path):
    """Render to linear EXR (no view transform), store the field as alpha of a white PNG."""
    tmp = path + ".tmp.exr"
    s = sc.render.image_settings
    s.file_format = "OPEN_EXR"
    s.color_mode = "RGB"
    s.color_depth = "32"
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * img.channels, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, img.channels)[::-1, :, :3]      # Blender rows are bottom-up
    a = np.clip(px.max(axis=2), 0.0, 1.0)
    rgba = np.empty((h, w, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(a * 255).astype(np.uint8)
    L.write_png(path, rgba.tobytes(), w, h, 4)
    bpy.data.images.remove(img)
    os.remove(tmp)
    edge = max(rgba[0, :, 3].max(), rgba[-1, :, 3].max(), rgba[:, 0, 3].max(), rgba[:, -1, 3].max())
    print(f"[constellate] {os.path.basename(path):<17} {w}x{h}  {os.path.getsize(path):>7} bytes  peak α {rgba[..., 3].max()}  border α {edge}")
    return path


def fx_glow(F, x, y):
    """Gaussian core + long exponential tail, windowed to zero at the sprite edge (no square cut-off)."""
    r = F.length(x, y)
    core = F.gauss(r, 0.13)
    halo = F.tail(r, 0.1)
    return F.mul(F.add(F.mul(core, 0.85), F.mul(halo, 0.3)), F.smooth_edge(r, 0.36, 0.5))


def fx_spark(F, x, y):
    """Point-like core with four long thin spikes (+ four faint diagonal ones) — a telescope's diffraction star."""
    r = F.length(x, y)
    core = F.add(F.mul(F.gauss(r, 0.035), 1.4), F.mul(F.tail(r, 0.06), 0.35))
    spike_h = F.mul(F.gauss(y, 0.007), F.tail(x, 0.13))
    spike_v = F.mul(F.gauss(x, 0.007), F.tail(y, 0.13))
    u = F.mul(F.add(x, y), 0.70710678)
    v = F.mul(F.sub(x, y), 0.70710678)
    diag = F.add(F.mul(F.gauss(v, 0.005), F.tail(u, 0.055)), F.mul(F.gauss(u, 0.005), F.tail(v, 0.055)))
    total = F.add(F.add(core, F.mul(F.add(spike_h, spike_v), 0.9)), F.mul(diag, 0.35))
    return F.mul(total, F.smooth_edge(r, 0.4, 0.5))


def fx_ring(F, x, y):
    """Main soft ring, a fine inner line and a faint fill: an expanding ripple reads as a wave, not a hoop."""
    r = F.length(x, y)
    ring = F.gauss(F.sub(r, 0.4), 0.028)
    line = F.gauss(F.sub(r, 0.33), 0.0045)
    fill = F.mul(F.smooth_edge(r, 0.3, 0.39), 0.07)
    return F.mul(F.add(F.add(ring, F.mul(line, 0.55)), fill), F.smooth_edge(r, 0.46, 0.5))


def fx_beam(F, x, y):
    """Bright core with a soft sheath across, strongest at the base and fading up; y ∈ [−0.5, 0.5] bottom → top."""
    up = F.add(y, 0.5)                                         # 0 at the base … 1 at the top
    core = F.gauss(x, 0.006)
    sheath = F.mul(F.tail(x, 0.016), 0.35)
    across = F.mul(F.add(core, sheath), F.smooth_edge(F.abs(x), 0.045, 0.0625))
    fade = F.pow(F.max(F.sub(1.0, up), 0.0), 1.4)
    base = F.add(1.0, F.mul(F.gauss(up, 0.06), 0.6))           # small flare where the pillar meets the floor
    return F.mul(F.mul(across, fade), base)


def fx_edge_ramp(F, x, y):
    """u = 0 (source) … 1 (target): dim tail, rising body, brightest just before the arrowhead, short fade under it."""
    u = F.add(x, 0.5)
    rise = F.pow(F.min(F.div(u, 0.9), 1.0), 1.6)
    drop = F.mul(F.max(F.sub(u, 0.9), 0.0), 3.0)
    return F.max(F.sub(F.add(0.28, F.mul(rise, 0.72)), drop), 0.0)


def fx_card_glow(F, x, y):
    """Distance field of the card outline: crisp rim just outside the edge + soft outer glow + faint inner wash.
    The card itself covers the inside, so only the rim and the outer glow are seen in the app."""
    d = F.rounded_rect_sdf(x, y, CARD_W / 2, CARD_H / 2, CARD_R)
    outside = F.max(d, 0.0)
    rim = F.gauss(F.sub(d, 0.006), 0.0045)
    glow = F.mul(F.tail(outside, 0.022), 0.55)
    wash = F.mul(F.tail(F.min(d, 0.0), 0.03), 0.12)
    window = F.smooth_edge(outside, CARD_GLOW_MARGIN * 0.55, CARD_GLOW_MARGIN * 0.98)
    return F.mul(F.add(F.add(rim, glow), wash), window)


_GW, _GH = CARD_W + 2 * CARD_GLOW_MARGIN, CARD_H + 2 * CARD_GLOW_MARGIN
FX = {
    #  file               size        plane (units)   field
    "FX_Glow.png":     ((256, 256), (1.0, 1.0), fx_glow),
    "FX_Spark.png":    ((256, 256), (1.0, 1.0), fx_spark),
    "FX_Ring.png":     ((512, 512), (1.0, 1.0), fx_ring),
    "FX_Beam.png":     ((64, 512), (0.125, 1.0), fx_beam),
    "FX_EdgeRamp.png": ((256, 8), (1.0, 1.0 / 32), fx_edge_ramp),
    "FX_CardGlow.png": ((580, int(round(580 * _GH / _GW))), (_GW, _GH), fx_card_glow),
}


def build_fx(names=None):
    L.ensure_dirs()
    out = []
    for fname, ((w, h), (pw, ph), fn) in FX.items():
        if names and fname not in names:
            continue
        sc = _sprite_scene(w, h, pw, ph, fn, fname[:-4])
        out.append(_render_alpha_png(sc, os.path.join(L.TEXTURES_DIR, fname)))
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    L.ensure_dirs()
    if "--fx-only" not in argv:
        export_node_stars()
    if "--stars-only" not in argv:
        build_fx([a for a in argv if a.endswith(".png")] or None)
