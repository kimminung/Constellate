"""Original score for the Constellate intro — "Observatory".

Slow, luminous piece in D Lydian at 80 BPM (one chord per 3-second bar): warm pad with a halo layer, harp arpeggios,
celesta sparkles that land on the visual events exported by the director (build/intro/events.json: cards twinkling
into view, depth rings, sectors, relation chips, the six skies…), a glockenspiel flourish on the title, the summon and
the end card, slow strings and a soft heartbeat pulse in the middle, a sine sub-bass, plus synthesized sound effects
(whooshes for camera moves and layout morphs, a riser into the title, the beacon rising, UI ticks).

MIDI written with mido, rendered per stem with FluidSynth + MuseScore General, effects with pedalboard.
Outputs build/intro/music.wav and build/intro/sfx.wav (48 kHz stereo).
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
NAME = sys.argv[1] if len(sys.argv) > 1 else "intro"
BUILD = HERE / "build" / NAME
STEMS = BUILD / "music_stems"
STEMS.mkdir(parents=True, exist_ok=True)
SF = os.environ.get("SOUNDFONT", "/usr/share/sounds/sf3/MuseScore_General.sf3")
SR = 48000
BPM = 80
BEAT = 60 / BPM          # 0.75 s
BAR = 4 * BEAT           # 3.0 s
TPB = 480

tl = json.load(open(BUILD / "timeline.json"))
EV = json.load(open(BUILD / "events.json"))["events"]
DUR = tl["duration"]
random.seed(1019)
rng = np.random.default_rng(1019)
LINE = {l["id"]: l for l in tl["lines"]}
SPEECH = [(l["start"] - 0.2, l["end"] + 0.15) for l in tl["lines"]]
in_speech = lambda t: any(a <= t <= b for a, b in SPEECH)

# ------------------------------------------------------------------ harmony (D Lydian)
CH = {
    "Dmaj9": dict(root=38, v=[62, 66, 69, 73, 76], arp=[50, 57, 62, 66, 69, 73, 76, 73], top=[73, 76, 78, 81]),
    "E/D":   dict(root=38, v=[64, 68, 71, 74], arp=[50, 56, 59, 64, 68, 71, 74, 71], top=[71, 74, 76, 80]),
    "Bm9":   dict(root=47, v=[62, 66, 69, 73], arp=[47, 54, 59, 62, 66, 69, 73, 69], top=[69, 73, 74, 78]),
    "Gmaj9": dict(root=43, v=[62, 66, 69, 71], arp=[43, 50, 55, 59, 62, 66, 69, 66], top=[69, 71, 74, 78]),
    "A6sus": dict(root=45, v=[62, 64, 66, 69], arp=[45, 52, 57, 62, 64, 66, 69, 66], top=[66, 69, 71, 76]),
    "F#m7":  dict(root=42, v=[61, 64, 69, 73], arp=[42, 49, 54, 57, 61, 64, 69, 64], top=[69, 73, 76, 78]),
    "Em9":   dict(root=40, v=[62, 66, 67, 71], arp=[40, 47, 52, 55, 59, 62, 66, 62], top=[66, 67, 71, 74]),
}
PROG = (["Dmaj9", "Dmaj9", "E/D"] +
        ["Dmaj9", "E/D", "Bm9", "Gmaj9"] + ["Dmaj9", "E/D", "Bm9", "A6sus"] +          # A: title, ingest, layout
        ["Gmaj9", "A6sus", "F#m7", "Bm9"] + ["Em9", "Gmaj9", "A6sus"] +               # B: dial, relations, stars
        ["Dmaj9", "E/D", "Gmaj9"] +                                                  # interlude: six skies
        ["Bm9", "Gmaj9", "Dmaj9", "A6sus"] + ["Gmaj9", "A6sus", "F#m7", "Bm9"] +      # C: host orb, voice, meeting
        ["Em9", "A6sus", "Dmaj9"] + ["Dmaj9", "Dmaj9", "Dmaj9"])                     # D + end
NBARS = len(PROG)


def chord_at(t):
    return CH[PROG[max(0, min(NBARS - 1, int(t // BAR)))]]


def section(b):
    if b < 3: return "intro"
    if b < 11: return "A"
    if b < 18: return "B"
    if b < 21: return "I"
    if b < 29: return "C"
    if b < 31: return "D"
    return "end"


class Track:
    def __init__(self, name, program, channel, volume=100, tie=False):
        self.name, self.program, self.channel, self.volume, self.tie = name, program, channel, volume, tie
        self.notes = []

    def resolved(self):
        """Same pitch overlapping itself: tie (pads/strings) or re-articulate (others)."""
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
pad = Track("pad", 89, 0, 96, tie=True)       # Pad 2 (warm)
halo = Track("halo", 94, 1, 80, tie=True)     # Pad 7 (halo)
harp = Track("harp", 46, 2, 92)               # Orchestral harp
cel = Track("celesta", 8, 3, 100)             # Celesta
glock = Track("glock", 9, 4, 84)              # Glockenspiel
strings = Track("strings", 49, 5, 86, tie=True)
piano = Track("piano", 0, 6, 88)
perc = Track("perc", 0, 9, 90)


def bar_t(b, beat=0.0):
    return b * BAR + beat * BEAT


# ------------------------------------------------------------------ arrangement
for b, name in enumerate(PROG):
    c = CH[name]; t0 = bar_t(b); sec = section(b)
    pv = {"intro": 30 + b * 4, "A": 42, "B": 46, "I": 50, "C": 48, "D": 42, "end": 40}[sec]
    for n in c["v"]:
        pad.add(t0 + 0.02, BAR + 0.2, n, pv)
    pad.add(t0 + 0.02, BAR + 0.2, c["root"] + 12, pv - 8)
    if sec in ("B", "I", "C"):
        for n in c["top"][:3]:
            halo.add(t0 + 0.05, BAR + 0.2, n + 12, 30 if sec != "I" else 36)
    # harp arpeggio: 8ths in A/B/C, 16ths in the interlude, thinner in D
    if sec in ("A", "B", "C", "D"):
        base = {"A": 34, "B": 38, "C": 40, "D": 32}[sec]
        for i, n in enumerate(c["arp"]):
            if sec == "D" and i % 2:
                continue
            acc = 6 if i == 0 else 3 if i == 4 else 0
            harp.add(bar_t(b, i * 0.5) + hum(), 1.2, n + 12 if n < 55 else n, base + acc + random.randint(-3, 3))
    if sec == "I":
        seq = c["arp"] + c["arp"][::-1]
        for i in range(16):
            n = seq[i % len(seq)]
            harp.add(bar_t(b, i * 0.25) + hum(0.004), 0.8, n + 12 if n < 57 else n, 38 + (6 if i % 4 == 0 else 0) + random.randint(-3, 3))
    # strings: long chords in B and C
    if sec in ("B", "C"):
        sv = 36 if sec == "B" else 42
        for n in c["top"][:3]:
            strings.add(t0 + 0.06, BAR + 0.15, n - 12, sv)
    # piano motif in C (answering phrases on beats 2 and 4)
    if sec == "C":
        top = c["top"]
        piano.add(bar_t(b, 1.0) + hum(), 1.4, top[2], 38)
        piano.add(bar_t(b, 1.5) + hum(), 1.2, top[1], 32)
        if b % 2 == 1:
            piano.add(bar_t(b, 3.0) + hum(), 1.6, top[3], 34)
    # soft heartbeat in B and C; shaker in C
    if sec in ("B", "C"):
        perc.add(t0, 0.25, 36, 44 if sec == "C" else 38)
        perc.add(bar_t(b, 2.0), 0.25, 36, 34)
        if sec == "C":
            for i in range(8):
                perc.add(bar_t(b, i * 0.5) + hum(0.005), 0.1, 82, (24 if i % 2 == 0 else 16) + random.randint(-2, 2))

# ending: rolled Dmaj9 at the end card, glockenspiel shimmer, long ring
tE = LINE["i15"]["start"] - 0.2
for i, n in enumerate([38, 45, 50, 57, 62, 66, 69, 73, 76]):
    harp.add(tE + i * 0.06, 6.5, n, 46 - i)
for n in [62, 66, 69, 73, 76]:
    strings.add(tE + 0.05, 7.0, n - 12, 40)
for i, n in enumerate([86, 88, 90, 93, 97]):
    glock.add(tE + 0.25 + i * BEAT / 4, 2.4, n, 40 - i * 3)

# ------------------------------------------------------------------ sparkles on visual events
def upper(c, k):
    pool = sorted(set([n + 12 for n in c["top"]] + [n + 24 for n in c["top"][:2]]))
    return pool[k % len(pool)]


def snap16(t):
    q = BEAT / 4
    return round(t / q) * q


for e in EV:
    t, kind, i = e["t"], e["kind"], e["i"]
    c = chord_at(t + 0.01)
    soft = -8 if in_speech(t) or in_speech(t + 0.4) else 0
    ts = snap16(t) if section(int(t // BAR)) in ("B", "C", "I") else t
    if kind == "twinkle":
        cel.add(t, 1.6, upper(c, i * 3), 30 + (i % 3) * 3)
    elif kind == "title":
        for k, n in enumerate([74, 78, 81, 85, 88]):
            glock.add(t + k * 0.06, 2.6, n, 46 - k * 3)
    elif kind in ("ring", "sector", "ray", "chip", "star", "chime"):
        cel.add(ts, 1.1, upper(c, i + {"ring": 0, "sector": 2, "ray": 1, "chip": 3, "star": 4, "chime": 2}[kind]), 38 + soft + (i % 2) * 3)
    elif kind == "tick":
        cel.add(ts, 0.5, upper(c, i), 26 + soft)
    elif kind == "morph":
        cel.add(ts, 1.4, upper(c, i * 2 + 1), 40 + soft)
        cel.add(ts + BEAT / 4, 1.2, upper(c, i * 2 + 3), 34 + soft)
    elif kind in ("summon", "end"):
        for k, n in enumerate([81, 85, 88, 93]):
            glock.add(t + k * 0.07, 2.0, n, (40 if kind == "summon" else 36) + soft // 2 - k * 3)
    elif kind in ("pin", "pointer", "avatar", "dock", "tap", "mic", "orbs"):
        cel.add(ts, 0.9, upper(c, i + 1), 30 + soft)

# ------------------------------------------------------------------ render stems
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
    "pad":     (Pedalboard([HighpassFilter(80), LowpassFilter(5000), Chorus(rate_hz=0.2, depth=0.25, mix=0.35), Reverb(room_size=0.92, damping=0.5, wet_level=0.38, dry_level=0.68)]), 0.55),
    "halo":    (Pedalboard([HighpassFilter(300), LowpassFilter(7000), Reverb(room_size=0.95, damping=0.4, wet_level=0.5, dry_level=0.55)]), 0.30),
    "harp":    (Pedalboard([HighpassFilter(90), LowShelfFilter(250, -1.5), Reverb(room_size=0.85, damping=0.45, wet_level=0.34, dry_level=0.75, width=1.0)]), 0.80),
    "celesta": (Pedalboard([HighpassFilter(350), HighShelfFilter(7000, -4.0), Reverb(room_size=0.9, damping=0.35, wet_level=0.48, dry_level=0.58, width=1.0)]), 0.50),
    "glock":   (Pedalboard([HighpassFilter(500), HighShelfFilter(6500, -5.0), Reverb(room_size=0.92, damping=0.4, wet_level=0.5, dry_level=0.5, width=1.0)]), 0.36),
    "strings": (Pedalboard([HighpassFilter(110), LowpassFilter(6000), Reverb(room_size=0.93, damping=0.45, wet_level=0.42, dry_level=0.62)]), 0.40),
    "piano":   (Pedalboard([HighpassFilter(70), LowpassFilter(6500), Reverb(room_size=0.82, damping=0.55, wet_level=0.32, dry_level=0.75)]), 0.62),
    "perc":    (Pedalboard([HighpassFilter(40), HighShelfFilter(7000, -6.0), Reverb(room_size=0.55, damping=0.7, wet_level=0.16, dry_level=0.85)]), 0.42),
}
mix = np.zeros((2, N), np.float32)
for tr in tracks:
    x = load(tr.name)
    fx, g = FX[tr.name]
    y = fx(x, SR)
    if tr.name in ("celesta", "glock"):
        y[0] *= 1.08; y[1] *= 0.92
    sf.write(STEMS / f"{tr.name}.wav", (y * g).T, SR, subtype="FLOAT")
    mix += y * g

# sine sub-bass (root per bar, soft swell; enters with the title)
t_all = np.arange(N) / SR
sub = np.zeros(N, np.float32)
for b, name in enumerate(PROG):
    if b < 3:
        continue
    f = 440 * 2 ** ((CH[name]["root"] - 12 - 69) / 12) if CH[name]["root"] >= 43 else 440 * 2 ** ((CH[name]["root"] - 69) / 12)
    a, z = int(bar_t(b) * SR), min(N, int((bar_t(b) + BAR + 0.25) * SR))
    if a >= N:
        break
    tt = np.arange(z - a) / SR
    env = np.minimum(1, tt / 0.35) * np.exp(-tt / 3.2)
    sec = section(b)
    amp = {"A": 0.075, "B": 0.09, "I": 0.085, "C": 0.09, "D": 0.07, "end": 0.07}.get(sec, 0.07)
    sub[a:z] += (np.sin(2 * np.pi * f * tt) + 0.18 * np.sin(4 * np.pi * f * tt)) * env * amp
mix += np.stack([sub, sub])

mix = Pedalboard([Compressor(threshold_db=-20, ratio=1.7, attack_ms=40, release_ms=400)])(mix, SR)
fi = int(1.8 * SR); mix[:, :fi] *= np.linspace(0, 1, fi) ** 1.5
fo0 = int((DUR - 3.2) * SR); mix[:, fo0:] *= np.linspace(1, 0, N - fo0) ** 1.6
peak = float(np.abs(mix).max()); mix *= 0.5 / max(peak, 1e-6)
sf.write(BUILD / "music.wav", mix.T, SR, subtype="FLOAT")

# ------------------------------------------------------------------ sound effects
def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def bandnoise(n, lo, hi):
    sos = butter(2, [lo, hi], "band", fs=SR, output="sos")
    return sosfilt(sos, rng.standard_normal(n))


def sweep_noise(dur, f0, f1, up=True):
    n = int(dur * SR); x = rng.standard_normal(n); out = np.zeros(n)
    blk = 512
    for s in range(0, n, blk):
        k = s / n
        fc = f0 * (f1 / f0) ** k
        sos = butter(2, [max(60, fc * 0.6), min(SR / 2 - 100, fc * 1.6)], "band", fs=SR, output="sos")
        out[s:s + blk] = sosfilt(sos, x[s:s + blk])
    tt = np.arange(n) / n
    env = np.sin(np.pi * tt) ** 1.6 if not up else (tt ** 2.2) * np.minimum(1, (1 - tt) / 0.06)
    return out * env


def sfx_wave(kind):
    if kind == "whoosh":
        return sweep_noise(0.9, 300, 2400, up=False) * 0.10
    if kind == "riser":
        r = sweep_noise(2.2, 200, 5000, up=True) * 0.08
        n = len(r); tt = np.arange(n) / SR
        r += np.sin(2 * np.pi * (220 + 660 * (tt / tt[-1]) ** 2) * tt) * (tt / tt[-1]) ** 3 * 0.025
        return r
    if kind == "rise":   # beacon light pillar
        n = int(1.4 * SR); tt = np.arange(n) / SR
        f = 180 + 900 * (1 - np.exp(-tt / 0.5))
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, tt / 0.05) * np.exp(-tt / 0.6) * 0.06
        x += bandnoise(n, 2500, 9000) * np.minimum(1, tt / 0.3) * np.exp(-tt / 0.5) * 0.02
        return x
    if kind == "tap":
        n = int(0.07 * SR); tt = np.arange(n) / SR
        return np.sin(2 * np.pi * 1600 * tt) * env_exp(n, 0.012) * 0.10
    if kind == "dock":
        n = int(0.9 * SR); tt = np.arange(n) / SR
        return np.sin(2 * np.pi * (70 + 90 * np.exp(-tt / 0.08)) * tt) * env_exp(n, 0.25) * 0.16
    if kind == "mic":
        out = np.zeros(int(0.4 * SR))
        for k, f in enumerate([880.0, 1318.5]):
            n = int(0.25 * SR); tt = np.arange(n) / SR
            seg = (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)) * env_exp(n, 0.08) * 0.07
            i = int(k * 0.09 * SR); out[i:i + n] += seg
        return out
    if kind == "zap":
        n = int(0.22 * SR); tt = np.arange(n) / SR
        f = 2600 - 1800 * tt / tt[-1]
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.06) * 0.04
    if kind == "plop":
        n = int(0.12 * SR); tt = np.arange(n) / SR
        f = 520 + 340 * np.exp(-tt / 0.02)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.03) * 0.08
    if kind == "tick":
        n = int(0.04 * SR); tt = np.arange(n) / SR
        return np.sin(2 * np.pi * 2900 * tt) * env_exp(n, 0.008) * 0.05
    raise ValueError(kind)


SFXMAP = {"morph": "whoosh", "whooshUp": "whoosh", "whooshDown": "whoosh", "beacon": "rise", "tap": "tap", "dock": "dock", "undock": "dock",
          "mic": "mic", "pointer": "zap", "avatar": "plop", "pin": "tap", "summon": "whoosh", "tick": "tick"}
fxs = np.zeros((2, N))
cues = [(EV_["t"], SFXMAP[EV_["kind"]], EV_.get("i", 0)) for EV_ in EV if EV_["kind"] in SFXMAP]
title = next(e["t"] for e in EV if e["kind"] == "title")
cues.append((title - 2.2, "riser", 0))
for t, kind, i in cues:
    w = sfx_wave(kind)
    if kind in ("whoosh",) and in_speech(t):
        w = w * 0.7
    a = int(max(0, t) * SR)
    if a >= N:
        continue
    z = min(N, a + len(w))
    pan = [-0.3, 0.3, -0.15, 0.15][i % 4] if kind in ("plop", "tick", "whoosh") else 0.0
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    fxs[0, a:z] += w[: z - a] * l * 1.414; fxs[1, a:z] += w[: z - a] * r * 1.414
fxs = Pedalboard([Reverb(room_size=0.6, damping=0.5, wet_level=0.22, dry_level=0.85, width=1.0)])(fxs.astype(np.float32), SR)
sf.write(BUILD / "sfx.wav", fxs.T, SR, subtype="FLOAT")
print(f"music.wav {DUR:.2f}s bars {NBARS} events {len(EV)} sfx cues {len(cues)} raw peak {peak:.3f}")
