"""Bundles the lucide icons the director pages use into web/data/icons.js (window.ICONS = {name: svg}).

Lucide stands in for SF Symbols (not redistributable); each name maps to the closest SF Symbol used by the app.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "web/node_modules/lucide-static/icons"
NAMES = """folder globe circle-dot orbit network grid-3x3 tornado slash crosshair waypoints list palette footprints user-plus mic
volume-2 message-square-text search chevron-right chevron-down package file-text box puzzle sparkles list-checks
square-arrow-out-up-right siren circle-dot-dashed app-window hash clock tag share circle-x eye eye-off check layers panel-left
radio-tower hand arrow-left-right scan-eye chevron-left x pin monitor video phone-off screen-share users mouse download house
hard-drive cloud chevrons-up-down circle-check scan text-cursor mouse-pointer-2 move zoom-in mic-off square-check-big
layout-grid chevron-up arrow-up-right volume-x""".split()

icons = {}
for n in NAMES:
    svg = (SRC / f"{n}.svg").read_text()
    svg = re.sub(r"<!--.*?-->", "", svg, flags=re.S)
    svg = re.sub(r'\s*class="[^"]*"', "", svg)
    svg = re.sub(r'width="24"', 'width="1em"', svg, count=1)
    svg = re.sub(r'height="24"', 'height="1em"', svg, count=1)
    svg = svg.replace('stroke-width="2"', 'stroke-width="1.75"')
    icons[n] = " ".join(svg.split())
(ROOT / "web/data/icons.js").write_text("window.ICONS = " + json.dumps(icons) + ";\n")
print(len(icons), "icons")
