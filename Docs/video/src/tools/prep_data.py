"""Builds web/data/graph.js from the ConstellateKit snapshots in Blender/data/*.json (Orbit Notes sample).

- nodes: everything the snapshot carries (name, kind, role, layer, colours, card width, star glyph/size/glow, preview)
- positions per layout style (+ each style's centre), so the renderer can morph between the six skies
- edges: (from, to, relation) recovered by matching arc end points to node positions (binds arcs are stored in
  flow direction, i.e. reversed), validated by re-running a port of EdgeSceneBuilder.arc() on every style
- fanIn per node recovered from the star size rule (StarEncoder: size = min(0.11, 0.045 + 0.012·log2(1 + fanIn)))
- folder clusters (ClusterBuilder.folderClusters: folders that directly contain a file, members = subtree)
"""
import json
import math
import os
import sys

import numpy as np

SRC = sys.argv[1]
OUT = sys.argv[2]
STYLES = ["celestial", "shells", "sphere", "treeRadial", "wall", "spiral"]

# RelationKind.style (lane, altitude) — ConstellateKit/Graph/RelationKind.swift
REL = {
    "conforms": (-0.62, 0.85), "extends": (0.18, 0.7), "composes": (0.44, 1.0), "presents": (1.22, 1.45),
    "binds": (0.87, 1.15), "creates": (-0.96, 1.25), "delegates": (-0.35, 1.05), "notifies": (-1.31, 1.6),
    "uses": (0.0, 0.55), "imports": (0.0, 0.38), "calls": (-1.1, 1.3),
}


def any_perp(v):
    helper = np.array([0, 1, 0.0]) if abs(v[1]) < 0.9 else np.array([1, 0, 0.0])
    c = np.cross(v, helper)
    return c / np.linalg.norm(c)


def arc(a, b, center, rel, inward=False):
    lane, altitude = REL[rel]
    a = np.asarray(a, np.float64); b = np.asarray(b, np.float64); center = np.asarray(center, np.float64)
    dist = np.linalg.norm(b - a)
    chord = (b - a) / max(dist, 1e-6)
    mid = (a + b) / 2
    out = mid - center
    if np.linalg.norm(out) < 1e-3:
        out = np.array([0, 1, 0.0])
    n0 = out - chord * np.dot(out, chord)
    if np.linalg.norm(n0) < 1e-4:
        up = np.array([0, 1, 0.0])
        n0 = up - chord * np.dot(up, chord)
        if np.linalg.norm(n0) < 1e-4:
            n0 = any_perp(chord)
    n0 = n0 / np.linalg.norm(n0)
    n = n0 * math.cos(lane) + np.cross(chord, n0) * math.sin(lane)
    height = min(1.4, 0.25 * dist + 0.16) * altitude * (-1 if inward else 1)
    control = mid + n * height
    segments = max(10, min(32, int(dist / 0.22) + 8))
    pts = []
    for i in range(segments + 1):
        t = i / segments
        s = 1 - t
        pts.append(a * s * s + control * 2 * s * t + b * t * t)
    return np.array(pts)


snaps = {s: json.load(open(os.path.join(SRC, f"orbitnotes_{s}.json"))) for s in STYLES}
base = snaps["celestial"]
ids = [n["id"] for n in base["nodes"]]
index = {nid: i for i, nid in enumerate(ids)}
for s in STYLES:
    assert [n["id"] for n in snaps[s]["nodes"]] == ids, f"node order differs in {s}"

pos = {s: np.array([n["position"] for n in snaps[s]["nodes"]], np.float64) for s in STYLES}


def find(p, style):
    d = np.linalg.norm(pos[style] - np.asarray(p), axis=1)
    i = int(np.argmin(d))
    return i, float(d[i])


edges = []
worst = 0.0
for arcd in base["arcs"]:
    rel = arcd["relation"]
    p0, p1 = arcd["points"][0], arcd["points"][-1]
    i0, d0 = find(p0, "celestial")
    i1, d1 = find(p1, "celestial")
    worst = max(worst, d0, d1)
    if rel == "binds":
        frm, to = i1, i0
    else:
        frm, to = i0, i1
    edges.append({"from": frm, "to": to, "rel": rel})
print("endpoint match worst distance", worst)

# Validate the arc port on every style (same edge order is not guaranteed; match by endpoints).
for s in STYLES:
    snap = snaps[s]
    center = snap["center"]
    errs = []
    by_end = {}
    for arcd in snap["arcs"]:
        if arcd["relation"] == "contains":
            continue
        key = (arcd["relation"], tuple(np.round(arcd["points"][0], 4)), tuple(np.round(arcd["points"][-1], 4)))
        by_end[key] = np.array(arcd["points"])
    for e in edges:
        if e["rel"] == "contains":
            continue
        a, b = pos[s][e["from"]], pos[s][e["to"]]
        if np.linalg.norm(a - b) <= 0.02:
            continue
        pts = arc(a, b, center, e["rel"])
        if e["rel"] == "binds":
            pts = pts[::-1]
        key = (e["rel"], tuple(np.round(pts[0], 4)), tuple(np.round(pts[-1], 4)))
        ref = by_end.get(key)
        if ref is None or len(ref) != len(pts):
            errs.append(9.9)
            continue
        errs.append(float(np.abs(ref - pts).max()))
    print(f"{s}: arcs {len(snap['arcs'])}, recomputed {len(errs)}, max err {max(errs):.2e}, misses {sum(1 for x in errs if x > 1)}")

# fan-in from star size
nodes = []
for i, n in enumerate(base["nodes"]):
    fan = 0
    if n["kind"] not in ("module", "folder"):
        size = n["starSize"]
        if size < 0.11 - 1e-6:
            fan = int(round(2 ** ((size - 0.045) / 0.012) - 1))
        else:
            fan = -1  # capped
    parent = None
    if "#" in n["id"]:
        parent = n["id"].split("#")[0]
    elif "/" in n["id"]:
        parent = n["id"].rsplit("/", 1)[0]
    nodes.append({
        "id": n["id"], "name": n["name"], "kind": n["kind"], "role": n.get("role"), "layer": n["layer"],
        "layerColor": n["layerColor"], "starColor": n["starColor"], "starSize": n["starSize"], "starGlow": n["starGlow"],
        "glyph": n["glyph"], "cardWidth": n["cardWidth"], "recency": n["recency"], "preview": n["preview"],
        "parent": index.get(parent) if parent else None, "fanIn": fan,
    })

# folder clusters
children = {}
for i, n in enumerate(nodes):
    if n["parent"] is not None:
        children.setdefault(n["parent"], []).append(i)


def subtree(i):
    out = [i]
    for c in children.get(i, []):
        out += subtree(c)
    return out


clusters = []
for i, n in enumerate(nodes):
    if n["kind"] in ("folder", "module") and any(nodes[c]["kind"] == "file" for c in children.get(i, [])):
        members = subtree(i)
        clusters.append({"anchor": i, "title": n["name"], "members": members})
clusters.sort(key=lambda c: nodes[c["anchor"]]["id"])
print("folder clusters", len(clusters), [c["title"] for c in clusters])

# file clusters (app default granularity)
file_clusters = [{"anchor": i, "title": n["name"], "members": subtree(i)} for i, n in enumerate(nodes) if n["kind"] == "file"]

data = {
    "project": base["project"],
    "styles": STYLES,
    "centers": {s: snaps[s]["center"] for s in STYLES},
    "positions": {s: [[round(float(v), 5) for v in p] for p in pos[s]] for s in STYLES},
    "nodes": nodes,
    "edges": edges,
    "legend": base["legend"],
    "roles": base["roles"],
    "folderClusters": clusters,
    "fileClusters": file_clusters,
}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write("window.GRAPH = " + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + ";\n")
print("wrote", OUT, os.path.getsize(OUT), "bytes;", len(nodes), "nodes,", len(edges), "edges")
from collections import Counter
print(Counter(e["rel"] for e in edges))
print("fanIn top", sorted([(n["fanIn"], n["name"]) for n in nodes], reverse=True)[:12])
