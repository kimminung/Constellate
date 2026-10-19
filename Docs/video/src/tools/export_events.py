"""Exports window.EVENTS of a director page to a JSON file (for music.py)."""
import asyncio, json, sys
from playwright.async_api import async_playwright
PAGE, OUT = sys.argv[1], sys.argv[2]
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        page = await b.new_page(viewport={"width": 1920, "height": 1080})
        await page.goto(f"http://127.0.0.1:8765/{PAGE}")
        await page.wait_for_function("window.ready === true", timeout=300000)
        ev = await page.evaluate("window.EVENTS"); dur = await page.evaluate("window.DURATION")
        json.dump({"duration": dur, "events": ev}, open(OUT, "w"), indent=1)
        print(len(ev), "events", dur)
        await b.close()
asyncio.run(main())
