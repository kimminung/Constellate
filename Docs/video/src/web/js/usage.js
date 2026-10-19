// How-to film director. The UI is a replica of Constellate's macOS SplitDashboard (NavigatorView | ConstellationViewport +
// HostHUDView | InspectorView) built from the SwiftUI source; the viewport is the same three.js scene as the intro, fed with
// the app's OrbitNotes sample data. Every frame is a pure function of t (seconds), keyed to the narration timeline (window.TL).
import * as THREE from 'three';
import { Constellation, ease, easeInOut, easeOut } from './engine.js';
import { REL, LAYOUT, DARK, PRESETS, LEGEND_ORDER, ROLE, RELATION_MODE, LAYER_COLOR, CODE_PALETTE, hsl, hex, rgbOfHex } from './theme.js';
import { tokenize } from './cards.js';

const TL = window.TL, G = window.GRAPH, IC = window.ICONS;
const Q = new URLSearchParams(location.search);
const V = (x, y, z) => new THREE.Vector3(x, y, z);
const clamp01 = (x) => Math.max(0, Math.min(1, x));
const lerp = (a, b, k) => a + (b - a) * k;
const line = (id) => TL.lines.find((l) => l.id === id);
const S = (id) => line(id).start, E = (id) => line(id).end;
/** time just before the first ASR token of line `id` whose running text contains `frag` */
function W(id, frag) {
  const l = line(id); let acc = '';
  for (const w of l.words) { acc += w.w; if (acc.replace(/\s/g, '').includes(frag.replace(/\s/g, ''))) return w.t - 0.12; }
  const i = l.cap.indexOf(frag); return l.start + (i < 0 ? 0 : i / l.cap.length * l.dur);
}
function win(t, a, b, fi = 0.25, fo = 0.25) { if (t <= a || t >= b) return 0; return Math.min(ease((t - a) / fi), ease((b - t) / fo)); }
const ramp = (t, a, d) => clamp01((t - a) / d);
const icon = (n) => IC[n] || '';
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
for (const el of document.querySelectorAll('[data-ic]')) el.innerHTML = icon(el.dataset.ic);

// ------------------------------------------------------------------------------------------------------------
// geometry of the replica (stage px; the window sits at 80,24)
const WX = 80, WY = 24;
const CX = 332, CY = 70, VW = 1024, VH = 830;          // content column (viewport) in window coords
const IX = 1356, IY = 70, IW = 404, IH = 830;          // inspector column

const canvas = document.getElementById('c');
canvas.width = VW; canvas.height = VH;
await document.fonts.load('600 44px Pretendard'); await document.fonts.load('700 30px Pretendard'); await document.fonts.load('500 17px Pretendard');
const eng = new Constellation(canvas, VW, VH);
await eng.load(G, 'assets/');
const graph = eng.graph, N = graph.nodes.length;
const idOf = (suffix) => graph.nodes.findIndex((n) => n.id.endsWith(suffix));
const byId = (id) => graph.nodes.findIndex((n) => n.id === id);

const nListFile = byId('OrbitNotes/Features/Notes/Views/NotesListView.swift');
const nListType = idOf('NotesListView.swift#NotesListView');
const nDetail = idOf('NoteDetailView.swift#NoteDetailView');
const atState = [nDetail, ...['NoteEditorView.swift#NoteEditorView', 'NotesListView.swift#NotesListView', 'SearchView.swift#SearchView', 'SyncSettingsView.swift#SyncSettingsView'].map(idOf)];
const nApp = idOf('App/OrbitNotesApp.swift#OrbitNotesApp');
const root = graph.nodes.findIndex((n) => n.kind === 'module');
const viewsCluster = eng.clusters.findIndex((c) => graph.nodes[c.anchor].id === 'OrbitNotes/Features/Notes/Views');

// sample facts (ConstellateKit/Sample/SampleGraph.swift): line counts, days before 2026-10-01, sources
const fmtDate = (days) => { const d = new Date(Date.UTC(2026, 9, 1) - days * 86400000); return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }); };
const SRC = {
  [nListFile]: `//  NotesListView.swift
//  OrbitNotes

import SwiftUI
import Domain

struct NotesListView: View {
    @State var viewModel: NotesListViewModel
    @Environment var router: AppRouter
    @State var searchText: String = ""
    var body: some View {
        List(viewModel.notes) { note in
            NoteRowView(note: note)
        }
        .task { await viewModel.load() }
    }

    func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            Task { try? await viewModel.delete(viewModel.notes[index]) }
        }
    }
}`,
  [nDetail]: `struct NoteDetailView: View {
    let note: Note
    @State var isEditing: Bool = false
    var body: some View {
        VStack {
            Text("NoteDetailView")
        }
    }

    func toggleArchive() async {
        try? await ArchiveNoteUseCase(repository: repository)(note, archived: !note.isArchived)
    }
}`,
  [nApp]: `@main
struct OrbitNotesApp: App {
    @State var environment: AppEnvironment
    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environment(environment)
        }
    }

    func init() {
        _environment = State(initialValue: .makeDefault())
    }
}`,
};
const META = {
  [nListFile]: { lines: [1, 184], days: 1, tags: ['@Environment', '@State', 'SwiftUI.View', 'imports:SwiftUI'] },
  [nDetail]: { lines: [7, 131], days: 4, tags: ['@State', 'SwiftUI.View', 'async', 'struct'] },
  [nApp]: { lines: [6, 41], days: 2, tags: ['@State', 'SwiftUI.App', 'entry-point', 'struct'] },
};
const fileLines = (i) => { const n = graph.nodes[i]; return n.kind === 'file' ? n.lineCount : 0; };
const subtreeFiles = (i) => graph.subtree(i).filter((k) => graph.nodes[k].kind === 'file');

// tour (ConstellateKit/Tour/TourBuilder.swift): entry point, then the largest root-level folders
const rootFolders = (graph.children[root] || []).filter((k) => graph.nodes[k].kind === 'folder' && graph.nodes[k].layer !== 'test')
  .map((k) => ({ k, lines: subtreeFiles(k).reduce((s, f) => s + fileLines(f), 0) })).sort((a, b) => b.lines - a.lines || graph.nodes[a.k].name.localeCompare(graph.nodes[b.k].name));
const nStep2 = rootFolders[0].k;
const step2Files = subtreeFiles(nStep2);
META[nStep2] = { days: 1 }; // newest file inside (NotesListView.swift, 1 day)
META[root] = { days: 1 };
const folderListing = (i) => { const n = graph.nodes[i]; const ks = graph.children[i] || [];
  return [`// ${n.id}`, `// ${n.kind === 'module' ? 'Module' : 'Folder'} ${n.name}: ${ks.length} items`, ...ks.slice(0, 9).map((k) => `//   ├─ ${graph.nodes[k].name}`)].join('\n'); };
const TOUR = [
  { node: nApp, title: 'Entry point: OrbitNotesApp', nar: 'OrbitNotesApp is the app’s entry point, marked @main — everything starts here.' },
  { node: nStep2, title: `${graph.nodes[nStep2].name}/`, nar: `The ${graph.nodes[nStep2].name} folder holds ${step2Files.length} files and ${step2Files.reduce((s, f) => s + fileLines(f), 0)} lines, mostly presentation (UI) code.` },
];

// participants (SessionCoordinator demo names; accent = theme.avatarAccent shifted by 47° per member)
const accentOf = (k) => { const [r, g, b] = rgbOfHex(DARK.avatarAccent); const mx = Math.max(r, g, b), mn = Math.min(r, g, b); const l = (mx + mn) / 2; const d = mx - mn;
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1)); let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h *= 60; return hex(hsl(h + k * 47, Math.min(1, s), l)); };
const PEOPLE = [{ name: 'Coulson', short: 'C', color: accentOf(0), host: true }, { name: 'Mina', short: 'M', color: accentOf(1) }, { name: 'Jae', short: 'J', color: accentOf(2) }, { name: 'Sora', short: 'S', color: accentOf(3) }];

// ------------------------------------------------------------------------------------------------------------
// keyframed tracks: seg(track, t0, t1, value, fn) — a value (number, array or function of t) eased in over [t0, t1]
// Segments are applied in start order, each blending from whatever the track was doing when it began (so overlapping
// moves stay continuous and the latest one wins).
const TRACKS = {};
function track(name, v0) { TRACKS[name] = { v0, segs: [], sorted: true }; }
function seg(name, t0, t1, v, fn = easeInOut) { const tr = TRACKS[name]; tr.segs.push({ t0, t1, v, fn }); tr.sorted = false; }
const resolve = (v, t) => (typeof v === 'function' ? v(t) : v);
const mix = (a, b, k) => (Array.isArray(a) ? a.map((x, i) => lerp(x, b[i], k)) : lerp(a, b, k));
function val(name, t) {
  const tr = TRACKS[name];
  if (!tr.sorted) { tr.segs.sort((a, b) => a.t0 - b.t0); tr.sorted = true; }
  let v = resolve(tr.v0, t);
  for (const s of tr.segs) {
    if (t < s.t0) break;
    const k = t >= s.t1 ? 1 : s.fn(clamp01((t - s.t0) / Math.max(1e-6, s.t1 - s.t0)));
    v = k >= 1 ? resolve(s.v, t) : mix(v, resolve(s.v, t), k);
  }
  return v;
}
// discrete states: step(name, t, value)
const STEPS = {};
function step(name, t, v) { (STEPS[name] = STEPS[name] || []).push({ t, v }); STEPS[name].sort((a, b) => a.t - b.t); }
function at(name, t, dflt = null) { let v = dflt; for (const s of STEPS[name] || []) { if (t >= s.t) v = s.v; else break; } return v; }
function since(name, t) { let ts = -1e9; for (const s of STEPS[name] || []) { if (t >= s.t) ts = s.t; else break; } return t - ts; }

// ------------------------------------------------------------------------------------------------------------
// scene helpers: layout / dial / camera at t
const LAYOUTS = ['celestial', 'shells', 'sphere', 'treeRadial', 'wall', 'spiral']; // LayoutStyle.allCases (⌃⌘1–6)
const LSYM = { celestial: 'globe', shells: 'circle-dot', sphere: 'orbit', treeRadial: 'network', wall: 'grid-3x3', spiral: 'tornado' };
const MSYM = { off: 'slash', focus: 'crosshair', all: 'waypoints' };
const MORPHS = []; // {t0, t1, a, b}
function morph(t0, t1, a, b) { MORPHS.push({ t0, t1, a, b }); }
function layoutAt(t) {
  let L = { a: 'celestial', b: 'celestial', m: 0 };
  for (const m of MORPHS) { if (t < m.t0) break; L = t < m.t1 ? { a: m.a, b: m.b, m: easeInOut((t - m.t0) / (m.t1 - m.t0)) } : { a: m.b, b: m.b, m: 0 }; }
  return L;
}
const styleAt = (t) => { const L = layoutAt(t); return L.m > 0 ? L.b : L.a; };
// bounding spheres (ConstellationViewport.rebuild: distance = max(4, r × 1.45), target y clamped to 1…2.4)
const BOUND = {};
for (const s of LAYOUTS) {
  const P = G.positions[s]; const lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
  for (const p of P) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], p[k]); hi[k] = Math.max(hi[k], p[k]); }
  const c = lo.map((v, k) => (v + hi[k]) / 2); let r = 0; for (const p of P) r = Math.max(r, Math.hypot(p[0] - c[0], p[1] - c[1], p[2] - c[2]));
  BOUND[s] = { c, r, dist: Math.min(14, Math.max(4, r * 1.45)), tgt: [c[0], Math.min(Math.max(c[1], 1.0), 2.4), c[2]] };
}
track('dial', 0);
const dialAt = (t) => val('dial', t);
const tmpV = new THREE.Vector3();
function nodePos(i, t) { return eng.position(i, layoutAt(t), dialAt(t), new THREE.Vector3()).clone(); }
const nodeArr = (i) => (t) => nodePos(i, t).toArray();
function clusterCenter(ci, t) { const c = eng.clusters[ci]; const v = V(0, 0, 0); for (const m of c.members) v.add(nodePos(m, t)); return v.divideScalar(c.members.length); }

// OrbitCameraRig: yaw / pitch / distance around an eased target, FOV 58°
track('yaw', 0.55); track('pitch', 0.22); track('dist', BOUND.celestial.dist); track('tgt', BOUND.celestial.tgt);
function camAt(t) {
  const yaw = val('yaw', t), pitch = val('pitch', t), dist = val('dist', t), tg = val('tgt', t);
  const target = V(tg[0], tg[1], tg[2]);
  const pos = target.clone().add(V(dist * Math.cos(pitch) * Math.sin(yaw), dist * Math.sin(pitch), dist * Math.cos(pitch) * Math.cos(yaw)));
  return { pos, target, fov: 58 };
}
const probe = new THREE.PerspectiveCamera(58, VW / VH, 0.05, 140);
/** stage px of a world point as seen by the window viewport at time t */
function screenOf(p, t) {
  const c = camAt(t); probe.fov = c.fov; probe.aspect = VW / VH; probe.updateProjectionMatrix(); probe.position.copy(c.pos); probe.lookAt(c.target); probe.updateMatrixWorld();
  const v = p.clone().project(probe); return [WX + CX + (v.x + 1) / 2 * VW, WY + CY + (1 - v.y) / 2 * VH];
}
/** viewer pose → point `d` m ahead (horizontal forward), `drop` below (ConstellationSceneController.ViewerPose.ahead) */
function ahead(t, d, drop) { const c = camAt(t); const f = c.target.clone().sub(c.pos); f.y = 0; f.normalize(); return c.pos.clone().addScaledVector(f, d).add(V(0, -drop, 0)); }
/** camera ray through a stage point at time t → point at distance of `anchor` (pointer fallback plane) */
function rayHit(px, py, t, anchor) {
  const c = camAt(t); probe.position.copy(c.pos); probe.lookAt(c.target); probe.updateMatrixWorld(); probe.fov = 58; probe.aspect = VW / VH; probe.updateProjectionMatrix();
  const ndc = V(((px - WX - CX) / VW) * 2 - 1, 1 - ((py - WY - CY) / VH) * 2, 0.5).unproject(probe);
  const dir = ndc.sub(c.pos).normalize(); const n = c.pos.clone().sub(c.target).normalize();
  const den = dir.dot(n.clone().negate()); const d = anchor.clone().sub(c.pos).dot(n.clone().negate()) / Math.max(1e-4, den);
  return { origin: c.pos.clone(), dir, hit: c.pos.clone().addScaledVector(dir, d) };
}

// ------------------------------------------------------------------------------------------------------------
// static UI: toolbar, menus, legend, panels
const el = {
  cam: $('#cam'), win: $('#win'), toolbar: $('#toolbar'), outline: $('#outline'), search: $('#sidebar .search'), content: $('#content'), toast: $('#toast'),
  plbl: $('#pointerlbl'), hud: $('#hud'), tour: $('#tourbar'), insp: $('#insp'), menus: $('#menus'), sheet: $('#sheet'), ft: $('#facetime'), rings: $('#rings'),
  cursor: $('#cursor'), press: $('#cursor .press'), vision: $('#vision'), vroom: $('#vroom'), gaze: $('#vroom .gaze'), pinch: $('#vroom .pinch'), full: $('#fullhost'),
  host: $('#canvashost'), voice: $('#voicecap'), vtxt: $('#voicecap .txt'), keycaps: $('#keycaps'), keys: $('#keycaps .keys'), klbl: $('#keycaps .lbl'),
  chapter: $('#chapter'), cap: $('#caption span'), capband: $('#capband'), title: $('#titlecard'), end: $('#endcard'), black: $('#black'),
};
el.toolbar.innerHTML = `
  <div class="tb" id="tb-open">${icon('folder')}</div>
  <div class="tb txt" id="tb-gran">Folder<span class="sm">${icon('chevrons-up-down')}</span></div>
  <div class="tb" id="tb-layout"><span class="li">${icon('globe')}</span><span class="sm">${icon('chevron-down')}</span></div>
  <div class="tb" id="tb-rel"><span class="li">${icon('waypoints')}</span></div>
  <div class="tb" id="tb-legend">${icon('list')}</div>
  <div class="tb" id="tb-theme">${icon('palette')}<span class="sm">${icon('chevron-down')}</span></div>
  <div class="tb" id="tb-tour">${icon('footprints')}</div>
  <div class="tb" id="tb-member">${icon('user-plus')}<i class="badge">1</i></div>
  <div class="tb" id="tb-mic">${icon('mic')}</div>`;
const tb = Object.fromEntries([...el.toolbar.querySelectorAll('.tb')].map((d) => [d.id.slice(3), d]));
const tip = document.createElement('div'); tip.className = 'tip'; el.win.appendChild(tip);

/** element rect in stage coordinates (layout space, ignores the #cam zoom and #insp scroll transforms) */
function rect(e) { let x = 0, y = 0; let n = e; while (n && n !== el.cam) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; } return { x, y, w: e.offsetWidth, h: e.offsetHeight, cx: x + e.offsetWidth / 2, cy: y + e.offsetHeight / 2 }; }
const ctr = (e, dx = 0, dy = 0) => { const r = rect(e); return [r.cx + dx, r.cy + dy]; };

// menus (positioned under their toolbar buttons)
function menuAt(btn, html, cls = '') {
  const m = document.createElement('div'); m.className = 'menu ' + cls; m.innerHTML = html; el.menus.appendChild(m);
  const r = rect(btn); m.style.left = (r.x - WX - 8) + 'px'; m.style.top = (r.y + r.h - WY + 8) + 'px';
  return m;
}
// toolbar menus (LayoutStylePicker inline + axes text; Theme picker inline). Shortcuts live in the menu bar, not here.
const layoutMenu = menuAt(tb.layout, LAYOUTS.map((s) => `<div class="mi" data-v="${s}"><span class="ck"></span><span class="mic">${icon(LSYM[s])}</span>${LAYOUT[s].label}</div>`).join('') + '<div class="dv"></div><div class="nt"></div>');
const themeMenu = menuAt(tb.theme, PRESETS.map((p) => `<div class="mi" data-v="${p.name}"><span class="ck"></span>${p.name}</div>`).join(''));
themeMenu.style.minWidth = '200px';
// legend popover (RelationLegendView inside RelationToolbarControl's popover)
const counts = {}; for (const e of graph.edges) if (e.rel !== 'contains') counts[e.rel] = (counts[e.rel] || 0) + 1;
function swatchSVG(color, dashed, flow, w = 50, h = 16, flip = false) {
  const d = dashed ? 'stroke-dasharray="5 4"' : '';
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" style="flex:none;${flip ? 'transform:scaleX(-1)' : ''}"><path d="M1 ${h * 0.75} Q${w / 2} 0 ${w - (flow ? 7 : 1)} ${h * 0.75}" fill="none" stroke="${color}" stroke-width="2.6" stroke-linecap="round" ${d}/>` +
    (flow ? `<path d="M${w - 0.5} ${h * 0.8} L${w - 8} ${h * 0.8 - 6} L${w - 7} ${h * 0.8 + 4} Z" fill="${color}"/>` : '') + '</svg>';
}
const legend = document.createElement('div'); legend.className = 'pop'; el.menus.appendChild(legend);
legend.innerHTML = `<div class="seg">${['off', 'focus', 'all'].map((m) => `<i data-m="${m}">${icon(MSYM[m])}${RELATION_MODE[m]}</i>`).join('')}</div>
<div style="margin-top:10px">${LEGEND_ORDER.map((k) => { const r = REL[k]; return `<div class="lg" data-k="${k}">${swatchSVG(r.color, r.dashed, r.flow)}<div class="tx"><div class="a">${r.ko} · ${r.en}</div><div class="b">${esc(r.hint)}</div></div><span class="n">${counts[k] || 0}</span><span class="e">${icon('eye')}</span></div>`; }).join('')}</div>
<div class="lgf"><span class="ht">Tap a row to hide it · 눌러서 숨기기</span><span class="sa">Show all</span></div>`;
{ const r = rect(tb.legend); legend.style.left = (r.cx - WX - 480 + 70) + 'px'; legend.style.top = (r.y + r.h - WY + 14) + 'px'; legend.style.setProperty('--ax', '61px'); }
const lgRows = Object.fromEntries([...legend.querySelectorAll('.lg')].map((d) => [d.dataset.k, d]));
// open panel (fileImporter) + save panel (fileExporter)
const openPanel = document.createElement('div'); openPanel.className = 'panel'; el.sheet.appendChild(openPanel);
const FOLDERS = [['Constellate', 'Today at 9:41 AM'], ['MyApp', 'Yesterday at 6:12 PM'], ['Playground', 'Oct 12, 2026 at 2:30 PM'], ['Portfolio', 'Sep 28, 2026 at 11:05 AM'], ['SwiftUI Samples', 'Aug 3, 2026 at 4:47 PM']];
openPanel.innerHTML = `<div class="pbar"><span class="nav">${icon('chevron-left')}${icon('chevron-right')}</span><span class="loc">${icon('folder')}Developer<span style="font-size:13px;color:#a3a2ad">${icon('chevrons-up-down')}</span></span><span class="srch">${icon('search')}Search</span></div>
<div class="pbody"><div class="pside"><div class="h">Favorites</div>${[['house', 'coulson'], ['app-window', 'Applications'], ['monitor', 'Desktop'], ['file-text', 'Documents'], ['download', 'Downloads'], ['folder', 'Developer']].map(([i, n]) => `<div class="it ${n === 'Developer' ? 'sel' : ''}"><span>${icon(i)}</span>${n}</div>`).join('')}
<div class="h">Locations</div><div class="it"><span>${icon('cloud')}</span>iCloud Drive</div><div class="it"><span>${icon('hard-drive')}</span>Macintosh HD</div></div>
<div class="plist"><div class="hdr"><span>Name</span><span>Date Modified</span></div>${FOLDERS.map(([n, d]) => `<div class="fr" data-n="${n}"><span class="fi">${icon('folder')}</span>${n}<span class="dt">${d}</span></div>`).join('')}</div></div>
<div class="pfoot"><div class="btn" data-b="cancel">Cancel</div><div class="btn dis" data-b="open">Open</div></div>`;
const savePanel = document.createElement('div'); savePanel.className = 'panel'; savePanel.style.width = '700px'; el.sheet.appendChild(savePanel);
savePanel.innerHTML = `<div class="row2" style="padding-top:22px"><span class="lb">Save As:</span><span class="fld">Review-OrbitNotes-2026-10-19.md</span></div>
<div class="row2"><span class="lb">Tags:</span><span style="flex:1;height:30px"></span></div>
<div class="row2" style="padding-bottom:18px"><span class="lb">Where:</span><span class="pop2">${icon('file-text')}Documents<span style="font-size:13px;color:#a3a2ad">${icon('chevrons-up-down')}</span></span></div>
<div class="pfoot"><div class="btn" data-b="cancel">Cancel</div><div class="btn pri" data-b="save">Save</div></div>`;
// FaceTime / SharePlay (system UI, kept generic)
el.ft.innerHTML = `<div class="fh"><span class="vi">${icon('video')}</span>FaceTime<span class="tm">12:04</span></div>
<div class="tiles">${PEOPLE.slice(1).map((p) => `<div class="tile"><div class="av" style="background:${p.color}">${p.short}</div><span class="nm">${p.name}</span></div>`).join('')}</div>
<div class="sp"><img class="ai" src="assets/img/icon-256.png"><div><div class="tt">Constellate</div><div class="ss">SharePlay · 함께 보기</div></div><div class="btn pri" id="sp-btn">${icon('screen-share')}SharePlay</div></div>
<div class="ctrls"><i>${icon('mic')}</i><i>${icon('video')}</i><i>${icon('screen-share')}</i><i class="end">${icon('phone-off')}</i></div>`;
const spBtn = $('#sp-btn');

// HUD (HostHUDView)
el.hud.innerHTML = `<div class="r1"><div class="glyph"><canvas width="92" height="92"></canvas></div><div class="tx"><div class="st"></div><div class="rp sec"></div></div>
<div class="ctl"><div class="btn" id="undock" style="display:none">Undock · 나와</div><div class="ib onbg">${icon('volume-2')}</div><div class="ib">${icon('message-square-text')}</div>
<div class="dial"><span>Older</span><div class="slider"><div class="trk"></div><div class="fil"></div><div class="kn"></div></div><span>Newer</span></div></div></div>
<div class="r2"><div class="field" id="ask"><span class="ty"></span><i class="caret"></i><span class="ph">Ask the host… ("find views using @State", "explain", "tour")</span></div><div class="btn dis" id="send">Send</div></div>`;
const hud = { st: el.hud.querySelector('.st'), rp: el.hud.querySelector('.rp'), glyph: el.hud.querySelector('.glyph canvas'), undock: $('#undock'), kn: el.hud.querySelector('.kn'),
  fil: el.hud.querySelector('.fil'), slider: el.hud.querySelector('.slider'), ask: $('#ask'), ty: $('#ask .ty'), ph: $('#ask .ph'), caret: $('#ask .caret'), send: $('#send') };
el.tour.innerHTML = `<div class="t1"><span class="walk">${icon('footprints')}</span><span>OrbitNotes overview</span><span class="n"></span><span class="fh" id="fh"><span class="sw"></span>Follow host</span><span class="xx" id="tour-x">${icon('circle-x')}</span></div>
<div class="s1"></div><div class="s2"></div><div class="t3"><div class="btn dis" id="t-prev">${icon('chevron-left')}Prev</div><div class="btn" id="t-next">${icon('chevron-right')}Next</div><span style="flex:1"></span><div class="btn">${icon('square-arrow-out-up-right')}Summon</div></div>`;
const tourEl = { n: el.tour.querySelector('.n'), s1: el.tour.querySelector('.s1'), s2: el.tour.querySelector('.s2'), prev: $('#t-prev'), next: $('#t-next'), fh: $('#fh'), x: $('#tour-x') };

// ------------------------------------------------------------------------------------------------------------
// navigator outline (NavigatorView: 12 pt indent, rows sorted by (kind.order, name), root + its children expanded)
const KORD = { module: 0, folder: 1, file: 2, type: 3, extensionDecl: 3 };
const KICON = { module: 'package', folder: 'folder', file: 'file-text', type: 'box', extensionDecl: 'puzzle' };
const kids = (i) => (graph.children[i] || []).slice().sort((a, b) => (KORD[graph.nodes[a].kind] - KORD[graph.nodes[b].kind]) || (graph.nodes[a].name < graph.nodes[b].name ? -1 : graph.nodes[a].name > graph.nodes[b].name ? 1 : 0));
const baseExpanded = new Set([root, ...kids(root)]);
const ancestors = (i) => { const out = []; let p = graph.nodes[i].parent; while (p !== null && p !== undefined) { out.push(p); p = graph.nodes[p].parent; } return out; };
function outlineRows(expanded) {
  const rows = [];
  const visit = (i, d) => { const ks = kids(i); rows.push({ i, d, has: ks.length > 0 }); if (!expanded.has(i)) return; for (const k of ks) visit(k, d + 1); };
  visit(root, 0); return rows;
}
const lineBadge = (n) => (n.kind === 'file' || n.kind === 'type' || n.kind === 'extensionDecl') ? n.lineCount : 0;
let outlineKey = '';
function renderOutline(sel, revealed, scrollTo) {
  const expanded = new Set(baseExpanded); if (revealed !== null) for (const a of ancestors(revealed)) expanded.add(a);
  const key = [...expanded].sort().join(',') + '|' + sel;
  if (key === outlineKey) return; outlineKey = key;
  const rows = outlineRows(expanded);
  el.outline.innerHTML = `<div class="head">OrbitNotes</div>` + rows.map((r) => {
    const n = graph.nodes[r.i]; const lc = lineBadge(n);
    return `<div class="rw ${r.d >= 3 ? 'compact' : ''} ${r.i === sel ? 'sel' : ''}" data-i="${r.i}" style="padding-left:${10 + r.d * 16}px">` +
      `<span class="cv ${expanded.has(r.i) ? 'open' : ''}">${r.has ? icon('chevron-right') : ''}</span><span class="ki" style="color:${LAYER_COLOR[n.layer] || '#A7ADBF'}">${icon(KICON[n.kind])}</span>` +
      `<span class="nm">${esc(n.name)}</span>${lc ? `<span class="lc">${lc}</span>` : ''}</div>`;
  }).join('');
  if (scrollTo !== null) { const rowEl = el.outline.querySelector(`[data-i="${scrollTo}"]`); if (rowEl) { const y = rowEl.offsetTop - 300; el.outline.scrollTop = Math.max(0, y); } }
  else el.outline.scrollTop = 0;
}

// ------------------------------------------------------------------------------------------------------------
// inspector (InspectorView)
const LAYER_BADGE = (L) => { const c = LAYER_COLOR[L] || '#A7ADBF'; const [r, g, b] = rgbOfHex(c).map((v) => Math.round(v * 255)); return `background:rgba(${r},${g},${b},0.25)`; };
function codeHTML(src) {
  return src.split('\n').map((ln) => tokenize(ln).map(([tx, k]) => `<span style="color:${CODE_PALETTE[k] || CODE_PALETTE.plain}">${esc(tx)}</span>`).join('')).join('\n');
}
function relationGroups(i) { // RelationDigest.groups
  const inside = new Set(graph.subtree(i)); const out = {}, inc = {};
  for (const e of graph.edges) { if (e.rel === 'contains') continue; const fi = inside.has(e.from), ti = inside.has(e.to);
    if (fi && !ti) (out[e.rel] = out[e.rel] || new Set()).add(e.to); if (ti && !fi) (inc[e.rel] = inc[e.rel] || new Set()).add(e.from); }
  const name = (k) => graph.nodes[k].name; const groups = [];
  for (const rel of LEGEND_ORDER) for (const [isOut, tab] of [[true, out], [false, inc]]) {
    const ids = tab[rel]; if (!ids || !ids.size) continue;
    const sorted = [...ids].sort((a, b) => (name(a) < name(b) ? -1 : name(a) > name(b) ? 1 : graph.nodes[a].id < graph.nodes[b].id ? -1 : 1));
    groups.push({ rel, out: isOut, nodes: sorted.slice(0, 12), total: ids.size });
  }
  return groups;
}
const PHRASE = { conforms: ['Conforms to · 채택·상속', 'Adopted by · 채택한 타입'], extends: ['Extends · 확장 대상', 'Extended by · 확장'], composes: ['Embeds · 포함하는 뷰', 'Embedded in · 포함된 곳'],
  presents: ['Presents · 띄우는 화면', 'Presented by · 띄우는 곳'], binds: ['Observes · 관찰하는 상태', 'Observed by · 관찰하는 뷰'], creates: ['Creates · 생성', 'Created by · 생성하는 곳'],
  delegates: ['Delegates to · 델리게이트', 'Delegate of · 위임하는 곳'], notifies: ['Notifies · 알림 보냄', 'Notified by · 알림 받음'], uses: ['Uses · 참조', 'Used by · 참조하는 곳'],
  imports: ['Imports · import', 'Imported by · import하는 곳'], calls: ['Calls · 호출', 'Called by · 호출하는 곳'] };
const ROLE_ICON = { app: 'app-window', view: 'monitor', model: 'box', viewModel: 'layers', service: 'sparkles', test: 'list-checks', extension: 'puzzle' };
const rgbaOf = (c, a) => { const [r, g, b] = rgbOfHex(c).map((v) => Math.round(v * 255)); return `rgba(${r},${g},${b},${a})`; };
function inspectorHTML(i, o) {
  if (i === null) return `<div class="empty"><div class="ei">${icon('layers')}</div><div class="et">Select a card</div><div class="ed">Tap a code card in the constellation or pick a node in the navigator.</div></div>`;
  const n = graph.nodes[i]; const meta = META[i] || {}; const m = graph.metrics(i);
  const role = n.role ? ROLE[n.role] : null;
  const lines = meta.lines ? `L${meta.lines[0]}–${meta.lines[1]} · ${meta.lines[1] - meta.lines[0] + 1} lines` : (lineBadge(n) ? `${n.lineCount} lines` : '');
  const days = meta.days ?? null;
  let h = `<div class="ih"><span class="ki">${icon(KICON[n.kind])}</span><span>${esc(n.name)}</span></div>
<div class="badges"><span class="cap" style="${LAYER_BADGE(n.layer)}">${n.layer}</span>${role && role.label ? `<span class="cap" id="i-role" style="color:${role.color};background:${rgbaOf(role.color, 0.16)}">${icon(ROLE_ICON[n.role] || 'box')}${role.label}</span>` : ''}<span class="cap plain">${icon('tag')}${n.kind}</span></div>
<div class="path">${esc(n.id.split('#')[0])}</div>
<div class="meta">${lines ? `<span>${icon('hash')}${lines}</span>` : ''}${days !== null ? `<span>${icon('clock')}${fmtDate(days)}</span>` : ''}</div>
${meta.tags ? `<div class="tags">${meta.tags.map((x) => `<i>${esc(x)}</i>`).join('')}</div>` : ''}
<div class="code">${codeHTML(SRC[i] || (n.kind === 'folder' || n.kind === 'module' ? folderListing(i) : n.preview.join('\n')))}</div>`;
  if (n.kind === 'folder' || n.kind === 'file' || n.kind === 'module') {
    const inner = graph.subtree(i).filter((k) => k !== i && graph.nodes[k].kind !== 'folder').map((k) => ({ k, f: graph.nodes[k].fanIn || 0 })).filter((x) => x.f > 0).sort((a, b) => b.f - a.f).slice(0, 3);
    h += `<div class="sec" id="i-hubs"><div class="hd">Most referenced · 허브</div>${inner.length ? inner.map((x) => `<div class="hub"><span style="color:${LAYER_COLOR[graph.nodes[x.k].layer]}">${icon(KICON[graph.nodes[x.k].kind])}</span>${esc(graph.nodes[x.k].name)}<span class="n">${x.f} refs</span></div>`).join('') : '<div class="hub" style="font-size:13.5px;color:#a3a2ad">Nothing inside is referenced yet.</div>'}</div>`;
  }
  if (n.kind !== 'folder' && n.kind !== 'module' && m) {
    h += `<div class="sec" id="i-coupling"><div class="hd">Coupling · 결합도</div><div class="grid">
<div><div class="v">${m.fanIn}</div><div class="l">Fan-in · 의존받음</div></div><div><div class="v">${m.fanOut}</div><div class="l">Fan-out · 의존함</div></div>
<div><div class="v">${m.instability === null ? '–' : m.instability.toFixed(2)}</div><div class="l">Instability · 불안정도</div></div><div><div class="v">${m.impact}</div><div class="l">Impact · 영향 범위</div></div></div></div>`;
  }
  const groups = relationGroups(i);
  h += `<div class="sec" id="i-rel"><div class="hd">Relations · 관계<span class="r">${icon(MSYM[o.mode])}${RELATION_MODE[o.mode]}</span></div>` +
    (groups.length ? groups.map((g) => { const r = REL[g.rel]; const hidden = o.hidden.has(g.rel);
      return `<div class="rg" style="opacity:${hidden ? 0.6 : 1}"><div class="gh">${swatchSVG(r.color, r.dashed, r.flow, 34, 12, !g.out)}<span>${PHRASE[g.rel][g.out ? 0 : 1]}</span>${hidden ? `<span class="hid">${icon('eye-off')}</span>` : ''}<span class="n">${g.total}</span></div>
<div class="chips">${g.nodes.map((k) => `<i style="background:${rgbaOf(r.color, 0.16)}">${esc(graph.nodes[k].name)}</i>`).join('')}${g.total > g.nodes.length ? `<i style="background:rgba(255,255,255,0.08)">+${g.total - g.nodes.length}</i>` : ''}</div></div>`; }).join('')
      : '<div style="font-size:13.5px;color:#a3a2ad;margin-top:8px">No relations leave this node.</div>') + '</div>';
  const pins = o.pins.filter((p) => p.node === i);
  h += `<div class="sec" id="i-pins"><div class="hd">Review pins · 핀${o.pins.length ? `<span class="r"><span class="btn" id="i-export" style="height:26px;font-size:13px;padding:0 10px">${icon('share')}Export pins</span></span>` : ''}</div>
${pins.map((p) => `<div class="pinrow"><span class="pc">${icon('circle-dot')}</span><div><div class="pt">${esc(p.text)}</div><div class="pm">${p.author} · ${p.time}</div></div></div>`).join('')}
<div class="pinin"><div class="field ${o.pinFocus ? 'focus' : ''}" id="i-pinfield">${o.pinText ? `<span class="ty">${esc(o.pinText)}</span><i class="caret" style="opacity:${o.caret}"></i>` : `<i class="caret" style="opacity:${o.pinFocus ? o.caret : 0}"></i><span class="ph">Add a review comment…</span>`}</div><div class="btn ${o.pinText ? '' : 'dis'}" id="i-pinbtn">Pin</div></div></div>`;
  h += `<div class="acts"><div class="btn"><span>${icon('sparkles')}</span>Ask host · 설명</div><div class="btn"><span>${icon('list-checks')}</span>Review</div>
<div class="btn"><span>${icon('square-arrow-out-up-right')}</span>Summon · 출두</div><div class="btn"><span>${icon('siren')}</span>Beacon</div>
<div class="btn"><span>${icon('circle-dot-dashed')}</span>${o.docked ? 'Undock' : 'Dock host'}</div><div class="btn"><span>${icon('app-window')}</span>Open in window</div></div>`;
  return h;
}
let inspKey = '';
function renderInspector(i, o) {
  const key = JSON.stringify([i, o.mode, [...o.hidden].sort(), o.pins, o.pinText, o.pinFocus, Math.round(o.caret), o.docked]);
  if (key !== inspKey) { inspKey = key; el.insp.innerHTML = inspectorHTML(i, o); }
}
/** measure an inspector element (stage coords, before scrolling) for node i */
const inspMeasure = {};
function measureInspector(i, withPin) {
  el.insp.innerHTML = inspectorHTML(i, { mode: 'all', hidden: new Set(['uses', 'imports']), pins: withPin ? [{ node: i, text: 'isEditing은 ViewModel로 옮기기', author: 'Coulson', time: '3:42 PM' }] : [], pinText: '', pinFocus: false, caret: 0, docked: false });
  const r = (id) => { const e = el.insp.querySelector('#' + id); return e ? rect(e) : null; };
  inspKey = '';
  return { role: r('i-role'), coupling: r('i-coupling'), rel: r('i-rel'), pins: r('i-pins'), field: r('i-pinfield'), pinbtn: r('i-pinbtn'), exp: r('i-export'), hubs: r('i-hubs'), h: el.insp.offsetHeight };
}
inspMeasure[nListFile] = measureInspector(nListFile, false);
inspMeasure[nDetail] = measureInspector(nDetail, false);
inspMeasure.detailPinned = measureInspector(nDetail, true);

// ------------------------------------------------------------------------------------------------------------
// cursor + clicks + cues
track('cur', [960, 520]);
const CLICKS = []; const click = (t) => CLICKS.push(t);
const HOLDS = []; const hold = (t0, t1, kind = 'drag') => HOLDS.push([t0, t1, kind]);
const curTo = (t0, t1, p, fn = easeInOut) => seg('cur', t0, t1, p, fn);
const curAt = (t) => val('cur', t);
/** stage → layout point for 3-D targets (follows the camera while it moves) */
const follow3D = (fnPos, dx = 0, dy = 0) => (t) => { const s = screenOf(fnPos(t), t); return [s[0] + dx, s[1] + dy]; };
const EVENTS = []; const ev = (t, kind, i = 0) => EVENTS.push({ t: +t.toFixed(3), kind, i });
const KEYS = []; // {t0, t1, keys:[...], press:[times], label, or}
const keycap = (t0, t1, keys, press = [], label = '', or = false) => { KEYS.push({ t0, t1, keys, press, label, or }); for (const p of press) ev(p, 'key'); };
const GEST = []; const gesture = (t0, t1, ic, label) => GEST.push({ t0, t1, ic, label });
const RINGS = []; const ring = (t0, t1, r, pad = 6) => RINGS.push({ t0, t1, r, pad });
const TAGS = []; const tag3 = (t0, t1, text, at, color = '#FFD166') => TAGS.push({ t0, t1, text, at, color });
track('zoom', [960, 540, 1]);
const zoomTo = (t0, t1, cx, cy, s) => seg('zoom', t0, t1, [cx, cy, s]);
const CHAPTERS = [
  ['u02', '01', '프로젝트 열기', 'Open a project'], ['u04', '02', '둘러보기', 'Navigate'], ['u06', '03', '배치', 'Layouts'], ['u07', '04', '관계', 'Relations'],
  ['u09', '05', '카드 살펴보기', 'Inspect a card'], ['u10', '06', '타임 다이얼', 'Time dial'], ['u11', '07', '호스트에게 묻기', 'Ask the host'], ['u14', '08', '음성', 'Voice'],
  ['u15', '09', '회의', 'Meetings'], ['u17', '10', '투어', 'Guided tour'], ['u18', '11', '테마', 'Themes'],
];
const chStart = (k) => S(CHAPTERS[k][0]) - 0.6;

const T = {}; // named cue times
// ---- intro / ch1: open a project
T.cursorIn = 5.5;
curTo(0, 0.01, [900, 560]);
const pOpen = ctr(tb.open);
curTo(6.25, 7.35, pOpen); T.openClick = W('u02', '버튼'); click(T.openClick); ev(T.openClick, 'click');
T.panelIn = T.openClick + 0.12; ev(T.panelIn, 'sheet');
keycap(W('u02', '커맨드') - 0.05, W('u02', '프로젝트') + 0.75, ['⌘', 'O'], [], 'Open Project…', true);
const rowMy = openPanel.querySelector('[data-n="MyApp"]');
// openPanel is centred via translateX(-50%): measure after layout
const panelRect = () => { const r = rect(openPanel); return r; };
T.rowClick = W('u02', '폴더를') - 0.05;
curTo(T.panelIn + 0.5, T.rowClick - 0.1, () => { const r = rect(rowMy); const pr = rect(openPanel); return [r.cx - pr.w / 2 - 60, r.cy]; });
click(T.rowClick); ev(T.rowClick, 'click');
const btnCancel = openPanel.querySelector('[data-b="cancel"]');
T.cancel = S('u03') - 0.45;
curTo(T.rowClick + 0.45, T.cancel - 0.08, () => { const r = rect(btnCancel); const pr = rect(openPanel); return [r.cx - pr.w / 2, r.cy]; });
click(T.cancel); ev(T.cancel, 'click');
T.panelOut = T.cancel + 0.06;
// sample callout on the navigator
T.sample0 = W('u03', '샘플') - 0.1; T.sample1 = E('u03') + 0.2;
const pHead = () => { const h = el.outline.querySelector('.head'), r0 = el.outline.querySelector(`[data-i="${root}"]`); if (!h || !r0) return { x: 96, y: 150, w: 280, h: 60 };
  const a = rect(h), b = rect(r0); return { x: a.x, y: a.y, w: Math.max(a.w, b.w), h: b.y + b.h - a.y }; };
curTo(T.cancel + 0.35, T.sample0 + 0.4, [300, 330]);

// ---- ch2: drag / scroll / pinch, then visionOS
T.drag0 = W('u04', '드래그'); T.drag1 = W('u04', '스크롤') - 0.15;
const pDrag = [820, 430];
curTo(T.sample1 - 0.3, T.drag0 - 0.05, pDrag);
hold(T.drag0, T.drag1);
curTo(T.drag0 + 0.1, T.drag1, [pDrag[0] + 120, pDrag[1] + 14]);
gesture(T.drag0, T.drag1 + 0.1, 'mouse', '드래그 · Drag');
seg('yaw', T.drag0 + 0.1, T.drag1, 0.55 - 120 * 0.006); seg('pitch', T.drag0 + 0.1, T.drag1, 0.22 + 14 * 0.005);
T.scroll0 = W('u04', '스크롤'); T.pinch0 = W('u04', '핀치');
gesture(T.scroll0, T.pinch0 + 0.05, 'mouse', '스크롤 · Scroll');
seg('dist', T.scroll0 + 0.05, T.pinch0, 8.6, easeOut);
gesture(T.pinch0 + 0.05, E('u04') + 0.1, 'move', '핀치 · Pinch');
seg('dist', T.pinch0 + 0.15, E('u04') - 0.1, 6.8);
ev(T.drag0, 'drag'); ev(T.scroll0, 'scroll'); ev(T.pinch0, 'scroll', 1);
// visionOS (real dashboard screenshot) → Enter Constellation → immersive full frame
T.v0 = S('u05') - 0.6; T.gaze = W('u05', '입장'); T.pinchV = W('u05', '누르면') + 0.05; T.imm0 = T.pinchV + 0.25; T.imm1 = S('u06') - 0.55;
ev(T.v0, 'whoosh'); ev(T.pinchV, 'tap'); ev(T.imm0, 'immersive');
const VBTN = { x: 642, y: 478, w: 192, h: 30, cx: 738, cy: 493 };

// ---- ch3: layout menu + ⌃⌘ shortcuts
T.lay0 = T.imm1 - 0.3;
const pLayout = ctr(tb.layout);
curTo(T.lay0, S('u06') + 0.42, pLayout); T.layClick = S('u06') + 0.55; click(T.layClick); ev(T.layClick, 'click'); ev(T.layClick + 0.05, 'menu');
const miSphere = layoutMenu.querySelector('[data-v="sphere"]');
T.sphClick = W('u06', '고르고') - 0.02;
curTo(T.layClick + 0.3, T.sphClick - 0.15, () => { const r = rect(miSphere); return [r.x + 120, r.cy]; });
click(T.sphClick); ev(T.sphClick, 'click');
const LAYSEQ = [];
function setLayout(t0, a, b) { morph(t0, t0 + 1.1, a, b); LAYSEQ.push({ t: t0, s: b }); ev(t0, 'morph', LAYSEQ.length);
  seg('dist', t0, t0 + 1.0, BOUND[b].dist); seg('tgt', t0, t0 + 1.0, BOUND[b].tgt); }
setLayout(T.sphClick + 0.08, 'celestial', 'sphere');
T.k5 = W('u06', '컨트롤') + 0.2; T.k6 = W('u06', '6') + 0.05; T.k1 = E('u06') + 0.0;
keycap(T.k5 - 0.25, T.k5 + 0.95, ['⌃', '⌘', '5'], [T.k5], '벽 · Wall'); setLayout(T.k5 + 0.05, 'sphere', 'wall');
keycap(T.k6 - 0.2, T.k6 + 0.95, ['⌃', '⌘', '6'], [T.k6], '나선 · Spiral'); setLayout(T.k6 + 0.05, 'wall', 'spiral');
keycap(T.k1 - 0.2, T.k1 + 1.0, ['⌃', '⌘', '1'], [T.k1], '천구 · Celestial'); setLayout(T.k1 + 0.05, 'spiral', 'celestial');
curTo(T.sphClick + 0.25, T.sphClick + 1.0, [1030, 330]);
zoomTo(T.layClick - 0.45, T.layClick + 0.2, 1180, 300, 1.4); zoomTo(T.sphClick + 0.1, T.sphClick + 0.75, 960, 540, 1);

// ---- ch4: relation modes + legend
const pRel = ctr(tb.rel);
curTo(S('u07') - 0.25, S('u07') + 0.55, pRel);
T.relOff = W('u07', '끔'); T.relFocus = W('u07', '선택') + 0.02; T.relAll = W('u07', '전체') + 0.02;
click(T.relOff); ev(T.relOff, 'click');
keycap(T.relFocus - 0.3, T.relAll + 1.0, ['⌘', 'L'], [T.relFocus, T.relAll], '');
step('mode', 0, 'all'); step('mode', T.relOff, 'off'); step('mode', T.relFocus, 'focus'); step('mode', T.relAll, 'all');
step('toast', T.relOff, 'Relations · 관계: ' + RELATION_MODE.off); step('toast', T.relFocus, 'Relations · 관계: ' + RELATION_MODE.focus); step('toast', T.relAll, 'Relations · 관계: ' + RELATION_MODE.all);
step('toast', T.relAll + 2.0, null);
zoomTo(T.relOff - 0.55, T.relOff - 0.05, 1010, 330, 1.25);
const pLegend = ctr(tb.legend);
T.legOpen = W('u08', '범례') + 0.2;
curTo(T.relAll + 0.9, T.legOpen - 0.1, pLegend); click(T.legOpen); ev(T.legOpen, 'click'); ev(T.legOpen + 0.05, 'menu');
T.hideUses = W('u08', '눌러') + 0.05; T.hideImports = T.hideUses + 0.62;
curTo(T.legOpen + 0.3, T.hideUses - 0.12, () => { const r = rect(lgRows.uses); return [r.x + 300, r.cy]; });
click(T.hideUses); ev(T.hideUses, 'click');
curTo(T.hideUses + 0.12, T.hideImports - 0.1, () => { const r = rect(lgRows.imports); return [r.x + 300, r.cy]; });
click(T.hideImports); ev(T.hideImports, 'click');
step('hidden', 0, []); step('hidden', T.hideUses, ['uses']); step('hidden', T.hideImports, ['uses', 'imports']);
T.legClose = E('u08') + 0.05;
curTo(T.hideImports + 0.9, T.legClose - 0.1, pLegend); click(T.legClose); ev(T.legClose, 'click');
zoomTo(T.legOpen - 0.35, T.legOpen + 0.35, 1230, 430, 1.32); zoomTo(T.legClose + 0.1, T.legClose + 0.75, 960, 540, 1);

// ---- ch5: select a card → inspector
T.scrollIn = T.legClose + 0.25;
gesture(T.scrollIn, T.scrollIn + 0.85, 'mouse', '스크롤 · Scroll'); ev(T.scrollIn, 'scroll');
seg('dist', T.scrollIn + 0.05, T.scrollIn + 0.8, 7.2, easeOut);
T.selClick = W('u09', '클릭') + 0.05;
curTo(T.scrollIn + 0.4, T.selClick - 0.12, follow3D((t) => nodePos(nListFile, t), 2, 6));
click(T.selClick); ev(T.selClick, 'select');
step('sel', 0, null); step('sel', T.selClick, nListFile);
seg('tgt', T.selClick, T.selClick + 1.1, nodeArr(nListFile), easeOut);
T.inspZoom = W('u09', '인스') - 0.4;
zoomTo(T.inspZoom, T.inspZoom + 0.75, 1290, 470, 1.45);
T.ringRole = W('u09', '역할'); T.ringCoupling = W('u09', '결합') + 0.05; T.ringRel = W('u09', '목록') - 0.25;
track('iscroll', 0);
const MI = inspMeasure[nListFile];
seg('iscroll', T.ringCoupling - 0.1, T.ringCoupling + 0.4, Math.max(0, MI.coupling.y - (WY + IY) - 190));
seg('iscroll', T.ringRel - 0.15, T.ringRel + 0.4, Math.max(0, MI.rel.y - (WY + IY) - 110));
const scrollTop = (t0) => seg('iscroll', t0, t0 + 0.001, 0, (x) => x);
ring(T.ringRole, T.ringCoupling + 0.1, () => MI.role, 5);
ring(T.ringCoupling + 0.25, T.ringRel, () => MI.coupling, 8);
ring(T.ringRel + 0.3, E('u09') + 0.6, () => ({ x: MI.rel.x, y: MI.rel.y, w: MI.rel.w, h: Math.min(MI.rel.h, 560) }), 8);
curTo(T.selClick + 0.3, T.ringRole - 0.2, () => { const r = MI.role; return [r.x + r.w + 20, r.cy + 18]; });
T.ch5out = E('u09') + 0.35;
zoomTo(T.ch5out, T.ch5out + 0.8, 960, 540, 1);

// ---- ch6: time dial (first select the project's root card in the middle of the sky: everything is related, nothing dims)
T.rootClick = S('u10') - 0.12;
curTo(T.ch5out - 0.1, T.rootClick - 0.1, follow3D((t) => nodePos(root, t), 0, 4)); click(T.rootClick); ev(T.rootClick, 'select');
step('sel', T.rootClick, root); scrollTop(T.rootClick);
seg('tgt', T.rootClick, T.rootClick + 1.1, nodeArr(root), easeOut);
seg('dist', T.rootClick, T.rootClick + 1.2, 8.4, easeOut);
const dialRect = () => rect(hud.slider);
T.dial0 = W('u10', '다이얼') + 0.3; T.dialN = W('u10', '뉴어') + 0.08; T.dialO = W('u10', '올더');
const knobX = (d) => { const r = dialRect(); return r.x + (d + 1) / 2 * r.w; };
curTo(T.rootClick + 0.12, T.dial0, () => [knobX(0) + 2, dialRect().cy + 4]);
hold(T.dial0 + 0.08, E('u10') - 0.2);
seg('dial', T.dialN + 0.05, T.dialN + 1.0, 1); curTo(T.dialN + 0.05, T.dialN + 1.0, () => [knobX(1) + 2, dialRect().cy + 4]);
seg('dial', T.dialO + 0.05, T.dialO + 1.45, -1); curTo(T.dialO + 0.05, T.dialO + 1.45, () => [knobX(-1) + 2, dialRect().cy + 4]);
ev(T.dialN, 'whooshUp'); ev(T.dialO, 'whooshDown');
T.reset = E('u10') + 0.25;
keycap(T.reset - 0.3, T.reset + 0.9, ['⌥', '⌘', '0'], [T.reset], 'Reset Time Dial');
seg('dial', T.reset + 0.05, T.reset + 0.75, 0);
zoomTo(S('u10') - 0.5, S('u10') + 0.3, 900, 600, 1.22);

// ---- ch7: ask the host, summon + beacon, dock / undock
const fieldPt = () => { const r = rect(hud.ask); return [r.x + 160, r.cy + 4]; };
const sendPt = () => { const r = rect(hud.send); return [r.cx, r.cy + 4]; };
T.f1 = W('u11', '입력') + 0.1;
curTo(S('u11') - 0.1, T.f1 - 0.1, fieldPt); click(T.f1); ev(T.f1, 'click');
T.type1a = W('u11', '엣') + 0.02; T.type1b = W('u11', '줘') + 0.18;
const Q1 = '@State를 쓰는 뷰 찾아줘';
T.send1 = W('u11', '보내') + 0.08;
curTo(T.type1b + 0.05, T.send1 - 0.08, sendPt); click(T.send1); ev(T.send1, 'click');
T.reply1 = S('u12') + 0.62; // locateCode on-device
const R1 = 'The project contains five SwiftUI views that use <code>@State</code>: NoteDetailView, NoteEditorView, NotesListView, SearchView and SyncSettingsView.';
T.summon1 = T.reply1 + 0.05; ev(T.summon1, 'summon'); ev(T.summon1 + 0.25, 'beacon');
step('sel', T.summon1, nDetail); scrollTop(T.summon1);
seg('tgt', T.summon1, T.summon1 + 1.1, nodeArr(nDetail), easeOut);
zoomTo(S('u11') - 0.6, S('u11') + 0.2, 940, 690, 1.42);
zoomTo(T.send1 + 0.25, T.send1 + 1.0, 960, 560, 1.08);
// a drag to look past the summoned copy, then tap the Views cluster orb
T.drag2a = E('u12') + 0.12; T.drag2b = S('u13') - 0.2;
const pDrag2 = [720, 360];
curTo(T.summon1 + 0.8, T.drag2a - 0.05, pDrag2); hold(T.drag2a, T.drag2b); curTo(T.drag2a + 0.05, T.drag2b, [pDrag2[0] - 70, pDrag2[1] + 4]);
seg('yaw', T.drag2a + 0.05, T.drag2b, () => val('yaw', T.drag2a) + 70 * 0.006); ev(T.drag2a, 'drag');
seg('dist', T.drag2a + 0.05, T.drag2b + 0.2, 4.8);
T.dockTap = W('u13', '탭') + 0.08;
curTo(T.drag2b + 0.15, T.dockTap - 0.12, follow3D((t) => clusterCenter(viewsCluster, t), 1, 4)); click(T.dockTap); ev(T.dockTap, 'tap');
T.docked = T.dockTap + 1.0; ev(T.docked, 'dock');
T.f2 = T.docked + 0.4; T.type2a = T.f2 + 0.08; T.type2b = T.type2a + 0.5; T.send2 = T.type2b + 0.22;
const Q2 = '여기엔 뭐가 있어?';
curTo(T.docked - 0.1, T.f2 - 0.08, fieldPt); click(T.f2); ev(T.f2, 'click');
curTo(T.type2b - 0.15, T.send2 - 0.05, sendPt); click(T.send2); ev(T.send2, 'click');
T.reply2 = T.send2 + 0.55;
const R2 = 'Views에는 SwiftUI 뷰 5개가 있어요 — <code>NotesListView</code>, <code>NoteDetailView</code>, <code>NoteEditorView</code>, <code>NoteRowView</code>, <code>TagChipView</code>.';
T.undock = W('u13', '나와') + 0.22;
curTo(T.reply2 + 0.3, T.undock - 0.1, () => { const r = rect(hud.undock); return [r.cx, r.cy + 4]; }); click(T.undock); ev(T.undock, 'click'); ev(T.undock + 0.05, 'undock');
T.undocked = T.undock + 1.0;
zoomTo(T.docked - 0.2, T.docked + 0.5, 940, 690, 1.32); zoomTo(T.undock + 0.15, T.undock + 0.9, 960, 540, 1);

// ---- ch8: voice
const pMic = ctr(tb.mic);
T.mic = W('u14', '버튼') + 0.05;
curTo(S('u14') - 0.7, T.mic - 0.12, pMic); click(T.mic); ev(T.mic, 'mic');
keycap(W('u14', '시프트') - 0.05, W('u14', '켜고') + 0.25, ['⇧', '⌘', 'V'], [], 'Toggle Voice', true);
T.wake = W('u14', '콘스') + 0.08; T.cmd0 = W('u14', '부른') - 0.05; T.cmd1 = W('u14', '됩니다') + 0.25; T.cmdDo = T.cmd1 + 0.25;
seg('dial', T.cmdDo, T.cmdDo + 0.8, 1); ev(T.cmdDo, 'whooshUp');
T.micOff = S('u15') - 0.45;
curTo(T.cmdDo + 0.1, T.micOff - 0.12, pMic); click(T.micOff); ev(T.micOff, 'click');
zoomTo(S('u14') - 0.8, S('u14') + 0.0, 1150, 360, 1.18); zoomTo(T.wake - 0.3, T.wake + 0.5, 960, 540, 1);

// ---- ch9: FaceTime → SharePlay, members, pointer, pins, export
T.ft0 = S('u15') - 0.15; T.sp = W('u15', '공유') - 0.1; T.ft1 = T.sp + 0.9;
curTo(T.micOff + 0.1, T.sp - 0.12, () => ctr(spBtn)); click(T.sp); ev(T.sp, 'click'); ev(T.ft0, 'sheet');
T.join = [T.ft1 - 0.15, T.ft1 + 0.4, T.ft1 + 0.95];
T.join.forEach((tj, k) => { step('toast', tj, `${PEOPLE[k + 1].name} joined · 참가`); ev(tj, 'avatar', k); });
step('toast', T.join[2] + 2.0, null);
seg('yaw', T.ft0, T.ft1, 0.32); seg('pitch', T.ft0, T.ft1, 0.3); seg('dist', T.ft0, T.ft1, 7.6); seg('tgt', T.ft0, T.ft1, [0.2, 1.55, 0.2]);
// laser pointer (long-press, then drag)
T.lp0 = W('u16', '길게'); T.lpOn = T.lp0 + 0.38; T.lp1 = W('u16', '인스') - 0.35;
const pP0 = [790, 380];
curTo(T.ft1 + 0.3, T.lp0 - 0.05, pP0); hold(T.lp0, T.lp1, 'long');
curTo(T.lpOn + 0.05, T.lpOn + 0.9, [960, 330]); curTo(T.lpOn + 0.95, T.lpOn + 1.75, [1080, 420]); curTo(T.lpOn + 1.8, T.lp1 - 0.05, [880, 470]);
ev(T.lpOn, 'pointer');
// review pin on the summoned card's node (NoteDetailView), then Markdown export
const MD = inspMeasure[nDetail];
T.pinScroll = T.lp1 - 0.1;
seg('iscroll', T.pinScroll, T.pinScroll + 0.45, Math.max(0, MD.pins.y - (WY + IY) - 200));
const pinOff = () => val('iscroll', T.pinScroll + 1);
T.pf = W('u16', '리뷰') + 0.02;
curTo(T.lp1 + 0.05, T.pf - 0.1, () => [MD.field.x + 120, MD.field.cy - pinOff() + 3]); click(T.pf); ev(T.pf, 'click');
T.pt0 = T.pf + 0.12; T.pt1 = W('u16', '남겨') + 0.1;
const PIN = 'isEditing은 ViewModel로 옮기기';
T.pinBtn = T.pt1 + 0.25;
curTo(T.pt1 - 0.05, T.pinBtn - 0.06, () => [MD.pinbtn.cx, MD.pinbtn.cy - pinOff() + 3]); click(T.pinBtn); ev(T.pinBtn, 'pin');
T.exp = W('u16', '마크') + 0.12;
const MDP = inspMeasure.detailPinned;
curTo(T.pinBtn + 0.12, T.exp - 0.08, () => [MDP.exp.cx, MDP.exp.cy - pinOff() + 3]); click(T.exp); ev(T.exp, 'click'); ev(T.exp + 0.08, 'sheet');
const btnSave = savePanel.querySelector('[data-b="save"]');
T.save = E('u16') - 0.25;
curTo(T.exp + 0.3, T.save - 0.1, () => { const r = rect(btnSave); const pr = rect(savePanel); return [r.cx - pr.w / 2, r.cy]; }); click(T.save); ev(T.save, 'click');
zoomTo(T.lp1 - 0.2, T.lp1 + 0.55, 1300, 560, 1.4); zoomTo(T.exp + 0.05, T.exp + 0.6, 960, 400, 1.25); zoomTo(T.save + 0.25, T.save + 0.95, 960, 540, 1);

// ---- ch10: guided tour
const pTour = ctr(tb.tour);
T.tourClick = W('u17', '버튼') + 0.12;
curTo(S('u17') - 0.75, T.tourClick - 0.1, pTour); click(T.tourClick); ev(T.tourClick, 'click');
T.step1 = W('u17', '학습') + 0.05; T.step2 = W('u17', '카메라') + 0.2;
ev(T.step1, 'summon'); ev(T.step1 + 0.25, 'beacon'); ev(T.step2, 'summon', 1); ev(T.step2 + 0.25, 'beacon', 1);
step('sel', T.step1, nApp); step('sel', T.step2, nStep2); scrollTop(T.step1); scrollTop(T.step2);
seg('tgt', T.step1, T.step1 + 1.2, nodeArr(nApp), easeOut); seg('tgt', T.step2, T.step2 + 1.3, nodeArr(nStep2), easeOut);
T.fhRing = W('u17', '팔로우') - 0.05;
const fhPt = () => ctr(tourEl.fh);
curTo(T.step1 + 0.3, T.fhRing + 0.1, () => { const p = fhPt(); return [p[0] + 10, p[1] + 6]; });
ring(T.fhRing, T.step2 - 0.25, () => rect(tourEl.fh), 6);
curTo(T.step2 - 0.6, T.step2 - 0.08, () => { const p = ctr(tourEl.next); return [p[0], p[1] + 4]; }); click(T.step2); ev(T.step2, 'click');
T.tourEnd = S('u18') - 0.8;
curTo(T.step2 + 0.5, T.tourEnd - 0.1, () => { const p = ctr(tourEl.x); return [p[0], p[1] + 3]; }); click(T.tourEnd); ev(T.tourEnd, 'click');
zoomTo(T.step1 - 0.4, T.step1 + 0.4, 900, 560, 1.16); zoomTo(T.tourEnd + 0.1, T.tourEnd + 0.7, 960, 540, 1);

// ---- ch11: themes
const pTheme = ctr(tb.theme);
T.th1 = W('u18', '팔레') + 0.1;
curTo(T.tourEnd + 0.2, T.th1 - 0.1, pTheme); click(T.th1); ev(T.th1, 'click'); ev(T.th1 + 0.05, 'menu');
const miOcean = themeMenu.querySelector('[data-v="Ocean"]'), miNebula = themeMenu.querySelector('[data-v="Nebula"]');
T.ocean = W('u18', '고르') + 0.05;
curTo(T.th1 + 0.3, T.ocean - 0.1, () => { const r = rect(miOcean); return [r.x + 110, r.cy]; }); click(T.ocean); ev(T.ocean, 'theme');
T.th2 = W('u18', '어떤') - 0.05;
curTo(T.ocean + 0.15, T.th2 - 0.1, pTheme); click(T.th2); ev(T.th2, 'click'); ev(T.th2 + 0.05, 'menu');
T.nebula = W('u18', '색이') + 0.25;
curTo(T.th2 + 0.25, T.nebula - 0.1, () => { const r = rect(miNebula); return [r.x + 110, r.cy]; }); click(T.nebula); ev(T.nebula, 'theme', 1);
step('theme', 0, 0); step('theme', T.ocean + 0.05, 1); step('theme', T.nebula + 0.05, 4);
T.close0 = W('u18', '코드는') - 0.2;
seg('tgt', T.close0, T.close0 + 1.6, nodeArr(nListType)); seg('dist', T.close0, T.close0 + 1.6, 0.86);
seg('yaw', T.close0, T.close0 + 1.6, () => { const p = nodePos(nListType, T.close0); let y = Math.atan2(p.x, p.z) + 0.1; const y0 = val('yaw', T.close0 - 0.01);
  while (y - y0 > Math.PI) y -= 2 * Math.PI; while (y0 - y > Math.PI) y += 2 * Math.PI; return y; });
seg('pitch', T.close0, T.close0 + 1.6, 0.1);
gesture(T.close0, T.close0 + 1.1, 'mouse', '스크롤 · Scroll'); ev(T.close0, 'scroll');
curTo(T.nebula + 0.3, T.close0 + 0.6, [1210, 640]);
zoomTo(S('u18') - 0.6, S('u18') + 0.3, 1150, 360, 1.15); zoomTo(T.nebula + 0.15, T.nebula + 0.8, 960, 540, 1);
zoomTo(T.close0 + 0.4, T.close0 + 1.7, 924, 470, 1.2);

// typing ticks + toast pops for the score
const typeEvents = (a, b, text) => { const n = text.length; for (let k = 0; k < n; k++) if (text[k] !== ' ') ev(a + (k + 0.5) / n * (b - a), 'type', k); };
typeEvents(T.type1a, T.type1b, Q1); typeEvents(T.type2a, T.type2b, Q2); typeEvents(T.pt0, T.pt1, PIN);
for (const s0 of STEPS.toast) if (s0.v) ev(s0.t, 'toast');
// ---- end
T.end0 = S('u19') - 0.5;
zoomTo(T.end0 - 0.2, T.end0 + 0.8, 960, 540, 1);
for (let k = 0; k < CHAPTERS.length; k++) ev(chStart(k) + 0.1, 'chapter', k);
ev(1.0, 'title'); ev(T.end0 + 0.3, 'end');

// ------------------------------------------------------------------------------------------------------------
// per-frame state
const hidden0 = new Set();
const typed = (t, a, b, text) => text.slice(0, Math.round(clamp01((t - a) / Math.max(0.01, b - a)) * text.length));
function hostUI(t) {
  // HostHUDView state label + last reply, glyph energy
  let st = 'Host orb · free', reply = null, energy = 0.2, docked = false;
  if (t >= T.send1 && t < T.reply1) { st = 'Thinking…'; energy = 1; }
  if (t >= T.reply1) reply = R1;
  if (t >= T.reply1 && t < T.reply1 + 3.6) { st = 'Speaking'; energy = 0.75; }
  if (t >= T.docked && t < T.undock) { docked = true; st = 'Docked in Views'; }
  if (t >= T.send2 && t < T.reply2) { st = 'Thinking…'; energy = 1; }
  if (t >= T.reply2) reply = R2;
  if (t >= T.reply2 && t < T.reply2 + 0.9) { st = 'Speaking'; energy = 0.75; }
  if (t >= T.mic && t < T.micOff && t >= T.wake) energy = Math.max(energy, 0.5);
  if (t >= T.tourClick && t < T.step1) { st = 'Thinking…'; energy = 1; }
  if (t >= T.step1) reply = `${TOUR[0].title}: ${TOUR[0].nar}`;
  if (t >= T.step2) reply = `${TOUR[1].title}: ${TOUR[1].nar}`;
  if ((t >= T.step1 && t < T.step1 + 3.0) || (t >= T.step2 && t < T.step2 + 3.0)) { st = 'Speaking'; energy = 0.75; }
  // streaming
  let shown = reply;
  const stream = (t0, txt) => { const plain = txt.replace(/<[^>]+>/g, ''); const k = clamp01((t - t0) / 0.8); return k >= 1 ? txt : esc(plain.slice(0, Math.round(plain.length * k))); };
  if (reply === R1 && t < T.reply1 + 0.8) shown = stream(T.reply1, R1);
  if (reply === R2 && t < T.reply2 + 0.8) shown = stream(T.reply2, R2);
  return { st, reply: shown, energy, docked };
}
function themeAt(t) {
  const steps = STEPS.theme; let a = 0, b = 0, t0 = -10;
  for (const s of steps) if (t >= s.t) { a = b; b = s.v; t0 = s.t; }
  const m = easeInOut(clamp01((t - t0) / 0.9));
  const A = PRESETS[a], B = PRESETS[b];
  if (a === b) return { pres: B, eng: b === 0 ? { m: 0 } : { m: 1, b: B } };
  if (a === 0) return { pres: m > 0.5 ? B : A, eng: { m, b: B }, A, B, k: m };
  return { pres: m > 0.5 ? B : A, eng: { m, a: A, b: B }, A, B, k: m };
}
function state(t) {
  const L = layoutAt(t);
  const mode = at('mode', t, 'all');
  const hidden = new Set(at('hidden', t, []));
  const sel = at('sel', t, null);
  const cam = camAt(t);
  const st = { t, camera: cam, layout: L, dial: dialAt(t), relMode: mode, hidden, orbs: 1, stage: true, guides: [], labels: [], extraGlows: [], bloom: 0.7, particles: true };
  st.focus = sel; st.selected = sel; st.selectColor = '#FFFFFF';
  // highlights: host answers (all five @State views), then tour stops
  if (t >= T.reply1) st.highlight = new Set(atState);
  if (t >= T.step1) st.highlight = new Set([sel]);
  // summon copies (world-fixed where the viewer was) + beacons (20 s lifetime)
  const summons = [[T.summon1, nDetail], [T.step1, nApp], [T.step2, nStep2]];
  let sm = null; for (const [ts, node] of summons) if (t >= ts) sm = { ts, node };
  if (sm) { state.sumT = state.sumT || {}; const key = sm.ts; if (!state.sumT[key]) state.sumT[key] = ahead(sm.ts + 1.1, 0.6, 0.08);
    st.summon = { node: sm.node, k: clamp01((t - sm.ts) / 0.6), target: state.sumT[key], width: 0.42 }; }
  st.beacons = [];
  for (const [ts, node] of summons) if (t >= ts && t < ts + 20) st.beacons.push({ node, age: t - ts, alpha: win(t, ts, ts + 20, 0.2, 0.6) });
  st.beacons = st.beacons.slice(-3);
  // host orb: rests at the standing viewer's 0.9 m ahead; docks into the Views orb; undock flies to the window camera
  const rest0 = V(0, 1.3, -0.9);
  if (!state.rest1) state.rest1 = ahead(T.undock + 0.05, 0.9, 0.12);
  const vc = clusterCenter(viewsCluster, t);
  let hp = rest0.clone(), hs = 1, hv = 1;
  if (t >= T.dockTap + 0.05 && t < T.undock + 0.05) { const k = easeInOut(clamp01((t - T.dockTap - 0.05) / 0.95)); hp = rest0.clone().lerp(vc, k); hs = 1 - 0.8 * k; if (k >= 1) hv = 0; }
  if (t >= T.undock + 0.05) { const k = easeInOut(clamp01((t - T.undock - 0.05) / 0.95)); hp = vc.clone().lerp(state.rest1, k); hs = 0.2 + 0.8 * k; }
  const hu = hostUI(t);
  st.host = { visible: hv, pos: hp, scale: 0.85 * hs, energy: hu.energy, glow: 0.42 };
  if (t >= T.imm0 - 0.05 && t < T.imm1 + 0.05) { st.host.scale = 0.42; st.host.glow = 0.6; }
  // hover highlight on the Views cluster orb before the tap (HoverEffectComponent)
  if (t > T.dockTap - 0.6 && t < T.dockTap + 0.3) st.extraGlows.push({ p: clusterCenter(viewsCluster, t), color: '#C9C2FF', alpha: 0.55 * win(t, T.dockTap - 0.6, T.dockTap + 0.3, 0.2, 0.2), size: 0.5 });
  if (hu.docked) st.docked = viewsCluster;
  // participants (windowed: the local avatar shows too); members join through SharePlay
  st.avatars = PEOPLE.map((p, k) => ({ name: p.name, color: p.color, visible: k === 0 ? 1 : ramp(t, T.join[k - 1], 0.5) }));
  // laser pointer
  if (t >= T.lpOn && t < T.lp1) { const c = curAt(t); const anchor = nodePos(nDetail, t); const r = rayHit(c[0], c[1], t, anchor);
    const origin = r.origin.clone().addScaledVector(r.dir, 0.4).add(V(0, -0.15, 0)); st.pointer = { origin, hit: r.hit, color: PEOPLE[0].color }; }
  if (t >= T.pinBtn) st.pins = { [nDetail]: 1 };
  // theme
  const th = themeAt(t); st.theme = th.eng;
  // immersive (visionOS) segment: standing in the middle of the sky
  if (t >= T.imm0 - 0.05 && t < T.imm1 + 0.05) {
    const k = clamp01((t - T.imm0) / (T.imm1 - T.imm0));
    const yaw = lerp(-0.42, 0.3, easeInOut(k));
    const pos = V(0, 1.45, 0.18);
    st.camera = { pos, target: pos.clone().add(V(Math.sin(yaw) * -6, 1.05, Math.cos(yaw) * -6)), fov: 64 };
    st.avatars = []; st.focus = null; st.selected = null; st.relMode = 'all';
  }
  return st;
}

// ------------------------------------------------------------------------------------------------------------
// overlay
const KEYEL = []; let keysKey = '';
const bars = []; { const vb = el.voice.querySelector('.bars'); for (let k = 0; k < 18; k++) { const b = document.createElement('i'); vb.appendChild(b); bars.push(b); } }
const ripples = [0, 1].map(() => { const d = document.createElement('div'); d.className = 'ripple'; el.rings.appendChild(d); return d; });
const ringEls = [0, 1, 2].map(() => { const d = document.createElement('div'); d.className = 'ring'; el.rings.appendChild(d); return d; });
const tagEl = document.createElement('div'); tagEl.className = 'tag3d'; el.rings.appendChild(tagEl);
const holdEl = document.createElement('div'); holdEl.className = 'hold'; el.cursor.appendChild(holdEl);
function envAt(t) { const i = Math.floor(t * TL.envFps); return TL.env[Math.max(0, Math.min(TL.env.length - 1, i))] || 0; }
function setText(e, s) { if (e._t !== s) { e._t = s; e.textContent = s; } }
function setHTML(e, s) { if (e._h !== s) { e._h = s; e.innerHTML = s; } }
function setOp(e, v) { const s = v.toFixed(3); if (e._o !== s) { e._o = s; e.style.opacity = s; } }
function setDisp(e, v) { if (e._d !== v) { e._d = v; e.style.display = v; } }
function drawGlyph(t, energy, color) {
  const c = hud.glyph, g = c.getContext('2d'); const W2 = 92; g.clearRect(0, 0, W2, W2); g.save(); g.translate(W2 / 2, W2 / 2); g.scale(2, 2);
  const pulse = 1 + Math.sin(t * (2 + energy * 6)) * 0.08 * energy; const r = 17;
  g.fillStyle = rgbaOf(color, 0.25); g.beginPath(); g.arc(0, 0, r * 0.62 * pulse * 1.35 * 0.74, 0, Math.PI * 2); g.fill();
  const ell = (sx, sy, rot, a) => { g.save(); g.rotate(rot); g.scale(sx, sy); g.beginPath(); g.arc(0, 0, r * 0.74, 0, Math.PI * 2); g.restore(); g.strokeStyle = rgbaOf(color, a); g.lineWidth = 1.5; g.stroke(); };
  ell(1, 0.45, t * (0.6 + energy * 2), 0.8); ell(0.45, 1, -t * (0.9 + energy * 2) + 1, 0.6);
  g.fillStyle = '#fff'; g.beginPath(); g.arc(0, 0, r * 0.74 * 0.45 * pulse, 0, Math.PI * 2); g.fill(); g.restore();
}
let canvasFull = false;
function placeCanvas(full) {
  if (full === canvasFull) return; canvasFull = full;
  if (full) { el.full.appendChild(canvas); el.full.style.display = 'block'; eng.setViewport(1920, 1080); }
  else { el.host.appendChild(canvas); el.full.style.display = 'none'; eng.setViewport(VW, VH); }
}
function menuHover(menu, cur, open) {
  const items = [...menu.querySelectorAll('.mi')]; let hit = null;
  if (open) for (const it of items) { const r = rect(it); if (cur[0] >= r.x && cur[0] <= r.x + r.w && cur[1] >= r.y && cur[1] <= r.y + r.h) hit = it; }
  for (const it of items) it.classList.toggle('hl', it === hit);
}
function layoutPass(t, st) {
  const mode = at('mode', t, 'all'); const th = themeAt(t);
  // ---------------- HUD
  const hu = hostUI(t);
  setText(hud.st, hu.st);
  if (hu.reply) { hud.rp.classList.remove('sec'); setHTML(hud.rp, hu.reply); } else { hud.rp.classList.add('sec'); setHTML(hud.rp, 'Apple Intelligence · on-device'); }
  setDisp(hud.undock, hu.docked ? 'flex' : 'none'); hud.undock.classList.toggle('down', t >= T.undock - 0.05 && t < T.undock + 0.08);
  drawGlyph(t, hu.energy, th.pres.orbHalo);
  const d = dialAt(t); const x = (d + 1) / 2; hud.kn.style.left = (x * 100).toFixed(2) + '%'; hud.fil.style.left = '0%'; hud.fil.style.width = (x * 100).toFixed(2) + '%';
  // text field: focus, typing, caret
  let ty = '', focus = false;
  if (t >= T.f1 && t < T.send1) { focus = true; ty = typed(t, T.type1a, T.type1b, Q1); }
  if (t >= T.f2 && t < T.send2) { focus = true; ty = typed(t, T.type2a, T.type2b, Q2); }
  hud.ask.classList.toggle('focus', focus); setText(hud.ty, ty); setDisp(hud.ph, ty ? 'none' : 'inline');
  hud.caret.style.opacity = focus && Math.floor(t * 2.2) % 2 === 0 ? 1 : 0; hud.caret.style.order = ty ? 0 : -1;
  hud.send.className = 'btn ' + (ty ? '' : 'dis') + ((t >= T.send1 - 0.05 && t < T.send1 + 0.08) || (t >= T.send2 - 0.05 && t < T.send2 + 0.08) ? ' down' : '');
  // tour bar
  const tourOn = t >= T.step1 && t < T.tourEnd + 0.05;
  setDisp(el.tour, tourOn ? 'block' : 'none');
  if (tourOn) { const k = t >= T.step2 ? 1 : 0; setText(tourEl.n, `${k + 1} / 8`); setText(tourEl.s1, TOUR[k].title); setText(tourEl.s2, TOUR[k].nar);
    tourEl.prev.className = 'btn' + (k === 0 ? ' dis' : ''); tourEl.next.classList.toggle('down', t >= T.step2 - 0.05 && t < T.step2 + 0.08);
    el.tour.style.opacity = ramp(t, T.step1, 0.2).toFixed(3); }
  // ---------------- navigator + inspector
  const sel = at('sel', t, null);
  renderOutline(sel, sel, sel);
  const pins = t >= T.pinBtn ? [{ node: nDetail, text: PIN, author: 'Coulson', time: '3:42 PM' }] : [];
  const pinFocus = t >= T.pf && t < T.pinBtn; const pinText = pinFocus ? typed(t, T.pt0, T.pt1, PIN) : '';
  renderInspector(sel, { mode, hidden: new Set(at('hidden', t, [])), pins, pinText, pinFocus, caret: Math.floor(t * 2.2) % 2 === 0 ? 1 : 0, docked: hu.docked && sel !== null && eng.clusters[viewsCluster].members.includes(sel) });
  const isc = val('iscroll', t); el.insp.style.transform = `translateY(${-isc}px)`;
  const ib = document.getElementById('i-pinbtn'); if (ib) ib.classList.toggle('down', t >= T.pinBtn - 0.05 && t < T.pinBtn + 0.08);
  const ie = document.getElementById('i-export'); if (ie) ie.classList.toggle('down', t >= T.exp - 0.05 && t < T.exp + 0.08);
}
function overlay(t, st) {
  layoutPass(t, st);
  const cur = curAt(t);
  // fade from black / to black; title card; end card
  setOp(el.black, Math.max(1 - ramp(t, 0.2, 1.4), ramp(t, TL.duration - 1.9, 1.7)));
  setOp(el.title, win(t, 0.9, S('u02') - 0.75, 0.6, 0.55));
  el.title.style.transform = `translateY(${(1 - ease(ramp(t, 0.9, 1.0))) * 14}px)`;
  const endK = ramp(t, T.end0, 0.9);
  setOp(el.end, ramp(t, T.end0 + 0.35, 0.8)); el.end.style.transform = `translateY(${(1 - ease(ramp(t, T.end0 + 0.35, 0.9))) * 16}px)`;
  // zoom (#cam) + window fade for the end card
  const z = val('zoom', t); let s = z[2];
  let tx = 960 - s * z[0], ty = 540 - s * z[1]; tx = Math.min(0, Math.max(1920 - 1920 * s, tx)); ty = Math.min(0, Math.max(1080 - 1080 * s, ty));
  const endS = 1 - 0.06 * ease(endK);
  el.cam.style.transform = `translate(${tx + 960 * (1 - endS)}px, ${ty + 540 * (1 - endS)}px) scale(${s * endS})`;
  el.cam.style.opacity = (1 - 0.82 * ease(endK)).toFixed(3);
  el.cam.style.filter = endK > 0 ? `blur(${(endK * 6).toFixed(1)}px)` : (t < S('u02') - 0.6 ? `brightness(${(1 - 0.45 * win(t, 0.9, S('u02') - 0.75, 0.6, 0.55)).toFixed(3)})` : 'none');
  // captions
  let cl = null; for (const l of TL.lines) if (t >= l.start - 0.12 && t <= l.end + 0.4) cl = l;
  if (cl && cl.id !== 'u19') { setText(el.cap, cl.cap); setOp(el.cap, win(t, cl.start - 0.12, cl.end + 0.4, 0.16, 0.22)); } else setOp(el.cap, 0);
  // chapter label
  let ck = -1; for (let k = 0; k < CHAPTERS.length; k++) if (t >= chStart(k)) ck = k;
  if (ck >= 0 && t < T.end0) {
    const [, num, ko, en] = CHAPTERS[ck];
    setText(el.chapter.querySelector('b'), num); setText(el.chapter.querySelector('.ko'), ko); setText(el.chapter.querySelector('.en'), en);
    const nxt = ck + 1 < CHAPTERS.length ? chStart(ck + 1) : T.end0;
    setOp(el.chapter, win(t, chStart(ck), nxt, 0.35, 0.25)); el.chapter.style.transform = `translateX(${(1 - ease(ramp(t, chStart(ck), 0.45))) * -16}px)`;
  } else setOp(el.chapter, 0);

  // ---------------- window chrome
  const L = st.layout; const style = L.m > 0.5 ? L.b : L.a;
  setHTML(tb.layout.querySelector('.li'), icon(LSYM[style]));
  const mode = at('mode', t, 'all'); setHTML(tb.rel.querySelector('.li'), icon(MSYM[mode]));
  const members = 1 + T.join.filter((tj) => t >= tj).length; setText(tb.member.querySelector('.badge'), String(members));
  const th = themeAt(t); tb.member.querySelector('.badge').style.background = th.pres.orbHalo;
  const micOn = t >= T.mic && t < T.micOff; tb.mic.classList.toggle('on', micOn); setHTML(tb.mic, icon('mic'));
  if (micOn) tb.mic.style.opacity = (0.65 + 0.35 * Math.abs(Math.sin(t * 3.2))).toFixed(3); else tb.mic.style.opacity = '1';
  // hover / pressed states on toolbar buttons
  for (const b of Object.values(tb)) { const r = rect(b); const over = cur[0] >= r.x && cur[0] <= r.x + r.w && cur[1] >= r.y && cur[1] <= r.y + r.h; b.classList.toggle('hov', over); }
  // tooltip on the relations button (help text)
  const tipA = win(t, S('u07') + 1.1, T.relOff - 0.05, 0.15, 0.1);
  setOp(tip, tipA);
  if (tipA > 0) { setText(tip, `Relations: ${RELATION_MODE[mode]} (⌘L cycles off → focus → all)`); const r = rect(tb.rel); tip.style.left = (r.x - WX - 120) + 'px'; tip.style.top = (r.y - WY + r.h + 14) + 'px'; }
  // layout menu
  const layOpen = t >= T.layClick + 0.05 && t < T.sphClick + 0.05;
  setOp(layoutMenu, layOpen ? ramp(t, T.layClick + 0.05, 0.12) : (t >= T.sphClick + 0.05 ? 1 - ramp(t, T.sphClick + 0.05, 0.12) : 0));
  layoutMenu.style.transform = `scale(${0.97 + 0.03 * ramp(t, T.layClick + 0.05, 0.12)})`;
  if (layoutMenu._s !== style) { layoutMenu._s = style; layoutMenu.querySelectorAll('.mi').forEach((m) => { m.querySelector('.ck').innerHTML = m.dataset.v === style ? icon('check') : ''; }); layoutMenu.querySelector('.nt').textContent = LAYOUT[style].axes; }
  menuHover(layoutMenu, cur, layOpen);
  // theme menu (opened twice)
  const thOpen = (t >= T.th1 + 0.05 && t < T.ocean + 0.05) || (t >= T.th2 + 0.05 && t < T.nebula + 0.05);
  const thA = Math.max(t >= T.th1 + 0.05 && t < T.ocean + 0.17 ? (t < T.ocean + 0.05 ? ramp(t, T.th1 + 0.05, 0.12) : 1 - ramp(t, T.ocean + 0.05, 0.12)) : 0,
    t >= T.th2 + 0.05 && t < T.nebula + 0.17 ? (t < T.nebula + 0.05 ? ramp(t, T.th2 + 0.05, 0.12) : 1 - ramp(t, T.nebula + 0.05, 0.12)) : 0);
  setOp(themeMenu, thA);
  const curTheme = PRESETS[at('theme', t, 0)].name;
  if (themeMenu._s !== curTheme) { themeMenu._s = curTheme; themeMenu.querySelectorAll('.mi').forEach((m) => { m.querySelector('.ck').innerHTML = m.dataset.v === curTheme ? icon('check') : ''; }); }
  menuHover(themeMenu, cur, thOpen);
  // legend popover
  const lgA = t >= T.legOpen + 0.05 && t < T.legClose + 0.17 ? (t < T.legClose + 0.05 ? ramp(t, T.legOpen + 0.05, 0.15) : 1 - ramp(t, T.legClose + 0.05, 0.12)) : 0;
  setOp(legend, lgA); legend.style.transform = `scale(${0.96 + 0.04 * ramp(t, T.legOpen + 0.05, 0.15)})`;
  if (lgA > 0) {
    const hid = new Set(at('hidden', t, []));
    legend.querySelectorAll('.seg i').forEach((s) => s.classList.toggle('on', s.dataset.m === mode));
    for (const [k, d] of Object.entries(lgRows)) { const off = hid.has(k) || !(counts[k] > 0); d.classList.toggle('off', off); setHTML(d.querySelector('.e'), icon(hid.has(k) ? 'eye-off' : 'eye'));
      const r = rect(d); d.classList.toggle('hov', cur[0] >= r.x && cur[0] <= r.x + r.w && cur[1] >= r.y && cur[1] <= r.y + r.h); }
    legend.querySelector('.sa').style.display = hid.size ? 'block' : 'none';
  }
  // open panel / save panel
  const opA = t >= T.panelIn && t < T.panelOut + 0.2 ? (t < T.panelOut ? ramp(t, T.panelIn, 0.22) : 1 - ramp(t, T.panelOut, 0.18)) : 0;
  setOp(openPanel, opA); openPanel.style.transform = `translateX(-50%) translateY(${(1 - ease(ramp(t, T.panelIn, 0.25))) * -18}px)`;
  rowMy.classList.toggle('sel', t >= T.rowClick); openPanel.querySelector('[data-b="open"]').className = 'btn ' + (t >= T.rowClick ? 'pri' : 'dis');
  btnCancel.classList.toggle('down', t >= T.cancel - 0.05 && t < T.cancel + 0.08);
  const svA = t >= T.exp + 0.08 && t < T.save + 0.25 ? (t < T.save + 0.06 ? ramp(t, T.exp + 0.08, 0.22) : 1 - ramp(t, T.save + 0.06, 0.18)) : 0;
  setOp(savePanel, svA); savePanel.style.transform = `translateX(-50%) translateY(${(1 - ease(ramp(t, T.exp + 0.08, 0.25))) * -18}px)`;
  btnSave.classList.toggle('down', t >= T.save - 0.05 && t < T.save + 0.08);
  // FaceTime / SharePlay
  const ftA = t >= T.ft0 && t < T.ft1 + 0.35 ? (t < T.ft1 ? ramp(t, T.ft0, 0.3) : 1 - ramp(t, T.ft1, 0.3)) : 0;
  setOp(el.ft, ftA); el.ft.style.transform = `translateX(${(1 - ease(ramp(t, T.ft0, 0.35))) * 40 + ease(ramp(t, T.ft1, 0.35)) * 40}px)`;
  if (t >= T.sp) { setHTML(spBtn, `${icon('check')}Sharing`); spBtn.className = 'btn'; } else { setHTML(spBtn, `${icon('screen-share')}SharePlay`); spBtn.className = 'btn pri'; }
  // toast
  const toastTxt = at('toast', t, null);
  if (toastTxt) { setText(el.toast, toastTxt); const since0 = since('toast', t); setOp(el.toast, Math.min(ramp(since0, 0, 0.18), 1)); el.toast.style.transform = `translateX(-50%) translateY(${(1 - ease(ramp(since0, 0, 0.25))) * -10}px)`; }
  else { const ago = since('toast', t); setOp(el.toast, ago < 0.25 ? 1 - ago / 0.25 : 0); }
  // pointer label (bottom-trailing of the viewport, above the HUD)
  setOp(el.plbl, t >= T.lpOn && t < T.lp1 ? 1 : 0);
  // ---------------- rings, 3-D tag
  ringEls.forEach((r) => (r.style.opacity = 0));
  let ri = 0;
  for (const R of RINGS) { if (t < R.t0 - 0.05 || t > R.t1 + 0.3 || ri >= ringEls.length) continue; const a = win(t, R.t0, R.t1 + 0.25, 0.2, 0.25); if (a <= 0) continue;
    let r = resolve(R.r, t); const insp = r.x >= WX + IX - 2; const dy = insp ? -val('iscroll', t) : 0;
    const e = ringEls[ri++]; e.style.opacity = a; e.style.left = (r.x - R.pad) + 'px'; e.style.top = (r.y - R.pad + dy) + 'px'; e.style.width = (r.w + R.pad * 2) + 'px'; e.style.height = (r.h + R.pad * 2) + 'px'; }
  // sample callout (navigator)
  const sa = win(t, T.sample0, T.sample1, 0.25, 0.3);
  if (sa > 0) { const h = pHead(); const e = ringEls[ri++]; e.style.opacity = sa; e.style.left = (h.x - 6) + 'px'; e.style.top = (h.y - 6) + 'px'; e.style.width = (h.w + 12) + 'px'; e.style.height = (h.h + 12) + 'px';
    tagEl.textContent = '내장 샘플 · Sample project (47 files)'; tagEl.style.left = (h.x + h.w + 26) + 'px'; tagEl.style.top = (h.y + h.h / 2) + 'px'; tagEl.style.transform = 'translate(0, -50%)'; tagEl.style.color = '#FFD166'; tagEl.style.opacity = sa; }
  else tagEl.style.opacity = 0;
  // ---------------- cursor
  const cvis = (t >= T.cursorIn ? ramp(t, T.cursorIn, 0.3) : 0) * (t < T.v0 + 0.3 || t > T.imm1 - 0.2 ? 1 : 0) * (1 - ramp(t, T.end0, 0.4));
  el.cursor.style.opacity = cvis.toFixed(3);
  el.cursor.style.transform = `translate(${cur[0].toFixed(1)}px, ${cur[1].toFixed(1)}px)`;
  let pk = 0; for (const c of CLICKS) if (t >= c - 0.02 && t < c + 0.42) pk = Math.max(pk, 1 - (t - c) / 0.42);
  const ph = CLICKS.find((c) => t >= c - 0.02 && t < c + 0.42);
  el.press.style.opacity = pk.toFixed(3); el.press.style.transform = `scale(${ph !== undefined ? 0.5 + 0.9 * ease((t - ph) / 0.42) : 1})`;
  const hd = HOLDS.find(([a, b, kind]) => t >= a && t < b && kind === 'long');
  if (hd) { const k = clamp01((t - hd[0]) / 0.38); holdEl.innerHTML = `<svg width="52" height="52" viewBox="0 0 52 52"><circle cx="26" cy="26" r="20" fill="rgba(255,255,255,0.12)" stroke="rgba(255,255,255,0.35)" stroke-width="3"/><circle cx="26" cy="26" r="20" fill="none" stroke="#fff" stroke-width="3" stroke-dasharray="${(k * 125.7).toFixed(1)} 200" transform="rotate(-90 26 26)"/></svg>`; holdEl.style.opacity = 1; }
  else holdEl.style.opacity = 0;
  // ---------------- keycaps + gestures
  const kc = KEYS.find((k) => t >= k.t0 && t < k.t1);
  const gs = GEST.find((g) => t >= g.t0 && t < g.t1);
  if (kc) {
    const kk = kc.keys.join('|') + kc.label + kc.or; if (keysKey !== kk) { keysKey = kk; el.keys.innerHTML = (kc.or ? '<span class="or">또는</span>' : '') + kc.keys.map((x) => `<div class="k">${x}</div>`).join(''); setText(el.klbl, kc.label); }
    const down = kc.press.some((p) => t >= p - 0.02 && t < p + 0.16);
    el.keys.querySelectorAll('.k').forEach((k) => k.classList.toggle('dn', down));
    setOp(el.keycaps, win(t, kc.t0, kc.t1, 0.15, 0.2));
    const pr = kc.press.filter((p) => t >= p); el.keycaps.style.transform = `translateX(-50%) scale(${1 + 0.03 * Math.max(0, 1 - (pr.length ? (t - pr[pr.length - 1]) / 0.2 : 9))})`;
  } else if (gs) {
    const kk = 'g' + gs.label; if (keysKey !== kk) { keysKey = kk; el.keys.innerHTML = `<div class="k g"><span style="font-size:30px;margin-right:12px;display:flex">${icon(gs.ic)}</span>${gs.label}</div>`; setText(el.klbl, ''); }
    setOp(el.keycaps, win(t, gs.t0, gs.t1, 0.15, 0.2)); el.keycaps.style.transform = 'translateX(-50%)';
  } else setOp(el.keycaps, 0);
  // ---------------- voice utterance (what the person says)
  const va = win(t, T.wake - 0.25, T.cmdDo + 0.55, 0.2, 0.3);
  setOp(el.voice, va);
  if (va > 0) {
    const full = '콘스텔, 최근 코드 보여 줘'; const wake = '콘스텔,';
    const txt = t < T.cmd0 ? wake.slice(0, Math.max(1, Math.round(clamp01((t - T.wake) / 0.45) * wake.length))) : wake + full.slice(wake.length, wake.length + Math.round(clamp01((t - T.cmd0) / (T.cmd1 - T.cmd0)) * (full.length - wake.length)));
    setText(el.vtxt, t < T.wake ? 'Listening… · 듣는 중' : txt);
    bars.forEach((b, k) => { const live = (t > T.wake && t < T.wake + 0.5) || (t > T.cmd0 && t < T.cmd1); const e = live ? 0.35 + 0.65 * Math.abs(Math.sin(t * 13 + k * 1.3)) * (0.5 + 0.5 * Math.sin(k * 0.9 + t * 4)) : 0.05;
      b.style.height = (5 + 30 * e).toFixed(1) + 'px'; });
  }
  // ---------------- visionOS segment
  const vA = t >= T.v0 && t < T.imm0 + 1.2 ? Math.min(ramp(t, T.v0, 0.45), 1 - ramp(t, T.imm0 + 0.55, 0.6)) : 0;
  const zs = val('zoom', t)[2];
  setOp(el.vision, vA); setOp(el.capband, Math.max(vA, t >= T.imm0 - 0.05 && t < T.imm1 + 0.05 ? 0.7 : 0, clamp01((zs - 1) / 0.12) * 0.92));
  if (vA > 0) {
    const zk = easeInOut(ramp(t, T.v0 + 0.35, 1.1)) * 1.0; const sV = 1 + 1.15 * zk;
    const tx2 = 960 - sV * (960 + (VBTN.cx - 960) * zk), ty2 = 540 - sV * (540 + (VBTN.cy - 540) * zk);
    el.vroom.style.transform = `translate(${tx2}px, ${ty2}px) scale(${sV})`;
    const ga = win(t, T.gaze, T.imm0 + 0.3, 0.2, 0.25); el.gaze.style.opacity = (ga * (t >= T.pinchV && t < T.pinchV + 0.15 ? 0.55 : 1)).toFixed(3);
    el.gaze.style.left = (VBTN.x - 4) + 'px'; el.gaze.style.top = (VBTN.y - 3) + 'px'; el.gaze.style.width = (VBTN.w + 8) + 'px'; el.gaze.style.height = (VBTN.h + 6) + 'px';
    const pk2 = ramp(t, T.pinchV - 0.05, 0.4); el.pinch.style.opacity = (pk2 > 0 && pk2 < 1 ? 1 - pk2 : 0).toFixed(3); el.pinch.style.left = VBTN.cx + 'px'; el.pinch.style.top = VBTN.cy + 'px';
    el.pinch.style.transform = `scale(${(1.6 - 1.1 * pk2).toFixed(3)})`;
  }
  const imm = t >= T.imm0 - 0.05 && t < T.imm1 + 0.05;
  placeCanvas(imm);
  if (imm) {
    const rk = easeOut(ramp(t, T.imm0, 0.9)); const out = 1 - ramp(t, T.imm1 - 0.45, 0.45);
    el.full.style.opacity = out.toFixed(3);
    el.full.style.webkitMaskImage = rk < 1 ? `radial-gradient(circle at 960px 540px, #000 ${(rk * 2300).toFixed(0)}px, transparent ${(rk * 2300 + 160).toFixed(0)}px)` : 'none';
    el.full.style.maskImage = el.full.style.webkitMaskImage;
  }
}

// ------------------------------------------------------------------------------------------------------------
window.EVENTS = EVENTS.sort((a, b) => a.t - b.t);
window.seek = (t) => {
  const st = state(t);
  overlay(t, st);
  eng.render(st);
  return true;
};
window.DURATION = TL.duration;
window.__eng = eng; window.__state = state; window.__T = T; window.__W = W; window.__camAt = camAt;
const t0 = parseFloat(Q.get('t') || '0');
window.seek(t0);
window.ready = true;
