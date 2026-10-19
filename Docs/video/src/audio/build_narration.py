"""Pick the best take per line and lay the narration out on a timeline.

python3 build_narration.py script_intro.json timing_intro.json
  -> build/<name>/narration.wav (48 kHz mono), build/<name>/timeline.json

timing_*.json: {"start": 3.0, "tail": 5.0, "gap": 0.55, "pre": {"i02": 1.2, ...}, "pick": {"i11": 3}}
Best take = lowest CER; ties → the take whose ASR text matches the most leading characters, then seed order.
"""
import json
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 48000

script = json.load(open(os.path.join(HERE, sys.argv[1])))
timing = json.load(open(os.path.join(HERE, sys.argv[2])))
name = script["name"]
db = json.load(open(os.path.join(HERE, "build", name, "takes.json")))


def load(path):
    a, sr = sf.read(os.path.join(HERE, path), dtype="float32")
    if a.ndim > 1:
        a = a.mean(axis=1)
    if sr != SR:
        a = resample_poly(a, SR, sr).astype(np.float32)
    # trim leading/trailing silence (keep 30 ms)
    env = np.abs(a) > 0.01
    idx = np.where(env)[0]
    s = 0
    if len(idx):
        s = max(0, idx[0] - int(0.03 * SR))
        e = min(len(a), idx[-1] + int(0.06 * SR))
        a = a[s:e]
    fade = int(0.012 * SR)
    a[:fade] *= np.linspace(0, 1, fade)
    a[-fade:] *= np.linspace(1, 0, fade)
    return a, s / SR


def word_cues(path):
    """SenseVoice token timestamps (seconds from the start of the raw take)."""
    sys.path.insert(0, HERE)
    import asr
    rec = asr.get_rec()
    a, sr = sf.read(os.path.join(HERE, path), dtype="float32")
    if a.ndim > 1:
        a = a.mean(axis=1)
    if sr != 16000:
        a = resample_poly(a, 16000, sr).astype(np.float32)
    st = rec.create_stream()
    st.accept_waveform(16000, a)
    rec.decode_stream(st)
    return list(zip(st.result.tokens, st.result.timestamps))


lines_out = []
pieces = []
t = timing.get("start", 2.0)
for line in script["lines"]:
    lid = line["id"]
    takes = db[lid]
    forced = timing.get("pick", {}).get(lid)
    if forced:
        best = next(e for e in takes if e["seed"] == forced)
    else:
        best = sorted(takes, key=lambda e: (round(e["cer"], 3), e["seed"]))[0]
    t += timing.get("pre", {}).get(lid, timing.get("gap", 0.55)) if lines_out else 0
    audio, trim = load(best["wav"])
    dur = len(audio) / SR
    pieces.append((t, audio))
    words = [{"w": w, "t": round(t + ts - trim, 3)} for w, ts in word_cues(best["wav"])]
    lines_out.append({"id": lid, "start": round(t, 3), "end": round(t + dur, 3), "dur": round(dur, 3), "cap": line["cap"], "say": line["say"],
                      "seed": best["seed"], "cer": best["cer"], "hyp": best["hyp"], "chapter": line.get("chapter"), "sid": line.get("sid", script["sid"]), "words": words})
    t += dur
total = t + timing.get("tail", 4.0)
mix = np.zeros(int(total * SR) + SR, dtype=np.float32)
for start, audio in pieces:
    i = int(start * SR)
    mix[i:i + len(audio)] += audio
mix = mix[: int(total * SR)]
peak = np.abs(mix).max()
mix = mix / max(peak, 1e-6) * 0.89
out_dir = os.path.join(HERE, "build", name)
sf.write(os.path.join(out_dir, "narration.wav"), mix, SR, subtype="PCM_24")
json.dump({"duration": round(total, 3), "lines": lines_out}, open(os.path.join(out_dir, "timeline.json"), "w"), ensure_ascii=False, indent=1)
web = os.path.join(HERE, "..", "web", "data", f"tl_{name}.js")
# speech envelope (50 fps) for voice-reactive UI
env_fps = 50
hop = SR // env_fps
n = len(mix) // hop
rms = np.sqrt(np.mean(mix[: n * hop].reshape(n, hop) ** 2, axis=1))
rms = (rms / max(rms.max(), 1e-6)).round(3).tolist()
open(web, "w").write("window.TL = " + json.dumps({"duration": round(total, 3), "lines": lines_out, "env": rms, "envFps": env_fps}, ensure_ascii=False) + ";\n")
print("wrote", web)
for l in lines_out:
    print(f'{l["id"]} {l["start"]:7.2f}–{l["end"]:7.2f} ({l["dur"]:.2f}s) seed {l["seed"]} cer {l["cer"]:.3f}  {l["cap"]}')
print("total", round(total, 2), "s")
