"""Build Constellate environment textures: Sky_Dark.png, Sky_Tint.png (4096x2048 equirect), Floor_Grid.png (2048² RGBA).

Sky_Dark is rendered with Cycles (panoramic equirectangular camera, pure-emission world shader): smooth horizon
haze, a Milky Way band with a bulge in front of the viewer and dark dust rifts, two low-chroma nebula layers and
four star magnitude classes with temperature tints (see `build_sky_world`).
Sky_Tint is derived from that render as a normalised luminance map (brightest sky = 1.0) for tinted themes.
Floor_Grid is an "astrolabe" whose rings sit exactly under the layout's depth shells (see `make_floor_grid`),
generated with numpy and written as straight-alpha PNG.

Run standalone:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python build_textures.py -- [--fallback] [--sky-only | --floor-only]
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


def _mix_hex(a, b, t):
    ca, cb = L.hex_to_srgb(a), L.hex_to_srgb(b)
    return "#%02X%02X%02X" % tuple(int(round((x + (y - x) * t) * 255)) for x, y in zip(ca, cb))


def _galaxy_frame():
    """Milky Way geometry (Blender Z-up world directions). The bulge sits in front of the viewer (Blender +Y =
    RealityKit −Z, the image centre column) 18° above the horizon; the band crosses the sky tilted 58°, so from
    the meeting floor it rises from the left horizon, arcs over the front and sinks behind on the right."""
    from mathutils import Vector
    el = math.radians(18)
    c = Vector((0.0, math.cos(el), math.sin(el)))                 # bulge direction
    up_perp = Vector((0.0, -math.sin(el), math.cos(el)))          # "up" within the plane perpendicular to c
    tilt = math.radians(58)
    t = (Vector((1.0, 0.0, 0.0)) * math.cos(tilt) + up_perp * math.sin(tilt)).normalized()
    n = c.cross(t).normalized()                                   # band normal
    return tuple(c), tuple(n)


def _star_layer(F, D, scale, density, sigma, mag, mag_pow, halo=0.0, halo_scale=0.1, band=None, band_boost=0.0, offset=None):
    """One magnitude class of stars: a Voronoi cell lights up when its random R channel passes a threshold
    (`density` = fraction of cells, raised inside the Milky Way by `band_boost`), with a Gaussian profile of
    `sigma` cell units, a power-law brightness (most stars faint) and a black-body-ish tint from the B channel."""
    vec = F.vadd(D, offset) if offset else D
    dist, col = F.voronoi(vec, scale)
    r, g, b = F.separate(col)
    thr = 1.0 - density
    if band is not None and band_boost > 0:
        thr = F.sub(thr, F.mul(band, band_boost))
    present = F.gt(r, thr)
    brightness = F.add(mag[0], F.mul(mag[1] - mag[0], F.pow(g, mag_pow)))
    profile = F.gauss(dist, sigma)
    if halo > 0:
        profile = F.add(profile, F.mul(F.tail(dist, halo_scale), halo))
    tint = F.ramp(b, [(0.0, "#A9C1FF"), (0.3, "#DCE6FF"), (0.55, "#FFFFFF"), (0.82, "#FFF1DC"), (1.0, "#FFD3A8")])
    return F.vscale(tint, F.mul(F.mul(present, brightness), profile))


def build_sky_world():
    """World shader, all in one Field expression graph:
      gradient (smooth horizon, no flat band) + horizon haze in the grid colour
      + Milky Way (diffuse band, brighter bulge, dark dust rifts, clumpy star clouds)
      + two low-chroma nebula layers (indigo, plum)
      + three star magnitude classes (faint field / mid / bright with halo), denser inside the band
    Environment rules (PRD-Design §4): sky chroma stays low and OKLab L ≤ 0.30 everywhere except the stars."""
    world = bpy.data.worlds.new("SkyWorld")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    coord = nt.nodes.new("ShaderNodeTexCoord")
    F = L.Field(nt)
    D = F.normalize(coord.outputs["Generated"])                   # world Generated = view direction
    _, _, z = F.separate(D)

    # -- gradient over elevation: soft peak at the horizon instead of the old flat 0.47–0.56 band
    t = F.mul(F.add(z, 1.0), 0.5)
    base = F.ramp(t, [
        (0.0, P["skyBottom"]),
        (0.40, _mix_hex(P["skyBottom"], P["horizon"], 0.55)),
        (0.505, P["horizon"]),
        (0.60, _mix_hex(P["horizon"], P["skyTop"], 0.45)),
        (0.78, _mix_hex(P["horizon"], P["skyTop"], 0.8)),
        (1.0, P["skyTop"]),
    ], interpolation="B_SPLINE")
    haze = F.add(F.mul(F.gauss(z, 0.1), 0.38), F.mul(F.gauss(z, 0.32), 0.2))       # wide, soft: no drawn horizon line
    color = F.vadd(base, F.vscale(F.rgb(P["grid"]), F.mul(haze, 0.32)))

    above = F.add(0.12, F.mul(F.smoothstep(z, -0.3, 0.02), 0.88))    # dim everything below the horizon (floor side)

    # -- Milky Way
    c_dir, n_dir = _galaxy_frame()
    b = F.dot(D, n_dir)                                           # signed distance from the galactic plane
    toward = F.max(F.dot(D, c_dir), 0.0)
    bulge = F.pow(toward, 5.0)
    band = F.gauss(b, 0.2)
    core = F.gauss(b, 0.075)
    clumps = F.add(0.55, F.mul(F.noise(D, 7.0, detail=6.0, roughness=0.6), 0.9))
    # dust rifts: a filamentary noise thresholded hard, strongest on the mid-plane (the Great Rift look)
    dust = F.smoothstep(F.noise(F.vadd(D, (3.1, -1.7, 0.4)), 6.5, detail=10.0, roughness=0.66, distortion=0.45), 0.5, 0.62)
    rift = F.mul(dust, F.gauss(F.add(b, 0.015), 0.085))
    glow = F.mul(F.mul(F.add(F.mul(band, 0.55), F.mul(core, 0.5)), F.add(0.5, F.mul(bulge, 1.1))), clumps)
    glow = F.mul(F.mul(glow, F.sub(1.0, F.mul(rift, 0.9))), above)
    color = F.vadd(color, F.vscale(F.rgb("#6F6BA6"), F.mul(glow, 0.03)))

    # -- nebulae: low-chroma indigo + plum, mostly along the band
    near_band = F.add(0.3, F.mul(F.gauss(b, 0.45), 0.7))
    neb1 = F.pow(F.smoothstep(F.noise(D, 1.7, detail=8.0, roughness=0.6, distortion=0.4), 0.47, 0.78), 1.6)
    neb2 = F.pow(F.smoothstep(F.noise(F.vadd(D, (-5.3, 2.2, 7.9)), 3.2, detail=6.0, roughness=0.55, distortion=0.3), 0.55, 0.8), 1.8)
    color = F.vadd(color, F.vscale(F.rgb(NEBULA_HEX), F.mul(F.mul(neb1, near_band), F.mul(above, 0.55))))
    color = F.vadd(color, F.vscale(F.rgb("#2A1A3C"), F.mul(F.mul(neb2, near_band), F.mul(above, 0.35))))

    # -- stars: faint field / mid / bright (halo); denser in the band, sparse below the horizon
    starband = F.mul(F.add(band, F.mul(bulge, 0.6)), F.sub(1.0, F.mul(rift, 0.7)))
    s1 = _star_layer(F, D, 520.0, 0.010, 0.16, (0.10, 0.55), 2.2, band=starband, band_boost=0.045)
    s2 = _star_layer(F, D, 210.0, 0.010, 0.13, (0.35, 1.3), 2.6, band=starband, band_boost=0.02, offset=(11.0, 3.0, -7.0))
    s3 = _star_layer(F, D, 68.0, 0.009, 0.085, (1.4, 5.0), 3.0, halo=0.05, halo_scale=0.075, offset=(-4.0, 9.0, 2.0))
    # unresolved star clouds: a very fine, faint layer that only exists inside the band (gives it grain)
    s0 = _star_layer(F, D, 950.0, 0.0, 0.2, (0.05, 0.3), 1.5, band=starband, band_boost=0.16, offset=(2.0, -6.0, 5.0))
    stars = F.vadd(F.vadd(F.vadd(s0, s1), s2), s3)
    color = F.vadd(color, F.vscale(stars, above))

    nt.links.new(color, bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    return world


def render_sky_cycles(path=SKY_PATH, samples=12):
    sc = L.reset_scene()
    L.setup_cycles(sc, samples=samples, denoise=False, filter_size=1.0)
    # NOTE: denoise is OFF on purpose. A pure-emission world has no Monte-Carlo noise (the samples only
    # anti-alias, and the Gaussian star profiles need few), and OpenImageDenoise would smear the 1-2 px stars.
    # 12 samples ≈ 15 min on a 2-core CPU, seconds on Apple-silicon Metal.
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


# Floor rings = the layout's depth shells: LayoutConfiguration.baseRadius + k · shellSpacing (ConstellateKit).
SHELL_BASE, SHELL_STEP, SHELL_COUNT = 1.6, 1.25, 8


def make_floor_grid(dst=GRID_PATH, size=GRID_SIZE, metres=GRID_METRES):
    """Astrolabe floor, white on transparent (straight alpha; the app tints it with theme.floorGrid).

    Every mark means something, so the floor doubles as a legend for the constellation above it:
      • depth rings at the layout's shell radii (1.6 m + 1.25 m · k): ring k sits under folder depth k + 1
      • degree ticks just outside each ring (5° minor, 15° major) — the azimuth the subtree sectors use
      • 24 faint spokes (15°) from the first ring outwards, the 4 cardinals brighter
      • a faint 1 m grid near the centre for scale, a small reticle at the origin, a bezel at 11 m
      • radial fade to transparent well before the plane's edge (no square corners)
    All lines are anti-aliased analytically (distance to the mark in pixels)."""
    ppm = size / metres
    half = metres / 2
    axis = (np.arange(size, dtype=np.float32) + 0.5) / ppm - half    # metres, centre = 0
    X = axis[None, :]
    Y = -axis[:, None]                                                # row 0 = +Y
    R = np.sqrt(X * X + Y * Y)
    TH = np.degrees(np.arctan2(Y, X)) % 360.0

    def aa(d_px, half_w):
        """Coverage of a line of half-width `half_w` px at distance `d_px` px."""
        return np.clip(half_w + 0.5 - d_px, 0.0, 1.0)

    def radial_band(a, b):
        """1 between radii a and b (metres), anti-aliased."""
        return np.clip(np.minimum(R - a, b - R) * ppm + 0.5, 0.0, 1.0)

    def angular(step):
        """Distance in px (along the arc) to the nearest multiple of `step` degrees."""
        d = np.abs(((TH + step / 2) % step) - step / 2)
        return np.radians(d) * R * ppm

    def smooth(x):
        x = np.clip(x, 0.0, 1.0)
        return x * x * (3 - 2 * x)

    rings = [SHELL_BASE + SHELL_STEP * k for k in range(SHELL_COUNT)]
    alpha = np.zeros((size, size), np.float32)

    # metre grid, only near the centre
    gx = np.abs(((X + 0.5) % 1.0) - 0.5) * ppm
    gy = np.abs(((Y + 0.5) % 1.0) - 0.5) * ppm
    grid = np.maximum(aa(gx, 0.45), aa(gy, 0.45)) * 0.14 * (1.0 - smooth((R - 3.0) / 4.0))
    alpha = np.maximum(alpha, grid)

    # spokes
    d15, d5, d90 = angular(15.0), angular(5.0), angular(90.0)
    spokes = aa(d15, 0.45) * 0.2 * radial_band(rings[0], half)
    cardinals = aa(d90, 0.75) * 0.42 * radial_band(rings[0] - 0.25, half)
    alpha = np.maximum(alpha, np.maximum(spokes, cardinals))

    # depth rings + ticks
    for k, rk in enumerate(rings):
        weight = 0.8 if k == 0 else 0.6
        alpha = np.maximum(alpha, aa(np.abs(R - rk) * ppm, 1.0) * weight)
        alpha = np.maximum(alpha, aa(d5, 0.45) * radial_band(rk, rk + 0.07) * 0.5)
        alpha = np.maximum(alpha, aa(d15, 0.7) * radial_band(rk, rk + 0.15) * 0.75)
        # fine half-shell circle between depth rings (where the layout's sub-rings sit)
        if k < len(rings) - 1:
            alpha = np.maximum(alpha, aa(np.abs(R - (rk + SHELL_STEP / 2)) * ppm, 0.35) * 0.16)

    # reticle at the origin
    alpha = np.maximum(alpha, aa(np.abs(R - 0.25) * ppm, 0.6) * 0.55)
    alpha = np.maximum(alpha, aa(d90, 0.6) * radial_band(0.3, 0.42) * 0.6)

    # bezel: double ring + 2.5° ticks
    alpha = np.maximum(alpha, aa(np.abs(R - 11.0) * ppm, 1.2) * 0.7)
    alpha = np.maximum(alpha, aa(np.abs(R - 11.18) * ppm, 0.5) * 0.45)
    alpha = np.maximum(alpha, aa(angular(2.5), 0.5) * radial_band(10.82, 11.0) * 0.5)

    # radial fade: full inside 45 % of the half-size, 0 at the edge
    alpha *= smooth((half - R) / (0.55 * half))
    alpha = np.clip(alpha, 0.0, 1.0)

    rgba = np.empty((size, size, 4), np.uint8)
    rgba[..., :3] = 255  # straight (non-premultiplied) white
    rgba[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
    L.write_png(dst, rgba.tobytes(), size, size, 4)
    print(f"[constellate] Floor_Grid written -> {os.path.getsize(dst)} bytes (rings at {', '.join(f'{r:.2f}' for r in rings)} m)")
    return dst


def build_textures(force_fallback=False, sky=True, floor=True):
    L.ensure_dirs()
    used_fallback = False
    if sky:
        if force_fallback:
            render_sky_numpy(); used_fallback = True
        else:
            try:
                render_sky_cycles()
            except Exception as e:  # pragma: no cover
                print("[constellate] Cycles sky render failed, using numpy fallback:", repr(e))
                render_sky_numpy(); used_fallback = True
        make_sky_tint()
    if floor:
        make_floor_grid()
    return {"fallback": used_fallback}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--derived-only" in argv:          # reuse the existing Sky_Dark render
        L.ensure_dirs(); make_sky_tint(); make_floor_grid()
    else:
        build_textures(force_fallback="--fallback" in argv, sky="--floor-only" not in argv, floor="--sky-only" not in argv)
