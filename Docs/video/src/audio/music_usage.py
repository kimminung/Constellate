"""Original score for the Constellate how-to film — "Field Notes".

A lighter companion to the intro's "Observatory": same D Lydian palette and instruments, 84 BPM (one chord per bar,
≈2.86 s), a warm pad, a plucked harp ostinato that walks the viewer through the chapters, a soft pulse (felt kick +
shaker) to keep the tutorial moving, celesta motifs on each chapter card, a glockenspiel figure on the title, the summon
and the end card, and a sine sub-bass. UI sound effects are synthesized and land on the director's events
(build/usage/events.json): mouse clicks, key presses, typing, menus, toasts, layout morphs, the summon whoosh, the
beacon, dock/undock, the microphone chime, members joining, the laser pointer, pins and theme changes.

MIDI written with mido, rendered per stem with FluidSynth + MuseScore General, effects with pedalboard.
Outputs build/usage/music.wav and build/usage/sfx.wav (48 kHz stereo).
"""
import json
import os
import random
import subprocess
import sys
from pathlib import Path

import mido
import numpy as np
import soundfile as sf
from pedalboard import Chorus, Compressor, HighpassFilter, HighShelfFilter, LowpassFilter, LowShelfFilter, Pedalboard, Reverb
from scipy.signal import butter, sosfilt

HERE = Path(__file__).resolve().parent
NAME = sys.argv[1] if len(sys.argv) > 1 else "usage"
BUILD = HERE / "build" / NAME
STEMS = BUILD / "music_stems"
STEMS.mkdir(parents=True, exist_ok=True)
SF = os.environ.get("SOUNDFONT", "/usr/share/sounds/sf3/MuseScore_General.sf3")
SR = 48000
BPM = 84
BEAT = 60 / BPM
BAR = 4 * BEAT
TPB = 480

tl = json.load(open(BUILD / "timeline.json"))
EV = json.load(open(BUILD / "events.json"))["events"]
DUR = tl["duration"]
random.seed(2026)
rng = np.random.default_rng(2026)
LINE = {l["id"]: l for l in tl["lines"]}
SPEECH = [(l["start"] - 0.2, l["end"] + 0.15) for l in tl["lines"]]
in_speech = lambda t: any(a <= t <= b for a, b in SPEECH)

CH = {
    "Dmaj9": dict(root=38, v=[62, 66, 69, 73, 76], arp=[50, 57, 62, 66, 69, 73, 76, 73], top=[73, 76, 78, 81]),
    "E/D":   dict(root=38, v=[64, 68, 71, 74], arp=[50, 56, 59, 64, 68, 71, 74, 71], top=[71, 74, 76, 80]),
    "Bm9":   dict(root=47, v=[62, 66, 69, 73], arp=[47, 54, 59, 62, 66, 69, 73, 69], top=[69, 73, 74, 78]),
    "Gmaj9": dict(root=43, v=[62, 66, 69, 71], arp=[43, 50, 55, 59, 62, 66, 69, 66], top=[69, 71, 74, 78]),
    "A6sus": dict(root=45, v=[62, 64, 66, 69], arp=[45, 52, 57, 62, 64, 66, 69, 66], top=[66, 69, 71, 76]),
    "F#m7":  dict(root=42, v=[61, 64, 69, 73], arp=[42, 49, 54, 57, 61, 64, 69, 64], top=[69, 73, 76, 78]),
    "Em9":   dict(root=40, v=[62, 66, 67, 71], arp=[40, 47, 52, 55, 59, 62, 66, 62], top=[66, 67, 71, 74]),
}
LOOP_A = ["Dmaj9", "Bm9", "Gmaj9", "A6sus"]
LOOP_B = ["Gmaj9", "A6sus", "F#m7", "Bm9"]
LOOP_C = ["Dmaj9", "E/D", "Bm9", "Gmaj9"]
PROG = (["Dmaj9", "E/D"] +                                   # title
        LOOP_A + LOOP_A + ["Dmaj9", "E/D"] +                  # ch1–3: open, navigate, layouts
        LOOP_B + LOOP_B + ["Em9", "A6sus"] +                  # ch4–6: relations, inspect, dial
        LOOP_C + LOOP_C + ["A6sus"] +                         # ch7–8: host, voice
        LOOP_B + ["Em9", "Gmaj9", "A6sus"] +                  # ch9–10: meeting, tour
        ["Dmaj9", "E/D", "Gmaj9"] +                           # ch11: themes
        ["Dmaj9"] * 4)                                        # end
NBARS = len(PROG)
SECT = []
for k, (n, s) in enumerate([(2, "intro"), (10, "A"), (10, "B"), (9, "C"), (7, "D"), (3, "E"), (4, "end")]):
    SECT += [s] * n
assert len(SECT) == NBARS, (len(SECT), NBARS)
chord_at = lambda t: CH[PROG[max(0, min(NBARS - 1, int(t // BAR)))]]
section = lambda b: SECT[max(0, min(NBARS - 1, b))]


class Track:
    def __init__(self, name, program, channel, volume=100, tie=False):
        self.name, self.program, self.channel, self.volume, self.tie = name, program, channel, volume, tie
        self.notes = []

    def resolved(self):
        out, by = [], {}
        for t, d, n, v in sorted(self.notes):
            by.setdefault(n, []).append([t, t + d, v])
        for n, lst in by.items():
            cur = None
            for on, off, v in lst:
                if cur and on <= cur[1]:
                    if self.tie and self.channel != 9:
                        cur[1] = max(cur[1], off)
                        continue
                    cur[1] = on - 0.006
                if cur:
                    out.append((cur[0], cur[1] - cur[0], n, cur[2]))
                cur = [on, off, v]
            if cur:
                out.append((cur[0], cur[1] - cur[0], n, cur[2]))
        return sorted(out)

    def add(self, t, dur, note, vel):
        if t < 0 or t >= DUR + 4:
            return
        self.notes.append((t, dur, int(note), int(max(1, min(127, vel)))))

    def write(self, path):
        mid = mido.MidiFile(ticks_per_beat=TPB)
        tr = mido.MidiTrack()
        mid.tracks.append(tr)
        tr.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(BPM), time=0))
        msgs = [(0, mido.Message("control_change", channel=self.channel, control=7, value=self.volume)),
                (0, mido.Message("control_change", channel=self.channel, control=91, value=0)),
                (0, mido.Message("control_change", channel=self.channel, control=93, value=0))]
        if self.channel != 9:
            msgs.append((0, mido.Message("program_change", channel=self.channel, program=self.program)))
        for t, d, n, v in self.resolved():
            on = int(round(t / BEAT * TPB)); off = int(round((t + d) / BEAT * TPB))
            msgs.append((on, mido.Message("note_on", channel=self.channel, note=n, velocity=v)))
            msgs.append((max(on + 1, off), mido.Message("note_off", channel=self.channel, note=n, velocity=0)))
        msgs.sort(key=lambda x: (x[0], 0 if x[1].type == "note_off" else 1))
        last = 0
        for tick, m in msgs:
            tr.append(m.copy(time=tick - last)); last = tick
        mid.save(path)


hum = lambda s=0.008: random.uniform(-s, s)
pad = Track("pad", 89, 0, 92, tie=True)
halo = Track("halo", 94, 1, 76, tie=True)
harp = Track("harp", 46, 2, 92)
cel = Track("celesta", 8, 3, 100)
glock = Track("glock", 9, 4, 84)
strings = Track("strings", 49, 5, 80, tie=True)
piano = Track("piano", 0, 6, 86)
perc = Track("perc", 0, 9, 88)
bar_t = lambda b, beat=0.0: b * BAR + beat * BEAT

# ostinato pattern (8ths): root-fifth-ninth-third shapes, varied per section
PAT = {"A": [0, 2, 4, 3, 5, 3, 4, 2], "B": [0, 3, 5, 4, 6, 4, 5, 3], "C": [0, 2, 4, 6, 5, 3, 4, 2], "D": [0, 3, 4, 5, 6, 5, 4, 3], "E": [0, 2, 3, 5, 4, 6, 5, 3]}
for b, name in enumerate(PROG):
    c = CH[name]; t0 = bar_t(b); sec = section(b)
    pv = {"intro": 32 + b * 5, "A": 40, "B": 42, "C": 44, "D": 42, "E": 40, "end": 38}[sec]
    for n in c["v"]:
        pad.add(t0 + 0.02, BAR + 0.2, n, pv)
    pad.add(t0 + 0.02, BAR + 0.2, c["root"] + 12, pv - 8)
    if sec in ("C", "D"):
        for n in c["top"][:3]:
            halo.add(t0 + 0.05, BAR + 0.2, n + 12, 28)
    if sec in PAT:
        base = {"A": 33, "B": 35, "C": 37, "D": 35, "E": 32}[sec]
        arp = c["arp"]
        for i, k in enumerate(PAT[sec]):
            n = arp[k % len(arp)]
            n = n + 12 if n < 55 else n
            acc = 6 if i == 0 else 3 if i == 4 else 0
            harp.add(bar_t(b, i * 0.5) + hum(), 1.0, n, base + acc + random.randint(-3, 3))
    if sec in ("B", "D"):
        for n in c["top"][:3]:
            strings.add(t0 + 0.06, BAR + 0.15, n - 12, 32)
    if sec == "C" and b % 2 == 0:
        top = c["top"]
        piano.add(bar_t(b, 1.0) + hum(), 1.3, top[2], 34)
        piano.add(bar_t(b, 1.5) + hum(), 1.1, top[1], 29)
    if sec in ("A", "B", "C", "D"):
        perc.add(t0, 0.25, 36, 36)
        perc.add(bar_t(b, 2.0), 0.25, 36, 28)
        for i in range(8):
            perc.add(bar_t(b, i * 0.5) + hum(0.005), 0.1, 82, (20 if i % 2 == 0 else 13) + random.randint(-2, 2))
        if sec in ("B", "D"):
            perc.add(bar_t(b, 1.0), 0.1, 75, 22); perc.add(bar_t(b, 3.0), 0.1, 75, 20)

# end: rolled Dmaj9 under the end card, glockenspiel shimmer
tE = LINE["u19"]["end"] + 0.1           # the final chord blooms after the last word, so the line's ending stays clear
for i, n in enumerate([38, 45, 50, 57, 62, 66, 69, 73, 76]):
    harp.add(tE + i * 0.06, 5.0, n, 40 - i)
for n in [62, 66, 69, 73, 76]:
    strings.add(LINE["u19"]["start"] - 0.4, 8.0, n - 12, 26)
tG = tE + 0.25
for i, n in enumerate([86, 88, 90, 93, 97]):
    glock.add(tG + i * BEAT / 4, 2.4, n, 38 - i * 3)


def upper(c, k):
    pool = sorted(set([n + 12 for n in c["top"]] + [n + 24 for n in c["top"][:2]]))
    return pool[k % len(pool)]


for e in EV:
    t, kind, i = e["t"], e["kind"], e["i"]
    c = chord_at(t + 0.01)
    soft = -8 if in_speech(t) or in_speech(t + 0.4) else 0
    if kind == "title":
        for k, n in enumerate([74, 78, 81, 85, 88]):
            glock.add(t + k * 0.06, 2.6, n, 42 - k * 3)
    elif kind == "chapter":
        cel.add(t, 1.4, upper(c, i * 2), 36 + soft)
        cel.add(t + BEAT / 2, 1.2, upper(c, i * 2 + 2), 30 + soft)
    elif kind in ("summon", "immersive"):
        for k, n in enumerate([81, 85, 88, 93]):
            glock.add(t + k * 0.07, 2.0, n, 36 + soft // 2 - k * 3)
    elif kind == "theme":
        for k in range(5):
            cel.add(t + k * 0.05, 1.0, upper(c, k + i), 30 + soft - k)
    elif kind in ("dock", "avatar", "pin"):
        cel.add(t, 0.9, upper(c, i + 1), 28 + soft)
    elif kind == "end":
        pass

tracks = [pad, halo, harp, cel, glock, strings, piano, perc]
for tr in tracks:
    mp = STEMS / f"{tr.name}.mid"
    tr.write(mp)
    wav = STEMS / f"{tr.name}_raw.wav"
    subprocess.run(["fluidsynth", "-ni", "-q", "-R", "0", "-C", "0", "-g", "0.7", "-r", str(SR), "-F", str(wav), SF, str(mp)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

N = int((DUR + 0.05) * SR)


def load(name):
    x, sr = sf.read(STEMS / f"{name}_raw.wav", dtype="float32", always_2d=True)
    assert sr == SR
    x = x.T
    out = np.zeros((2, N), np.float32)
    m = min(N, x.shape[1]); out[:, :m] = x[:, :m]
    return out


FX = {
    "pad":     (Pedalboard([HighpassFilter(80), LowpassFilter(5000), Chorus(rate_hz=0.2, depth=0.25, mix=0.35), Reverb(room_size=0.9, damping=0.5, wet_level=0.36, dry_level=0.68)]), 0.50),
    "halo":    (Pedalboard([HighpassFilter(300), LowpassFilter(7000), Reverb(room_size=0.95, damping=0.4, wet_level=0.5, dry_level=0.55)]), 0.26),
    "harp":    (Pedalboard([HighpassFilter(90), LowShelfFilter(250, -1.5), Reverb(room_size=0.8, damping=0.45, wet_level=0.3, dry_level=0.78, width=1.0)]), 0.78),
    "celesta": (Pedalboard([HighpassFilter(350), HighShelfFilter(7000, -4.0), Reverb(room_size=0.9, damping=0.35, wet_level=0.46, dry_level=0.6, width=1.0)]), 0.46),
    "glock":   (Pedalboard([HighpassFilter(500), HighShelfFilter(6500, -5.0), Reverb(room_size=0.92, damping=0.4, wet_level=0.5, dry_level=0.5, width=1.0)]), 0.34),
    "strings": (Pedalboard([HighpassFilter(110), LowpassFilter(6000), Reverb(room_size=0.93, damping=0.45, wet_level=0.42, dry_level=0.62)]), 0.36),
    "piano":   (Pedalboard([HighpassFilter(70), LowpassFilter(6500), Reverb(room_size=0.82, damping=0.55, wet_level=0.32, dry_level=0.75)]), 0.58),
    "perc":    (Pedalboard([HighpassFilter(40), HighShelfFilter(7000, -6.0), Reverb(room_size=0.5, damping=0.7, wet_level=0.14, dry_level=0.86)]), 0.40),
}
mix = np.zeros((2, N), np.float32)
for tr in tracks:
    x = load(tr.name)
    fx, g = FX[tr.name]
    y = fx(x, SR)
    if tr.name in ("celesta", "glock"):
        y[0] *= 1.08; y[1] *= 0.92
    mix += y * g

sub = np.zeros(N, np.float32)
for b, name in enumerate(PROG):
    if b < 2:
        continue
    f = 440 * 2 ** ((CH[name]["root"] - 12 - 69) / 12) if CH[name]["root"] >= 43 else 440 * 2 ** ((CH[name]["root"] - 69) / 12)
    a, z = int(bar_t(b) * SR), min(N, int((bar_t(b) + BAR + 0.25) * SR))
    if a >= N:
        break
    tt = np.arange(z - a) / SR
    env = np.minimum(1, tt / 0.3) * np.exp(-tt / 3.0)
    amp = {"A": 0.065, "B": 0.075, "C": 0.075, "D": 0.07, "E": 0.06, "end": 0.06}.get(section(b), 0.06)
    sub[a:z] += (np.sin(2 * np.pi * f * tt) + 0.18 * np.sin(4 * np.pi * f * tt)) * env * amp
mix += np.stack([sub, sub])
mix = Pedalboard([Compressor(threshold_db=-20, ratio=1.7, attack_ms=40, release_ms=400)])(mix, SR)
fi = int(1.6 * SR); mix[:, :fi] *= np.linspace(0, 1, fi) ** 1.5
fo0 = int((DUR - 3.4) * SR); mix[:, fo0:] *= np.linspace(1, 0, N - fo0) ** 1.6
peak = float(np.abs(mix).max()); mix *= 0.5 / max(peak, 1e-6)
sf.write(BUILD / "music.wav", mix.T, SR, subtype="FLOAT")


# ------------------------------------------------------------------ UI sound effects
def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def bandnoise(n, lo, hi, order=2):
    sos = butter(order, [lo, hi], "band", fs=SR, output="sos")
    return sosfilt(sos, rng.standard_normal(n))


def sweep_noise(dur, f0, f1):
    n = int(dur * SR); x = rng.standard_normal(n); out = np.zeros(n)
    blk = 512
    for s in range(0, n, blk):
        fc = f0 * (f1 / f0) ** (s / n)
        sos = butter(2, [max(60, fc * 0.6), min(SR / 2 - 100, fc * 1.6)], "band", fs=SR, output="sos")
        out[s:s + blk] = sosfilt(sos, x[s:s + blk])
    tt = np.arange(n) / n
    return out * np.sin(np.pi * tt) ** 1.6


def sfx_wave(kind, i=0):
    if kind == "click":   # trackpad / mouse click: press + release transients
        out = np.zeros(int(0.09 * SR))
        for k, (d, g, lo, hi) in enumerate([(0.0, 1.0, 1800, 7000), (0.055, 0.55, 2200, 8000)]):
            n = int(0.012 * SR); s = int(d * SR)
            out[s:s + n] += bandnoise(n, lo, hi) * env_exp(n, 0.0022) * 0.09 * g
            tt = np.arange(n) / SR; out[s:s + n] += np.sin(2 * np.pi * 1200 * tt) * env_exp(n, 0.003) * 0.03 * g
        return out
    if kind == "key":     # keyboard press (soft thock)
        n = int(0.06 * SR); tt = np.arange(n) / SR
        x = bandnoise(n, 700, 4200) * env_exp(n, 0.006) * 0.08 + np.sin(2 * np.pi * (180 + 60 * np.exp(-tt / 0.01)) * tt) * env_exp(n, 0.012) * 0.05
        return x
    if kind == "type":    # light typing tick
        n = int(0.03 * SR)
        return bandnoise(n, 1500, 6500) * env_exp(n, 0.0035) * (0.035 + 0.01 * ((i * 7) % 3))
    if kind == "menu":
        n = int(0.05 * SR); tt = np.arange(n) / SR
        return np.sin(2 * np.pi * 2300 * tt) * env_exp(n, 0.01) * 0.035
    if kind == "whoosh":
        return sweep_noise(0.8, 300, 2400) * 0.08
    if kind == "swish":   # small camera move (drag / scroll)
        return sweep_noise(0.5, 500, 1800) * 0.045
    if kind == "sheet":
        return sweep_noise(0.35, 900, 3000) * 0.04
    if kind == "rise":
        n = int(1.4 * SR); tt = np.arange(n) / SR
        f = 180 + 900 * (1 - np.exp(-tt / 0.5))
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, tt / 0.05) * np.exp(-tt / 0.6) * 0.055
        x += bandnoise(n, 2500, 9000) * np.minimum(1, tt / 0.3) * np.exp(-tt / 0.5) * 0.018
        return x
    if kind == "tap":
        n = int(0.07 * SR); tt = np.arange(n) / SR
        return np.sin(2 * np.pi * 1600 * tt) * env_exp(n, 0.012) * 0.08
    if kind == "dock":
        n = int(0.9 * SR); tt = np.arange(n) / SR
        return np.sin(2 * np.pi * (70 + 90 * np.exp(-tt / 0.08)) * tt) * env_exp(n, 0.25) * 0.14
    if kind == "mic":
        out = np.zeros(int(0.4 * SR))
        for k, f in enumerate([880.0, 1318.5]):
            n = int(0.25 * SR); tt = np.arange(n) / SR
            seg = (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)) * env_exp(n, 0.08) * 0.06
            s = int(k * 0.09 * SR); out[s:s + n] += seg
        return out
    if kind == "zap":
        n = int(0.22 * SR); tt = np.arange(n) / SR
        f = 2600 - 1800 * tt / tt[-1]
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.06) * 0.035
    if kind == "plop":
        n = int(0.12 * SR); tt = np.arange(n) / SR
        f = 520 + 340 * np.exp(-tt / 0.02)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.03) * 0.07
    if kind == "pop":     # toast
        n = int(0.09 * SR); tt = np.arange(n) / SR
        f = 900 + 500 * np.exp(-tt / 0.015)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.025) * 0.03
    raise ValueError(kind)


SFXMAP = {"click": "click", "select": "click", "key": "key", "type": "type", "menu": "menu", "morph": "whoosh", "whooshUp": "swish", "whooshDown": "swish",
          "drag": "swish", "scroll": "swish", "sheet": "sheet", "summon": "whoosh", "beacon": "rise", "tap": "tap", "dock": "dock", "undock": "dock",
          "mic": "mic", "pointer": "zap", "avatar": "plop", "pin": "tap", "toast": "pop", "immersive": "whoosh", "whoosh": "whoosh", "theme": "swish"}
fxs = np.zeros((2, N))
cues = [(e["t"], SFXMAP[e["kind"]], e.get("i", 0)) for e in EV if e["kind"] in SFXMAP]
for t, kind, i in cues:
    w = sfx_wave(kind, i)
    if kind in ("whoosh", "swish") and in_speech(t):
        w = w * 0.75
    a = int(max(0, t) * SR)
    if a >= N:
        continue
    z = min(N, a + len(w))
    pan = [-0.25, 0.25, -0.1, 0.1][i % 4] if kind in ("plop", "type", "whoosh", "swish") else 0.0
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    fxs[0, a:z] += w[: z - a] * l * 1.414; fxs[1, a:z] += w[: z - a] * r * 1.414
fxs = Pedalboard([Reverb(room_size=0.45, damping=0.55, wet_level=0.14, dry_level=0.9, width=1.0)])(fxs.astype(np.float32), SR)
sf.write(BUILD / "sfx.wav", fxs.T, SR, subtype="FLOAT")
print(f"music.wav {DUR:.2f}s bars {NBARS} ({NBARS * BAR:.1f}s) events {len(EV)} sfx cues {len(cues)} raw peak {peak:.3f}")
