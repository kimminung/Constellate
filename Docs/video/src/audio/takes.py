"""Generate N takes per script line (different seeds) and score each with SenseVoice CER.

python3 takes.py script_intro.json 6   ->  build/intro/takes/<id>_<seed>.wav, build/intro/takes.json
"""
import json
import os
import sys

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from asr import cer, transcribe  # noqa: E402
from tts import synth  # noqa: E402

script_path = sys.argv[1]
n_takes = int(sys.argv[2]) if len(sys.argv) > 2 else 6
only = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else None
script = json.load(open(os.path.join(HERE, script_path)))
name = script["name"]
out_dir = os.path.join(HERE, "build", name, "takes")
os.makedirs(out_dir, exist_ok=True)
db_path = os.path.join(HERE, "build", name, "takes.json")
db = json.load(open(db_path)) if os.path.exists(db_path) else {}


def hangul_count(s):
    return sum(1 for c in s if "가" <= c <= "힣")


for line in script["lines"]:
    lid = line["id"]
    if only and lid not in only:
        continue
    sid = line.get("sid", script["sid"])
    speed = line.get("speed", script["speed"])
    entries = [] if only else db.get(lid, [])
    done = {e["seed"] for e in entries if e.get("say") == line["say"] and e.get("sid") == sid and e.get("speed") == speed}
    entries = [e for e in entries if e.get("say") == line["say"] and e.get("sid") == sid and e.get("speed") == speed]
    for seed in range(1, n_takes + 1):
        if seed in done:
            continue
        wav = os.path.join(out_dir, f"{lid}_{seed}.wav")
        dur, sr, _ = synth(line["say"], wav, sid=sid, speed=speed, seed=seed)
        audio, _ = sf.read(wav, dtype="float32")
        hyp = transcribe(wav)
        c = cer(line["say"], hyp)
        peak = float(np.abs(audio).max())
        entries.append({"seed": seed, "sid": sid, "speed": speed, "say": line["say"], "dur": round(dur, 3), "cer": round(c, 4),
                        "hyp": hyp, "peak": round(peak, 3), "rate": round(hangul_count(line["say"]) / dur, 2), "wav": os.path.relpath(wav, HERE)})
        print(lid, seed, f"dur {dur:.2f}", f"cer {c:.3f}", hyp, flush=True)
    db[lid] = entries
    json.dump(db, open(db_path, "w"), ensure_ascii=False, indent=1)
print("done", db_path)
