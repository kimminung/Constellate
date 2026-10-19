"""README GIF from a rendered master: a few highlight segments joined by short dips through the night-sky colour,
a seamless loop back to the first frame, then a palette GIF (ffmpeg palettegen/paletteuse) squeezed with gifsicle.

python3 tools/make_gif.py <master.mkv> <out.gif> <width> <fps> <t0-t1> [<t0-t1> ...]
"""
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

src, out, W, FPS = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
SEGS = [tuple(float(x) for x in s.split("-")) for s in sys.argv[5:]]
COLORS = int(os.environ.get("COLORS", "128"))
LOSSY = os.environ.get("LOSSY", "30")
H = round(W * 1080 / 1920 / 2) * 2
SKY = (5, 7, 15)
XF, LOOP = 3, 4

tmp = tempfile.mkdtemp(prefix="gif_")
seq = []
for k, (a, b) in enumerate(SEGS):
    d = os.path.join(tmp, f"s{k}")
    os.makedirs(d)
    subprocess.run(["ffmpeg", "-v", "error", "-ss", f"{a:.3f}", "-t", f"{b - a:.3f}", "-i", src,
                    "-vf", f"fps={FPS},scale={W}:{H}:flags=lanczos", os.path.join(d, "%04d.png")], check=True)
    frames = [Image.open(os.path.join(d, f)).convert("RGB") for f in sorted(os.listdir(d))]
    if seq:
        sky = Image.new("RGB", (W, H), SKY)
        for j in range(XF):
            seq[-XF + j] = Image.blend(seq[-XF + j], sky, (j + 1) / (XF + 1))
            frames[j] = Image.blend(sky, frames[j], (j + 1) / (XF + 1))
    seq.extend(frames)
sky = Image.new("RGB", (W, H), SKY)
for j in range(LOOP):
    seq[-LOOP + j] = Image.blend(seq[-LOOP + j], sky, (j + 1) / (LOOP + 1))
    seq[j] = Image.blend(sky, seq[j], (j + 1) / (LOOP + 1)) if j < 2 else seq[j]
fr = os.path.join(tmp, "f")
os.makedirs(fr)
for i, im in enumerate(seq):
    im.save(os.path.join(fr, f"{i:05d}.png"))
pal = os.path.join(tmp, "pal.png")
subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", str(FPS), "-i", os.path.join(fr, "%05d.png"),
                "-vf", f"palettegen=max_colors={COLORS}:stats_mode=full:reserve_transparent=0", pal], check=True)
raw = out + ".raw.gif"
subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", str(FPS), "-i", os.path.join(fr, "%05d.png"), "-i", pal,
                "-lavfi", "paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle", "-loop", "0", raw], check=True)
subprocess.run(["gifsicle", "-O3", f"--lossy={LOSSY}", "-o", out, raw], check=True)
os.remove(raw)
shutil.rmtree(tmp)
print(f"{out}: {len(seq)} frames, {len(seq) / FPS:.1f}s, {W}x{H}, {os.path.getsize(out) / 1e6:.2f} MB")
