"""Build Constellate textures: Sky_Dark.png, Sky_Tint.png (4096x2048 equirect) and Floor_Grid.png (2048x2048 RGBA).

Sky_Dark is rendered with Cycles (panoramic equirectangular camera, pure-emission world shader).
Sky_Tint is derived from that render as a normalised luminance map (horizon = 1.0).
Floor_Grid is generated procedurally with numpy and written as straight-alpha PNG.

Run standalone:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python build_textures.py -- [--fallback]
"""
from __future__ import annotations

import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import constellate_lib as L  # noqa: E402

P = L.PALETTE
SKY_W, SKY_H = 4096, 2048
GRID_SIZE = 2048
GRID_METRES = 24.0

SKY_PATH = os.path.join(L.TEXTURES_DIR, "Sky_Dark.png")
TINT_PATH = os.path.join(L.TEXTURES_DIR, "Sky_Tint.png")
GRID_PATH = os.path.join(L.TEXTURES_DIR, "Floor_Grid.png")

NEBULA_HEX = "#1A1F4A"   # low-chroma indigo, OKLCh chroma ~0.09
STAR_HEX = "#DDE3FF"


def _node(nt, type_name, **kw):
    n = nt.nodes.new(type_name)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


def build_sky_world():
    """World shader: vertical gradient + subtle nebula noise + tiny thresholded Voronoi stars."""
    world = bpy.data.worlds.new("SkyWorld")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = _node(nt, "ShaderNodeOutputWorld")
    bg = _node(nt, "ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    coord = _node(nt, "ShaderNodeTexCoord")
    sep = _node(nt, "ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs["Vector"])  # world Generated = view direction

    # --- gradient over elevation: z in [-1,1] -> t in [0,1]
    t = _node(nt, "ShaderNodeMapRange")
    t.inputs["From Min"].default_value = -1.0
    t.inputs["From Max"].default_value = 1.0
    nt.links.new(sep.outputs["Z"], t.inputs["Value"])
    ramp = _node(nt, "ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.interpolation = "EASE"
    cr.elements[0].position = 0.0
    cr.elements[0].color = L.hex_to_linear(P["skyBottom"])
    cr.elements[1].position = 1.0
    cr.elements[1].color = L.hex_to_linear(P["skyTop"])
    e = cr.elements.new(0.47)
    e.color = L.hex_to_linear(P["horizon"])
    e = cr.elements.new(0.56)
    e.color = L.hex_to_linear(P["horizon"])
    e = cr.elements.new(0.80)
    mid = tuple((a + b) / 2 for a, b in zip(L.hex_to_linear(P["horizon"]), L.hex_to_linear(P["skyTop"])))
    e.color = mid
    nt.links.new(t.outputs["Result"], ramp.inputs["Fac"])

    # --- nebula: large-scale noise, low contrast, indigo only, stronger near horizon
    noise = _node(nt, "ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 7.0
    noise.inputs["Roughness"].default_value = 0.58
    noise.inputs["Lacunarity"].default_value = 2.1
    nt.links.new(coord.outputs["Generated"], noise.inputs["Vector"])
    nmap = _node(nt, "ShaderNodeMapRange")       # compress noise 0.35..0.75 -> 0..1
    nmap.inputs["From Min"].default_value = 0.38
    nmap.inputs["From Max"].default_value = 0.78
    nt.links.new(noise.outputs["Fac"], nmap.inputs["Value"])
    npow = _node(nt, "ShaderNodeMath", operation="POWER")
    npow.inputs[1].default_value = 2.2
    nt.links.new(nmap.outputs["Result"], npow.inputs[0])
    # fade nebula away from horizon: 1 - |z|^0.7
    zabs = _node(nt, "ShaderNodeMath", operation="ABSOLUTE")
    nt.links.new(sep.outputs["Z"], zabs.inputs[0])
    zpow = _node(nt, "ShaderNodeMath", operation="POWER")
    zpow.inputs[1].default_value = 0.7
    nt.links.new(zabs.outputs[0], zpow.inputs[0])
    zinv = _node(nt, "ShaderNodeMath", operation="SUBTRACT")
    zinv.inputs[0].default_value = 1.0
    nt.links.new(zpow.outputs[0], zinv.inputs[1])
    nfac = _node(nt, "ShaderNodeMath", operation="MULTIPLY")
    nt.links.new(npow.outputs[0], nfac.inputs[0])
    nt.links.new(zinv.outputs[0], nfac.inputs[1])
    nscale = _node(nt, "ShaderNodeMath", operation="MULTIPLY")
    nscale.inputs[1].default_value = 0.55                   # overall nebula amount
    nt.links.new(nfac.outputs[0], nscale.inputs[0])
    nmix = _node(nt, "ShaderNodeMix", data_type="RGBA", blend_type="MIX")
    nt.links.new(nscale.outputs[0], nmix.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], nmix.inputs[6])
    nmix.inputs[7].default_value = L.hex_to_linear(NEBULA_HEX)

    # --- stars: Voronoi on direction; a cell lights up only if its random colour passes a threshold
    vor = _node(nt, "ShaderNodeTexVoronoi")
    vor.feature = "F1"
    vor.distance = "EUCLIDEAN"
    vor.inputs["Scale"].default_value = 330.0
    vor.inputs["Randomness"].default_value = 1.0
    nt.links.new(coord.outputs["Generated"], vor.inputs["Vector"])
    vsep = _node(nt, "ShaderNodeSeparateColor")
    nt.links.new(vor.outputs["Color"], vsep.inputs["Color"])
    near = _node(nt, "ShaderNodeMath", operation="LESS_THAN")     # distance < radius (in cell units)
    near.inputs[1].default_value = 0.26
    nt.links.new(vor.outputs["Distance"], near.inputs[0])
    sparse = _node(nt, "ShaderNodeMath", operation="GREATER_THAN")  # ~2 % of cells
    sparse.inputs[1].default_value = 0.98
    nt.links.new(vsep.outputs["Red"], sparse.inputs[0])
    star = _node(nt, "ShaderNodeMath", operation="MULTIPLY")
    nt.links.new(near.outputs[0], star.inputs[0])
    nt.links.new(sparse.outputs[0], star.inputs[1])
    bright = _node(nt, "ShaderNodeMapRange")                      # per-star brightness 0.25..1.0
    bright.inputs["To Min"].default_value = 0.25
    bright.inputs["To Max"].default_value = 1.0
    nt.links.new(vsep.outputs["Green"], bright.inputs["Value"])
    sbright = _node(nt, "ShaderNodeMath", operation="MULTIPLY")
    nt.links.new(star.outputs[0], sbright.inputs[0])
    nt.links.new(bright.outputs["Result"], sbright.inputs[1])
    # fewer stars below the horizon (floor side): multiply by smooth step on z
    below = _node(nt, "ShaderNodeMapRange")
    below.inputs["From Min"].default_value = -0.35
    below.inputs["From Max"].default_value = 0.05
    below.inputs["To Min"].default_value = 0.15
    below.inputs["To Max"].default_value = 1.0
    nt.links.new(sep.outputs["Z"], below.inputs["Value"])
    sfinal = _node(nt, "ShaderNodeMath", operation="MULTIPLY")
    nt.links.new(sbright.outputs[0], sfinal.inputs[0])
    nt.links.new(below.outputs["Result"], sfinal.inputs[1])
    scol = _node(nt, "ShaderNodeMix", data_type="RGBA", blend_type="MIX")
    scol.inputs["Factor"].default_value = 1.0
    scol.inputs[6].default_value = (0, 0, 0, 1)
    scol.inputs[7].default_value = L.hex_to_linear(STAR_HEX)
    smul = _node(nt, "ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    smul.inputs["Factor"].default_value = 1.0
    nt.links.new(scol.outputs[2], smul.inputs[6])
    sgray = _node(nt, "ShaderNodeCombineColor")
    nt.links.new(sfinal.outputs[0], sgray.inputs["Red"])
    nt.links.new(sfinal.outputs[0], sgray.inputs["Green"])
    nt.links.new(sfinal.outputs[0], sgray.inputs["Blue"])
    nt.links.new(sgray.outputs["Color"], smul.inputs[7])
    add = _node(nt, "ShaderNodeMix", data_type="RGBA", blend_type="ADD")
    add.inputs["Factor"].default_value = 1.0
    nt.links.new(nmix.outputs[2], add.inputs[6])
    nt.links.new(smul.outputs[2], add.inputs[7])

    nt.links.new(add.outputs[2], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    return world


def render_sky_cycles(path=SKY_PATH, samples=32):
    sc = L.reset_scene()
    L.setup_cycles(sc, samples=samples, denoise=False, filter_size=1.0)
    # NOTE: denoise is OFF on purpose. A pure-emission world has no Monte-Carlo noise (the 32 samples
    # only anti-alias), and OpenImageDenoise would smear/remove the 1-2 px stars.
    sc.cycles.use_adaptive_sampling = False
    sc.world = build_sky_world()
    cam_data = bpy.data.cameras.new("SkyCam")
    cam_data.type = "PANO"
    cam_data.panorama_type = "EQUIRECTANGULAR"
    cam = bpy.data.objects.new("SkyCam", cam_data)
    L.link(cam)
    cam.rotation_euler = (math.pi / 2, 0, 0)  # +Z (up) at the top row of the image
    sc.camera = cam
    t0 = time.time()
    L.render_to(sc, path, SKY_W, SKY_H)
    print(f"[constellate] Sky_Dark rendered in {time.time() - t0:.1f}s -> {os.path.getsize(path)} bytes")
    return path


def render_sky_numpy(path=SKY_PATH):
    """Fallback: same look generated directly with numpy (no Cycles)."""
    rng = np.random.default_rng(7)
    y = np.linspace(1.0, -1.0, SKY_H, dtype=np.float32)[:, None]  # elevation -> z
    z = np.sin(y * math.pi / 2)
    t = (z + 1) / 2
    stops = [(0.0, P["skyBottom"]), (0.47, P["horizon"]), (0.56, P["horizon"]), (1.0, P["skyTop"])]
    img = np.zeros((SKY_H, 1, 3), np.float32)
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= p0) & (t <= p1)
        f = np.clip((t - p0) / max(p1 - p0, 1e-6), 0, 1)
        f = f * f * (3 - 2 * f)
        a = np.array(L.hex_to_linear(c0)[:3]); b = np.array(L.hex_to_linear(c1)[:3])
        img = np.where(m, a * (1 - f) + b * f, img)
    img = np.repeat(img, SKY_W, axis=1)
    # nebula: multi-octave value noise via upsampled random grids
    neb = np.zeros((SKY_H, SKY_W), np.float32)
    for oct_ in range(5):
        g = rng.random((8 << oct_, 16 << oct_)).astype(np.float32)
        ry = np.linspace(0, g.shape[0] - 1, SKY_H); rx = np.linspace(0, g.shape[1] - 1, SKY_W)
        gy = np.clip(ry.astype(int), 0, g.shape[0] - 2); gx = np.clip(rx.astype(int), 0, g.shape[1] - 2)
        fy = (ry - gy)[:, None]; fx = (rx - gx)[None, :]
        v = (g[gy][:, gx] * (1 - fx) + g[gy][:, gx + 1] * fx) * (1 - fy) + (g[gy + 1][:, gx] * (1 - fx) + g[gy + 1][:, gx + 1] * fx) * fy
        neb += v * (0.55 ** oct_)
    neb = (neb / neb.max() - 0.45) / 0.4
    neb = np.clip(neb, 0, 1) ** 2.2 * (1 - np.abs(z) ** 0.7) * 0.55
    img = img * (1 - neb[..., None]) + np.array(L.hex_to_linear(NEBULA_HEX)[:3]) * neb[..., None]
    # stars
    n_stars = 14000
    sy = rng.integers(0, SKY_H, n_stars); sx = rng.integers(0, SKY_W, n_stars)
    sb = rng.random(n_stars) * 0.75 + 0.25
    keep = rng.random(n_stars) < np.where(z[sy, 0] < -0.3, 0.15, 1.0)
    star = np.array(L.hex_to_linear(STAR_HEX)[:3])
    for yy, xx, b in zip(sy[keep], sx[keep], sb[keep]):
        img[yy, xx] += star * b
        if b > 0.7:
            img[yy, (xx + 1) % SKY_W] += star * b * 0.35
    srgb = np.vectorize(L.linear_to_srgb)(np.clip(img, 0, 1)) if False else _lin_to_srgb_np(np.clip(img, 0, 1))
    L.write_png(path, (srgb * 255 + 0.5).astype(np.uint8).tobytes(), SKY_W, SKY_H, 3)
    print(f"[constellate] Sky_Dark generated with numpy fallback -> {os.path.getsize(path)} bytes")
    return path


def _lin_to_srgb_np(x):
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(np.maximum(x, 1e-9), 1 / 2.4) - 0.055)


def _srgb_to_lin_np(x):
    return np.where(x <= 0.04045, x / 12.92, np.power((x + 0.055) / 1.055, 2.4))


def make_sky_tint(src=SKY_PATH, dst=TINT_PATH):
    """Grayscale luminance of Sky_Dark, normalised so the brightest *sky* (99.7th percentile, i.e. the
    nebula-lit horizon band, excluding stars) maps to 1.0. The app multiplies this by the theme's horizon
    colour (HSL(H,0.34,0.17)); stars clip to white."""
    img = bpy.data.images.load(src, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * img.channels, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, img.channels)[::-1, :, :3]  # Blender rows are bottom-up; byte PNG pixels are sRGB-encoded
    lin = _srgb_to_lin_np(px)
    lum = 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]
    # reference = brightest sky region measured on 8x8 block means (stars average out)
    blocks = lum.reshape(h // 8, 8, w // 8, 8).mean(axis=(1, 3))
    ref = float(np.percentile(blocks, 99.5))
    tint = np.clip(lum / max(ref, 1e-6), 0, 1)
    out = (_lin_to_srgb_np(tint) * 255 + 0.5).astype(np.uint8)
    L.write_png(dst, out.tobytes(), w, h, 1)
    bpy.data.images.remove(img)
    print(f"[constellate] Sky_Tint written -> {os.path.getsize(dst)} bytes (reference lum {ref:.4f} -> 1.0)")
    return dst


def make_floor_grid(dst=GRID_PATH, size=GRID_SIZE, metres=GRID_METRES):
    """Transparent RGBA grid: 1 m lines (24 cells), brighter every 4 m, radial alpha falloff, white RGB."""
    ppm = size / metres  # pixels per metre
    c = np.arange(size, dtype=np.float32) + 0.5
    coord_m = c / ppm  # metres along the axis
    # distance in pixels to nearest 1 m line / 4 m line
    d1 = np.abs((coord_m % 1.0) - 0.5)
    d1 = (0.5 - d1) * ppm
    d4 = np.abs((coord_m % 4.0) - 2.0)
    d4 = (2.0 - d4) * ppm

    def line(d, half_w):
        return np.clip(half_w + 0.5 - d, 0.0, 1.0)

    minor_x = line(d1, 1.0)[None, :]; minor_y = line(d1, 1.0)[:, None]
    major_x = line(d4, 1.5)[None, :]; major_y = line(d4, 1.5)[:, None]
    minor = np.maximum(minor_x, minor_y) * 0.42
    major = np.maximum(major_x, major_y) * 1.0
    alpha = np.maximum(minor, major)
    # radial falloff: full inside 45 % of half-size, 0 at the edge (circle inscribed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.sqrt((xx - size / 2 + 0.5) ** 2 + (yy - size / 2 + 0.5) ** 2) / (size / 2)
    f = np.clip((1.0 - r) / 0.55, 0, 1)
    fall = f * f * (3 - 2 * f)
    alpha = np.clip(alpha * fall, 0, 1)
    rgba = np.empty((size, size, 4), np.uint8)
    rgba[..., :3] = 255  # straight (non-premultiplied) white
    rgba[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
    L.write_png(dst, rgba.tobytes(), size, size, 4)
    print(f"[constellate] Floor_Grid written -> {os.path.getsize(dst)} bytes")
    return dst


def build_textures(force_fallback=False):
    L.ensure_dirs()
    used_fallback = False
    if force_fallback:
        render_sky_numpy(); used_fallback = True
    else:
        try:
            render_sky_cycles()
        except Exception as e:  # pragma: no cover
            print("[constellate] Cycles sky render failed, using numpy fallback:", repr(e))
            render_sky_numpy(); used_fallback = True
    make_sky_tint()
    make_floor_grid()
    return {"fallback": used_fallback}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--derived-only" in argv:          # reuse the existing Sky_Dark render
        L.ensure_dirs(); make_sky_tint(); make_floor_grid()
    else:
        build_textures(force_fallback="--fallback" in argv)
