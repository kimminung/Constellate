"""Narration + ducked music + sound effects → build/<name>/mix.wav (-16 LUFS integrated, ≤ -1.2 dBTP).

- narration: high-pass, light EQ, gentle compression, every line levelled to -19 LUFS
- music: bed at -24 LUFS, ducks under speech (-9 dB broadband, a further -4 dB above 1.2 kHz, slow release)
- sfx: added at a fixed relative level, ducked 4 dB under speech
(adapted from the Lantern / Couldra intro pipeline)
"""
import json
import sys
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from pedalboard import Compressor, HighpassFilter, PeakFilter, Pedalboard
from scipy.ndimage import maximum_filter1d
from scipy.signal import butter, resample_poly, sosfiltfilt

HERE = Path(__file__).resolve().parent
NAME = sys.argv[1] if len(sys.argv) > 1 else "intro"
MUSIC_LUFS = float(sys.argv[2]) if len(sys.argv) > 2 else -24.0
SFX_GAIN = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
BUILD = HERE / "build" / NAME
SR = 48000
tl = json.load(open(BUILD / "timeline.json"))
meter = pyln.Meter(SR)

nar, sr = sf.read(BUILD / "narration.wav", dtype="float32")
assert sr == SR
voice_fx = Pedalboard([
    HighpassFilter(cutoff_frequency_hz=75),
    PeakFilter(cutoff_frequency_hz=200, gain_db=-1.2, q=0.9),
    PeakFilter(cutoff_frequency_hz=3300, gain_db=1.8, q=0.8),
    Compressor(threshold_db=-22, ratio=2.2, attack_ms=8, release_ms=120),
])
nar = voice_fx(nar[None, :], SR)[0]
for l in tl["lines"]:
    a, b = int((l["start"] - 0.05) * SR), int((l["end"] + 0.1) * SR)
    seg = nar[a:b]
    loud = meter.integrated_loudness(np.concatenate([seg, np.zeros(int(0.5 * SR), np.float32)]))
    target = -19.0 if l.get("sid", 4) == 4 else -19.5
    nar[a:b] = seg * 10 ** ((target - loud) / 20)

mus, sr = sf.read(BUILD / "music.wav", dtype="float32", always_2d=True)
mus = mus.T
fx = None
if (BUILD / "sfx.wav").exists():
    fx, _ = sf.read(BUILD / "sfx.wav", dtype="float32", always_2d=True)
    fx = fx.T
N = max(len(nar), mus.shape[1])
nar = np.pad(nar, (0, N - len(nar)))
mus = np.pad(mus, ((0, 0), (0, N - mus.shape[1])))
mloud = meter.integrated_loudness(mus.T)
mus *= 10 ** ((MUSIC_LUFS - mloud) / 20)

hop = 240
n = N // hop
env = np.sqrt((nar[: n * hop].reshape(n, hop) ** 2).mean(1))
act = (env > 10 ** (-42 / 20)).astype(np.float32)
act = maximum_filter1d(act, size=int(0.45 / 0.005))
sm = np.zeros_like(act)
a_up, a_dn = np.exp(-0.005 / 0.08), np.exp(-0.005 / 0.9)
v = 0.0
for i, x in enumerate(act):
    v = a_up * v + (1 - a_up) * x if x > v else a_dn * v + (1 - a_dn) * x
    sm[i] = v
duck = np.repeat(sm, hop)
duck = np.pad(duck, (0, N - len(duck)), mode="edge")
g_all = 10 ** (-9.0 * duck / 20)
g_hi = 10 ** (-4.0 * duck / 20)
sos_lo = butter(4, 1200, "low", fs=SR, output="sos")
sos_hi = butter(4, 1200, "high", fs=SR, output="sos")
lo = sosfiltfilt(sos_lo, mus, axis=1)
hi = sosfiltfilt(sos_hi, mus, axis=1)
mus_d = (lo + hi * g_hi) * g_all

mix = mus_d + nar[None, :]
if fx is not None:
    fx = np.pad(fx, ((0, 0), (0, N - fx.shape[1])))[:, :N]
    fx_scale = 10 ** ((MUSIC_LUFS + 24.0) / 20) * SFX_GAIN   # follow the music level
    mix = mix + fx * fx_scale * 10 ** (-4.0 * duck / 20)
loud = meter.integrated_loudness(mix.T)
mix *= 10 ** ((-16.0 - loud) / 20)


def true_peak(x):
    return float(np.abs(resample_poly(x, 4, 1, axis=1)).max())


ceiling = 10 ** (-1.2 / 20)
tp = true_peak(mix)
if tp > ceiling:
    up = np.abs(resample_poly(mix, 4, 1, axis=1)).max(0)
    pk = up[: 4 * N].reshape(-1, 4).max(1) if len(up) >= 4 * N else np.pad(up, (0, 4 * N - len(up))).reshape(-1, 4).max(1)
    need = np.minimum(1.0, ceiling / np.maximum(pk, 1e-9))
    la = int(0.004 * SR)
    need = -maximum_filter1d(-need, size=2 * la + 1)
    g = np.empty_like(need)
    rel = np.exp(-1 / (0.08 * SR))
    cur = 1.0
    for i, x in enumerate(need):
        cur = x if x < cur else rel * cur + (1 - rel) * x
        g[i] = cur
    mix *= g[None, :]
print(f"{NAME} mix: {loud:.1f} → {meter.integrated_loudness(mix.T):.1f} LUFS, true peak {20 * np.log10(true_peak(mix)):.2f} dBTP")
sf.write(BUILD / "mix.wav", mix.T, SR, subtype="PCM_24")
sf.write(BUILD / "voice_only.wav", (nar * 10 ** ((-16.0 - loud) / 20)), SR, subtype="PCM_24")
