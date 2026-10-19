"""Frame-accurate renderer: drives window.seek(t) on a director page and pipes frames into ffmpeg.

python3 tools/render.py <page.html> <out.mkv> [fps=30] [from=0] [to=duration] [query]
Frames are captured with CDP Page.captureScreenshot (JPEG q95) and encoded near-lossless (x264 crf 10).
"""
import asyncio
import base64
import subprocess
import sys
import time

from playwright.async_api import async_playwright

PAGE, OUT = sys.argv[1], sys.argv[2]
FPS = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
T0 = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
T1 = float(sys.argv[5]) if len(sys.argv) > 5 else -1
QUERY = sys.argv[6] if len(sys.argv) > 6 else ""
W = 1920
H = 1080


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
                                          "--font-render-hinting=none", "--force-color-profile=srgb", "--disable-gpu-vsync"])
        page = await b.new_page(viewport={"width": W, "height": H})
        page.on("pageerror", lambda e: print("pageerror:", e, flush=True))
        await page.goto(f"http://127.0.0.1:8765/{PAGE}{QUERY}")
        await page.wait_for_function("window.ready === true", timeout=300000)
        dur = await page.evaluate("window.DURATION")
        t1 = dur if T1 < 0 else min(T1, dur)
        n = int(round((t1 - T0) * FPS))
        cdp = await page.context.new_cdp_session(page)
        ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", str(FPS), "-c:v", "mjpeg", "-i", "-",
                               "-c:v", "libx264", "-preset", "fast", "-crf", "10", "-pix_fmt", "yuv420p", "-r", str(FPS), OUT], stdin=subprocess.PIPE)
        start = time.time()
        for i in range(n):
            t = T0 + i / FPS
            await page.evaluate(f"window.seek({t:.5f})")
            r = await cdp.send("Page.captureScreenshot", {"format": "jpeg", "quality": 95, "optimizeForSpeed": True})
            ff.stdin.write(base64.b64decode(r["data"]))
            if i % 60 == 0:
                el = time.time() - start
                print(f"{OUT}: frame {i}/{n} t={t:.2f} {el:.0f}s ({el / max(1, i):.2f}s/f)", flush=True)
        ff.stdin.close()
        ff.wait()
        print(f"done {OUT}: {n} frames in {time.time() - start:.0f}s", flush=True)
        await b.close()


asyncio.run(main())
