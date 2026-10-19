"""Render stills of a director page: python3 tools/stills.py intro.html outdir t1 t2 ... (query via Q env)"""
import asyncio
import os
import sys
import time

from playwright.async_api import async_playwright

PAGE, OUT, TIMES = sys.argv[1], sys.argv[2], [float(x) for x in sys.argv[3:]]
Q = os.environ.get("Q", "")
os.makedirs(OUT, exist_ok=True)


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
                                          "--font-render-hinting=none", "--force-color-profile=srgb"])
        page = await b.new_page(viewport={"width": 1920, "height": 1080})
        page.on("console", lambda m: print("console:", m.text) if m.type in ("error", "warning") and "GPU stall" not in m.text else None)
        page.on("pageerror", lambda e: print("pageerror:", e))
        await page.goto(f"http://127.0.0.1:8765/{PAGE}{Q}")
        await page.wait_for_function("window.ready === true", timeout=240000)
        cdp = await page.context.new_cdp_session(page)
        for t in TIMES:
            t0 = time.time()
            await page.evaluate(f"window.seek({t})")
            r = await cdp.send("Page.captureScreenshot", {"format": "jpeg", "quality": 88, "optimizeForSpeed": True})
            import base64
            open(os.path.join(OUT, f"t{t:07.2f}.jpg"), "wb").write(base64.b64decode(r["data"]))
            print(f"t={t:.2f} {time.time() - t0:.2f}s", flush=True)
        await b.close()


asyncio.run(main())
