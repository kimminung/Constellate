// Intro film director: every visual is a pure function of t (seconds), keyed to the narration timeline (window.TL).
import * as THREE from 'three';
import { Constellation, ease, easeInOut, easeOut } from './engine.js';
import { REL, LAYOUT, DARK } from './theme.js';

const TL = window.TL, G = window.GRAPH;
const Q = new URLSearchParams(location.search);
const GIF = Q.has('gif');
const V = (x, y, z) => new THREE.Vector3(x, y, z);
const clamp01 = (x) => Math.max(0, Math.min(1, x));
const lerp = (a, b, k) => a + (b - a) * k;
const line = (id) => TL.lines.find((l) => l.id === id);
const S = (id) => line(id).start, E = (id) => line(id).end;
/** time of the first ASR token of line `id` that contains `frag` (falls back to proportional position) */
function W(id, frag, after = 0) {
  const l = line(id);
  let acc = '';
  for (const w of l.words) { acc += w.w; if (acc.replace(/\s/g, '').includes(frag.replace(/\s/g, '')) && w.t >= l.start + after) return w.t - 0.12; }
  const i = l.cap.indexOf(frag); return l.start + (i < 0 ? 0 : i / l.cap.length * l.dur);
}
/** smooth window: 0 before a, ramps to 1 over fi, holds, ramps down over fo ending at b */
function win(t, a, b, fi = 0.4, fo = 0.4) {
  if (t <= a || t >= b) return 0;
  return Math.min(ease((t - a) / fi), ease((b - t) / fo));
}
const ramp = (t, a, d) => clamp01((t - a) / d);

// ------------------------------------------------------------------------------------------------------------
// deterministic helpers
let seed = 1;
const rnd = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
const N = G.nodes.length;
// "chaos" layout: the same cards scattered at random around the viewer (before Constellate orders them)
seed = 7;
G.positions.chaos = G.nodes.map(() => {
  const az = rnd() * Math.PI * 2, el = (rnd() * 62 - 8) * Math.PI / 180, r = 5 + rnd() * 5.5;
  return [Math.sin(az) * Math.cos(el) * r, 1.45 + Math.sin(el) * r, Math.cos(az) * Math.cos(el) * r];
});
G.centers.chaos = [0, 1.45, 0];
const chaosBase = G.positions.chaos.map((p) => p.slice());
const delayHash = G.nodes.map((n, i) => ((i * 7919) % 101) / 101);

const canvas = document.getElementById('c');
canvas.width = 1920; canvas.height = 1080;
await document.fonts.load('600 44px Pretendard'); await document.fonts.load('700 30px Pretendard'); await document.fonts.load('800 44px Pretendard');
const eng = new Constellation(canvas, 1920, 1080);
await eng.load(G, 'assets/');
const graph = eng.graph;
const idOf = (name) => graph.nodes.findIndex((n) => n.id.endsWith(name));
const P0 = (i, style = 'celestial') => V(...G.positions[style][i]);

// ------------------------------------------------------------------------------------------------------------
// key nodes and sets
const nDetail = idOf('NoteDetailView.swift#NoteDetailView');
const atStateViews = ['NoteEditorView.swift#NoteEditorView', 'NotesListView.swift#NotesListView', 'SearchView.swift#SearchView', 'SyncSettingsView.swift#SyncSettingsView'].map(idOf);
const nNoteFile = idOf('Domain/Models/Note.swift');
const nNote = idOf('Domain/Models/Note.swift#Note');
const nPoint = idOf('Notes/Views/NotesListView.swift#NotesListView');
const nApp = idOf('App/OrbitNotesApp.swift#OrbitNotesApp');
const viewsCluster = eng.clusters.findIndex((c) => graph.nodes[c.anchor].id === 'OrbitNotes/Features/Notes/Views');
const root = graph.nodes.findIndex((n) => n.kind === 'module');
const topLevel = (graph.children[root] || []);
const byLayer = (L) => new Set(graph.nodes.filter((n) => n.layer === L).map((n) => n.index));
const layerSets = { presentation: byLayer('presentation'), data: byLayer('data'), test: byLayer('test') };
const order = [...graph.nodes].sort((a, b) => a.depth - b.depth || a.id.localeCompare(b.id)).map((n) => n.index);
const rankOf = new Array(N); order.forEach((i, k) => (rankOf[i] = k));

// sector geometry of the top-level subtrees (celestial)
const SECTOR_COLORS = { App: '#F7768E', Features: '#5EE1FF', Domain: '#C9B6FF', Data: '#FFD166', Core: '#8A93A6', Tests: '#B8FF7A' };
const sectors = topLevel.map((ti) => {
  const members = graph.subtree(ti).filter((k) => k !== ti);
  const az = members.map((k) => { const p = G.positions.celestial[k]; return Math.atan2(p[0], p[2]); });
  // circular mean & spread
  const mx = az.reduce((s, a) => s + Math.sin(a), 0), mz = az.reduce((s, a) => s + Math.cos(a), 0);
  const mid = Math.atan2(mx, mz);
  const dev = az.map((a) => { let d = a - mid; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; });
  return { name: graph.nodes[ti].name, mid, lo: mid + Math.min(...dev) - 0.06, hi: mid + Math.max(...dev) + 0.06, color: SECTOR_COLORS[graph.nodes[ti].name] || '#AEB6CF', members };
});

// ------------------------------------------------------------------------------------------------------------
// camera path (Catmull-Rom through keyframes)
const K = [];
const key = (t, pos, tgt, fov = 50) => K.push({ t, pos: V(...pos), tgt: V(...tgt), fov });
function buildCamera() {
  const t02 = S('i02'), t03 = S('i03'), t04 = S('i04'), t05 = S('i05'), t06 = S('i06'), t07 = S('i07'), t08 = S('i08'), t09 = S('i09');
  const t10 = S('i10'), t11 = S('i11'), t12 = S('i12'), t13 = S('i13'), t14 = S('i14'), t15 = S('i15');
  key(0, [0.0, 1.5, 0.6], [0.6, 3.6, -6], 60);
  key(t02 - 1.2, [0.3, 1.6, 0.9], [0.4, 2.9, -6], 58);
  key(t02 + 2.6, [1.0, 3.6, 14.6], [-4.4, 2.5, 0.4], 50);
  key(t03 - 0.2, [2.4, 3.9, 14.4], [-4.0, 2.4, 0.2], 50);
  key(t03 + 3.0, [5.4, 4.4, 13.4], [-3.0, 2.2, 0.0], 50);
  key(t04 - 0.3, [3.4, 9.0, 11.0], [-0.6, 1.4, 0.0], 50);
  key(t04 + 1.0, [0.9, 19.8, 5.4], [0.0, 0.0, 0.9], 50);
  key(t05 - 0.35, [0.3, 20.4, 4.4], [0.0, 0.0, 0.9], 50);
  key(t05 + 0.45, [16.4, 2.5, 2.2], [0.0, 2.3, 0.3], 44);
  key(t06 - 0.2, [15.8, 2.7, 3.6], [0.0, 2.3, 0.3], 44);
  key(t06 + 0.8, [10.4, 4.8, 9.6], [0.0, 2.4, 0.0], 50);
  key(t07 - 0.5, [8.6, 4.9, 8.2], [-0.3, 2.5, 0.0], 50);
  key(t07 + 3.6, [1.2, 5.4, 11.4], [-0.6, 2.6, 0.0], 50);
  key(t08 - 0.4, [-6.4, 4.6, 6.8], [-1.6, 2.7, -1.0], 50);
  key(t08 + 0.7, [-1.25, 3.05, -0.65], [-3.75, 3.0, -2.55], 44);
  key(t09 - 0.6, [-1.05, 3.1, -0.35], [-3.75, 3.05, -2.5], 44);
  key(t09 + 0.6, [0.0, 3.8, 13.4], [0.0, 2.6, -0.5], 50);
  key(t10 - 1.8, [2.4, 4.4, 12.8], [0.0, 2.6, -0.4], 50);
  key(t10 - 0.1, [1.0, 2.55, 1.1], [-1.9, 4.3, 4.6], 56);
  key(t11 - 0.2, [0.75, 2.45, 0.8], [-2.2, 4.4, 4.5], 56);
  key(t12 + 0.15, [0.6, 2.4, 0.55], [-2.6, 4.2, 4.0], 56);
  key(t12 + 1.7, [0.5, 2.35, 0.45], [-2.6, 4.0, 3.9], 56);
  key(t13 - 1.7, [2.6, 2.9, -2.0], [-3.0, 2.2, 3.0], 50);
  key(t13 - 0.1, [0.55, 2.45, 5.1], [0.0, 1.65, -2.0], 50);
  key(t14 - 0.3, [-0.45, 2.35, 4.8], [0.05, 1.7, -2.0], 50);
  key(t14 + 0.8, [9.0, 6.2, 9.0], [0.0, 2.4, 0.0], 50);
  key(t15 - 0.4, [6.4, 5.4, 11.4], [-1.0, 2.4, 0.0], 50);
  key(t15 + 0.8, [1.0, 3.4, 14.8], [-5.3, 2.5, 0.4], 50);
  key(TL.duration + 1, [0.2, 3.2, 14.4], [-5.5, 2.5, 0.4], 50);
}
buildCamera();
function catmull(p0, p1, p2, p3, u) {
  const u2 = u * u, u3 = u2 * u;
  return new THREE.Vector3().addScaledVector(p0, -0.5 * u3 + u2 - 0.5 * u).addScaledVector(p1, 1.5 * u3 - 2.5 * u2 + 1)
    .addScaledVector(p2, -1.5 * u3 + 2 * u2 + 0.5 * u).addScaledVector(p3, 0.5 * u3 - 0.5 * u2);
}
function cameraAt(t) {
  let i = 0; while (i < K.length - 2 && K[i + 1].t <= t) i++;
  const a = K[i], b = K[i + 1]; const u = easeInOut(clamp01((t - a.t) / Math.max(1e-3, b.t - a.t)));
  const p0 = K[Math.max(0, i - 1)], p3 = K[Math.min(K.length - 1, i + 2)];
  // blend: catmull for smoothness, eased parameter for gentle starts/stops
  const pos = catmull(p0.pos, a.pos, b.pos, p3.pos, u), tgt = catmull(p0.tgt, a.tgt, b.tgt, p3.tgt, u);
  return { pos, target: tgt, fov: lerp(a.fov, b.fov, u) };
}

// ------------------------------------------------------------------------------------------------------------
// DOM overlay
const $ = (s) => document.querySelector(s);
const el = { cap: $('#caption span'), black: $('#black'), title: $('#title'), kicker: $('#kicker'), kEn: $('#kicker .en'), kKo: $('#kicker .ko'),
  ingest: $('#ingest'), files: $('#ingest .files'), n0: $('#ingest .n0'), n1: $('#ingest .n1'), n2: $('#ingest .n2'), dial: $('#dial'),
  dialFill: $('#dial .fill'), dialKnob: $('#dial .knob'), dialVal: $('#dial .val'), legend: $('#legend'), starkey: $('#starkey'), layoutchip: $('#layoutchip'),
  bubble: $('#bubble'), voice: $('#voice'), tour: $('#tour'), privacy: $('#privacy'), endcard: $('#endcard'), fx: $('#fx') };

const files = graph.nodes.filter((n) => n.kind === 'file').sort((a, b) => a.id.localeCompare(b.id));
el.files.innerHTML = files.map((f) => `<div><span class="ok">✓</span>${f.id.replace('OrbitNotes/', '').replace(/([^/]+)$/, '<b>$1</b>')}</div>`).join('');
const relCount = graph.edges.filter((e) => e.rel !== 'contains').length;
const typeCount = graph.nodes.filter((n) => n.kind === 'type').length;

function swatch(color, dashed, flow) {
  const d = dashed ? 'stroke-dasharray="7 5"' : '';
  return `<svg width="64" height="22" viewBox="0 0 64 22"><path d="M2 17 Q32 1 ${flow ? 54 : 62} 17" fill="none" stroke="${color}" stroke-width="3.4" stroke-linecap="round" ${d}/>` +
    (flow ? `<path d="M63 18 L52 12 L54 21 Z" fill="${color}"/>` : '') + '</svg>';
}
const LEG = ['presents', 'binds', 'creates', 'conforms'];
const LEGW = { presents: '화면', binds: '상태', creates: '생성', conforms: '채택' };
el.legend.innerHTML = LEG.map((k) => { const r = REL[k]; return `<div class="chip" data-k="${k}">${swatch(r.color, r.dashed, r.flow)}<div><div><span class="t" style="color:${r.color}">${r.ko}</span><span class="e">${r.en}</span></div><div class="h">${r.hint}</div></div></div>`; }).join('');
const legendChips = [...el.legend.querySelectorAll('.chip')];

el.starkey.innerHTML = `<div class="r"><span class="k" style="color:#C9B6FF">모양</span><span class="v">역할 · App / View / Model …</span></div>
<div class="r"><span class="k" style="color:#FFD166">크기</span><span class="v">결합도 · 의존받는 파일 수</span></div>
<div class="r"><span class="k" style="color:#5EE1FF">빛</span><span class="v">최근성 · 최근 수정일수록 밝게</span></div>
<img src="assets/img/node_stars.png">`;
const starRows = [...el.starkey.querySelectorAll('.r')];
const starImg = el.starkey.querySelector('img');

el.privacy.innerHTML = [
  ['P', '#5EE1FF', 'Parsing · 파싱', 'ProjectIngestor'], ['AI', '#9B8CFF', 'AI · 추론', 'FoundationModels'], ['S', '#FF9E64', 'Speech · 음성', 'SpeechAnalyzer'],
].map(([ic, c, t, s]) => `<div class="pc"><div class="ic" style="background:${c}22;color:${c};border:1px solid ${c}66">${ic}</div><div class="t">${t}</div><div class="s">${s}</div><div class="ok">✓ On-device · 기기 안에서</div></div>`).join('');
const privCards = [...el.privacy.querySelectorAll('.pc')];

el.tour.innerHTML = `<div class="top"><span>🚶</span><span>OrbitNotes overview</span><span class="n">1 / 8</span><span class="fl">Follow host</span><span class="sw"></span></div>
<div class="st">Entry point: OrbitNotesApp</div><div class="nar">OrbitNotesApp is the app's entry point, marked @main — everything starts here.</div>`;

const bars = []; const vb = el.voice.querySelector('.bars'); for (let k = 0; k < 22; k++) { const b = document.createElement('i'); vb.appendChild(b); bars.push(b); }
const ripple = document.createElement('div'); ripple.className = 'ripple'; el.fx.appendChild(ripple);
const callouts = [0, 1, 2].map(() => { const d = document.createElement('div'); d.className = 'callout'; el.fx.appendChild(d); d.style.opacity = 0; return d; });

const KICKERS = [
  ['i03', 'On-device ingest', '기기 안에서 읽기'], ['i04', 'Celestial layout', '천구 배치'], ['i05', 'Elevation = layer', '고도 = 아키텍처 레이어'],
  ['i06', 'Time dial', '시간, 네 번째 축'], ['i07', 'Relations by meaning', '의미로 그린 관계'], ['i08', 'Node stars', '카드 위의 별'], ['i09', 'Six skies', '여섯 가지 배치'],
  ['i10', 'Host AI orb', '방장 AI 오브'], ['i11', 'Voice summon', '음성 출두'], ['i13', 'Meetings', 'SharePlay 회의'], ['i14', 'Privacy', '온디바이스'],
];

function envAt(t) { const i = Math.floor(t * TL.envFps); return TL.env[Math.max(0, Math.min(TL.env.length - 1, i))] || 0; }

// ------------------------------------------------------------------------------------------------------------
function state(t) {
  const st = { t, camera: cameraAt(t), layout: { a: 'celestial', b: 'celestial', m: 0 }, relMode: 'all', orbs: 0, stage: true, guides: [], labels: [], extraGlows: [], bloom: 0.85 };
  const t02 = S('i02');
  // 0. chaos → celestial
  const morph0 = t02 - 0.4, morph1 = t02 + 3.2;
  if (t < morph1) {
    const rot = t * 0.025;
    for (let i = 0; i < N; i++) { const b = chaosBase[i]; const c = Math.cos(rot), s = Math.sin(rot); G.positions.chaos[i] = [b[0] * c - b[2] * s, b[1] + 0.06 * Math.sin(t * 0.5 + i), b[0] * s + b[2] * c]; }
    st.layout = { a: 'chaos', b: 'celestial', m: easeInOut(ramp(t, morph0, morph1 - morph0)) };
    const vis = new Float32Array(N);
    for (let i = 0; i < N; i++) vis[i] = clamp01((t - 1.0 - delayHash[i] * 5.2) / 0.7);
    st.nodeVis = vis;
    st.relOpacity = ramp(t, t02 + 0.6, 1.6);
    st.treeOpacity = ramp(t, t02 + 1.2, 1.6);
    st.edgeDraw = (e) => clamp01((t - (t02 + 0.6 + ((e.index * 37) % 100) / 100 * 1.6)) / 1.1);
    st.stars = ramp(t, 1.2, 2.0);
    st.floorOpacity = 0.25 + 0.75 * ramp(t, t02, 2.5);
    // random "unknown" links flicker during "그 관계를…"
    const fl0 = W('i01', '관계');
    if (t > fl0 && t < morph0 + 0.4) {
      for (let k = 0; k < 9; k++) {
        const a = (k * 37 + 11) % N, b = (k * 53 + 29) % N; const ph = (t - fl0) * 1.3 + k * 0.37; const al = Math.max(0, Math.sin(ph * Math.PI)) * 0.5 * (1 - ramp(t, morph0 - 0.6, 0.8));
        if (al > 0.01) st.guides.push({ points: [V(...G.positions.chaos[a]), V(...G.positions.chaos[b])], color: '#8B93A5', alpha: al, width: 0.004 });
      }
    }
  }
  // 1. ingest wave
  const t03 = S('i03');
  if (t > t03 - 0.6 && t < E('i03') + 1.2) {
    const glow = new Float32Array(N); const w0 = t03 + 0.2;
    for (let i = 0; i < N; i++) { const tt = w0 + rankOf[i] / N * 3.6; glow[i] = Math.max(0, 1 - Math.abs(t - tt) / 0.45) * 0.9; }
    st.nodeGlow = glow; st.nodeGlowColor = () => '#B8FF7A';
    st.edgeAlpha = (e) => { if (e.rel !== 'contains') return 1; const tt = w0 + rankOf[e.to] / N * 3.6; return 1 + 3.5 * Math.max(0, 1 - Math.abs(t - tt) / 0.5); };
    st.treeColor = (e) => { const tt = w0 + rankOf[e.to] / N * 3.6; const k = Math.max(0, 1 - Math.abs(t - tt) / 0.5); return k > 0 ? [0.42 + 0.3 * k, 0.45 + 0.55 * k, 0.56 - 0.1 * k] : null; };
  }
  // 2. depth rings + subtree sectors (seen from above)
  const t04 = S('i04');
  if (t > t04 - 0.5 && t < E('i04') + 0.6) {
    const a = win(t, t04 - 0.3, E('i04') + 0.6, 0.6, 0.5);
    const radii = [1.6, 2.85, 4.1, 5.35];
    radii.forEach((r, k) => {
      const on = ramp(t, t04 + 0.25 + k * 0.32, 0.35) * a;
      if (on <= 0) return;
      const pts = []; for (let j = 0; j <= 96; j++) { const th = j / 96 * Math.PI * 2; pts.push(V(Math.sin(th) * r, 0.02, Math.cos(th) * r)); }
      st.guides.push({ points: pts, color: '#9B8CFF', alpha: 0.8 * on, width: 0.012 });
      st.labels.push({ text: `depth ${k + 1}`, p: V(r * Math.sin(0.62), 0.25, r * Math.cos(0.62)), color: '#C9C2FF', size: 0.5, alpha: on, bg: 'rgba(10,12,24,0.7)' });
    });
    const s0 = W('i04', '서브트리');
    sectors.forEach((sec, k) => {
      const on = ramp(t, s0 + k * 0.22, 0.35) * a;
      if (on <= 0) return;
      const R = 6.3;
      for (const th of [sec.lo, sec.hi]) st.guides.push({ points: [V(0, 0.02, 0), V(Math.sin(th) * R, 0.02, Math.cos(th) * R)], color: sec.color, alpha: 0.55 * on, width: 0.012 });
      const arc = []; for (let j = 0; j <= 30; j++) { const th = lerp(sec.lo, sec.hi, j / 30); arc.push(V(Math.sin(th) * R, 0.02, Math.cos(th) * R)); }
      st.guides.push({ points: arc, color: sec.color, alpha: 0.95 * on, width: 0.03 });
      st.labels.push({ text: sec.name, p: V(Math.sin(sec.mid) * (R + 1.0), 0.3, Math.cos(sec.mid) * (R + 1.0)), color: sec.color, size: 0.72, alpha: on, bg: 'rgba(10,12,24,0.7)' });
    });
    if (t > s0) { const glow = new Float32Array(N); const cmap = {}; sectors.forEach((sec, k) => { const on = ramp(t, s0 + k * 0.22, 0.35) * a; for (const m of sec.members) { glow[m] = 0.7 * on; cmap[m] = sec.color; } }); st.nodeGlow = glow; st.nodeGlowColor = (i) => cmap[i] || '#5EE1FF'; }
  }
  // 3. elevation rays from the eye (side view) + "you" at the centre
  const t05 = S('i05');
  if (t > t05 - 0.6 && t < E('i05') + 0.8) {
    const a = win(t, t05 - 0.5, E('i05') + 0.8, 0.5, 0.5);
    const eye = V(0, 1.45, 0);
    const rays = [
      { el: 34, az: sectors.find((s) => s.name === 'Features').mid, color: '#5EE1FF', text: 'Presentation  +34°', set: layerSets.presentation, t: W('i05', '화면') },
      { el: 0, az: sectors.find((s) => s.name === 'Data').mid, color: '#FFD166', text: 'Data  0° · 지평선', set: layerSets.data, t: W('i05', '데이터') },
      { el: -15, az: sectors.find((s) => s.name === 'Tests').mid, color: '#B8FF7A', text: 'Tests  −15°', set: layerSets.test, t: W('i05', '테스트') },
    ];
    const glow = new Float32Array(N); const cmap = {};
    rays.forEach((r) => {
      const on = ramp(t, r.t, 0.35) * a; if (on <= 0) return;
      const d = V(Math.sin(r.az) * Math.cos(r.el * Math.PI / 180), Math.sin(r.el * Math.PI / 180), Math.cos(r.az) * Math.cos(r.el * Math.PI / 180));
      st.guides.push({ points: [eye, eye.clone().addScaledVector(d, 6.4 * easeOut(on))], color: r.color, alpha: 0.9 * on, width: 0.016, dashed: true, dash: 0.16, gap: 0.1 });
      st.labels.push({ text: r.text, p: eye.clone().addScaledVector(d, 7.7).add(V(0, 0.45, 0)), color: r.color, size: 0.62, alpha: on, bg: 'rgba(10,12,24,0.72)' });
      for (const m of r.set) { glow[m] = Math.max(glow[m], 0.85 * on); cmap[m] = r.color; }
    });
    st.nodeGlow = glow; st.nodeGlowColor = (i) => cmap[i] || '#5EE1FF';
    st.avatars = [{ visible: a, color: '#9B8CFF', name: 'you · 사용자', pos: V(0, 0.95, 0), rotY: Math.PI / 2 }];
  }
  // 4. time dial
  const t06 = S('i06');
  let dial = 0;
  if (t > t06 && t < E('i06') + 1.5) {
    dial = easeInOut(ramp(t, t06 + 0.5, 2.2)) * (1 - easeInOut(ramp(t, E('i06') - 0.4, 1.6)));
    st.starGlowBoost = 1 + dial;
    if (dial > 0.02) {
      const tmp = V(0, 0, 0);
      for (let i = 0; i < N; i++) {
        const n = graph.nodes[i]; if (n.kind === 'folder' || n.kind === 'module') continue;
        const a = P0(i); eng.position(i, { a: 'celestial', b: 'celestial', m: 0 }, dial, tmp);
        if (a.distanceTo(tmp) < 0.08) continue;
        const hot = n.recency > 0.5;
        st.guides.push({ points: [a, tmp.clone()], color: hot ? '#5EE1FF' : '#7F7CFF', alpha: (hot ? 0.55 : 0.3) * Math.min(1, dial * 1.4), width: 0.004 });
      }
    }
  }
  st.dial = dial;
  // 5. relations by meaning
  const t07 = S('i07');
  if (t > t07 - 0.4 && t < E('i07') + 0.6) {
    const marks = LEG.map((k) => ({ k, t: W('i07', LEGW[k]) }));
    const allOn = W('i07', '종류');
    let only = null;
    for (const m of marks) if (t >= m.t && t < allOn) only = new Set([m.k]);
    st.onlyKinds = only;
    st.treeOpacity = only ? 0.35 : 1;
    st.lineBoost = 1.25;
  }
  // 6. stars close-up
  const t08 = S('i08');
  if (t > t08 - 0.3 && t < E('i08') + 0.4) {
    st.starScale = 1 + 0.32 * win(t, t08 - 0.2, E('i08') + 0.4, 0.6, 0.6);
    const k = W('i08', '결합도'); const r = W('i08', '최근성');
    if (t > r) { const g = new Float32Array(N); const sg = 0.5 + 0.5 * Math.sin((t - r) * 5.5); graph.nodes.forEach((n, i) => { g[i] = 0.55 * n.recency * win(t, r, E('i08') + 0.4, 0.3, 0.4) * sg; }); st.nodeGlow = g; st.nodeGlowColor = () => '#FFFFFF'; }
    if (t > k && t < r) st.highlight = new Set([nNoteFile, nNote]);
  }
  // 7. six skies
  const t09 = S('i09');
  if (t > t09 && t < S('i10') + 0.2) {
    const s0 = W('i09', '구') - 0.05, step = (S('i10') - 0.9 - s0) / 6;
    const names = ['celestial', 'sphere', 'wall', 'spiral', 'treeRadial', 'shells', 'celestial'];
    const seq = names.slice(0, 6).map((a, k) => [a, names[k + 1], s0 + k * step]);
    let cur = null;
    for (const [a, b, ts] of seq) if (t >= ts) cur = { a, b, ts };
    if (cur) st.layout = { a: cur.a, b: cur.b, m: easeInOut(ramp(t, cur.ts, Math.min(1.15, (S('i10') - 0.9 - s0) / 6 * 0.72))) };
    st.particles = true;
  }
  // 8. host orb + cluster orbs + dock
  const t10 = S('i10');
  const orbVis = win(t, t10 - 0.4, S('i13') - 1.3, 0.9, 0.6);
  st.orbs = orbVis;
  const tap = W('i10', '탭하면'), dockEnd = tap + 1.0, undock0 = E('i10') + 0.35, undock1 = undock0 + 0.8;
  if (orbVis > 0) {
    if (!state.hostRest) { const c = cameraAt(t10 + 0.2); const f = c.target.clone().sub(c.pos).normalize(); const r = new THREE.Vector3().crossVectors(f, V(0, 1, 0)).normalize(); const u = new THREE.Vector3().crossVectors(r, f);
      state.hostRest = c.pos.clone().addScaledVector(f, 1.55).addScaledVector(r, 0.42).addScaledVector(u, -0.28); }
    const rest = state.hostRest;
    const vc = eng.clusters[viewsCluster];
    // cluster centroid (same rule as engine)
    const ctr = V(0, 0, 0); for (const m of vc.members) ctr.add(P0(m)); ctr.divideScalar(vc.members.length);
    let pos = rest, scale = 1, energy = 0.22, vis = ramp(t, t10 - 0.2, 0.8);
    if (t >= tap + 0.25 && t < undock1) {
      const k = easeInOut(ramp(t, tap + 0.25, dockEnd - tap - 0.25));
      const ku = easeInOut(ramp(t, undock0, undock1 - undock0));
      const a = rest.clone().lerp(ctr, k); pos = a.lerp(rest, ku);
      scale = (1 - k * 0.85) + ku * k * 0.85;
      if (k >= 1 && ku <= 0) vis = 0;
    }
    if (t >= dockEnd && t < undock0) st.docked = viewsCluster;
    const listening = t > S('i11') - 0.2 && t < E('i11') + 0.3, thinking = t >= E('i11') + 0.3 && t < S('i12') + 0.6;
    energy = thinking ? 1.0 : listening ? 0.55 : 0.22;
    st.host = { visible: vis * orbVis, pos, scale: scale * 0.85, energy };
    // tap ripple (DOM)
    const rp = eng.toScreen(ctr);
    const rk = ramp(t, tap - 0.05, 0.7);
    ripple.style.opacity = rk > 0 && rk < 1 ? (1 - rk) : 0; ripple.style.left = rp.x + 'px'; ripple.style.top = rp.y + 'px';
    ripple.style.width = ripple.style.height = (14 + rk * 120) + 'px';
    st._bubbleAnchor = rp;
  } else ripple.style.opacity = 0;
  // 9. summon + beacon (voice)
  const sumT = S('i12') + 0.25;
  const sumEnd = S('i13') - 1.45;
  if (t > sumT - 0.6 && t < sumEnd) {
    const k = ramp(t, sumT, 1.1);
    if (!state.summonTarget) { const c = cameraAt(sumT); const f = c.target.clone().sub(c.pos).normalize(); state.summonTarget = c.pos.clone().addScaledVector(f, 0.62).add(V(0, -0.07, 0)); }
    if (t >= sumT) st.summon = { node: nDetail, k: k * win(t, sumT, sumEnd, 0.01, 0.55), target: state.summonTarget, width: 0.42 };
    st.highlight = new Set(atStateViews);
    st.beacons = [{ node: nDetail, age: Math.max(0, t - (sumT + 0.3)), alpha: win(t, sumT + 0.2, sumEnd, 0.2, 0.5) }];
    st.selected = nDetail; st.selectColor = '#FFD166';
  }
  // 10. meeting in front of the wall layout (the host's layout choice syncs to everyone)
  const t13 = S('i13');
  const w0 = t13 - 1.45, w1 = E('i13') + 0.5;
  if (t > w0 && t < w1 + 1.4) {
    if (t < w1) st.layout = { a: 'celestial', b: 'wall', m: easeInOut(ramp(t, w0, 1.3)) };
    else st.layout = { a: 'wall', b: 'celestial', m: easeInOut(ramp(t, w1, 1.3)) };
  }
  if (t > t13 - 0.9 && t < E('i13') + 1.0) {
    const a = win(t, t13 - 0.9, E('i13') + 1.0, 0.8, 0.6);
    const people = [['Coulson · host', '#9B8CFF'], ['Mina', '#6FB6FF'], ['Jae', '#FF9E64'], ['Ari', '#9ECE6A']];
    const look = V(0, 1.5, -3.2);
    st.avatars = people.map(([name, color], k) => ({ name, color, visible: a * ramp(t, t13 - 0.7 + k * 0.22, 0.5), lookAt: look }));
    const pk = W('i13', '레이저'); const pin = W('i13', '리뷰'); const tour = W('i13', '가이드');
    if (t > pk && a > 0.5) {
      const ang = 1 / 6 * Math.PI * 2; const origin = V(Math.sin(ang) * 1.2, 0.44, Math.cos(ang) * 1.2);
      const target = P0(nPoint, 'wall').add(V(0.04 * Math.sin(t * 2.1), 0.03 * Math.sin(t * 1.7), 0.02));
      st.pointer = { origin, hit: origin.clone().lerp(target, easeOut(ramp(t, pk, 0.45))), color: '#6FB6FF' };
    }
    if (t > pin) st.pins = { [nPoint]: 1 };
    const hl = new Set(); if (t > pk) hl.add(nPoint); if (t > tour) hl.add(nApp);
    st.highlight = hl;
    if (t > tour) st.beacons = [{ node: nApp, age: t - tour, alpha: win(t, tour, E('i13') + 0.9, 0.2, 0.5) }];
  }
  // 11. privacy + end: softer
  if (t > S('i14') - 0.4) { st.relOpacity = 1; }
  // fade to black at the very end
  return st;
}
state.summonTarget = null;

function overlay(t, st) {
  const tl = TL.lines;
  // black
  const blackA = Math.max(1 - ramp(t, 0.15, 2.2), ramp(t, TL.duration - 1.4, 1.3));
  el.black.style.opacity = blackA;
  // caption
  let cur = null; for (const l of tl) if (t >= l.start - 0.12 && t <= l.end + 0.35) cur = l;
  if (cur && cur.id !== 'i15') {
    if (el.cap.textContent !== cur.cap) el.cap.textContent = cur.cap;
    el.cap.style.opacity = win(t, cur.start - 0.12, cur.end + 0.35, 0.18, 0.22);
    el.cap.style.color = cur.id === 'i11' ? '#FFD1D6' : '#F3F5FB';
  } else el.cap.style.opacity = 0;
  // title
  const t02 = S('i02');
  const ta = win(t, t02 + 0.1, S('i03') - 0.5, 0.9, 0.7);
  el.title.style.opacity = ta; el.title.style.transform = `translateY(${(1 - ease(ramp(t, t02 + 0.1, 1.2))) * 18}px) scale(${1 + 0.02 * ramp(t, t02, 6)})`;
  // kicker
  let kk = null; for (const [id, en, ko] of KICKERS) if (t >= S(id) - 0.4) kk = [id, en, ko];
  const kEnd = (id) => { const i = KICKERS.findIndex((x) => x[0] === id); const nxt = KICKERS[i + 1]; return nxt ? S(nxt[0]) - 0.4 : S('i15') - 0.3; };
  if (kk && t < S('i15') - 0.3) { if (el.kEn.textContent !== kk[1]) { el.kEn.textContent = kk[1]; el.kKo.textContent = kk[2]; } el.kicker.style.opacity = win(t, S(kk[0]) - 0.4, kEnd(kk[0]), 0.4, 0.35); }
  else el.kicker.style.opacity = 0;
  // ingest
  const t03 = S('i03');
  const ia = win(t, t03 - 0.3, E('i03') + 0.9, 0.5, 0.5);
  el.ingest.style.opacity = ia; el.ingest.style.transform = `translateX(${(1 - ease(ramp(t, t03 - 0.3, 0.6))) * -24}px)`;
  if (ia > 0) {
    const p = easeInOut(ramp(t, t03 + 0.2, 3.6));
    const shown = Math.round(p * files.length);
    el.files.scrollTop = Math.max(0, shown * 30 - 270);
    [...el.files.children].forEach((d, k) => (d.style.opacity = k < shown ? 1 : 0.0));
    el.n0.textContent = Math.round(p * files.length); el.n1.textContent = Math.round(p * typeCount); el.n2.textContent = Math.round(p * relCount);
  }
  // dial
  const da = win(t, S('i06') - 0.2, E('i06') + 1.4, 0.4, 0.4);
  el.dial.style.opacity = da;
  if (da > 0) { const d = st.dial; const x = (d + 1) / 2; el.dialKnob.style.left = (x * 100) + '%'; el.dialFill.style.left = '50%'; el.dialFill.style.width = Math.abs(x - 0.5) * 100 + '%'; if (x < 0.5) el.dialFill.style.left = x * 100 + '%'; el.dialVal.textContent = (d >= 0 ? '+' : '') + d.toFixed(2); }
  // legend chips
  const la = win(t, S('i07') - 0.2, E('i07') + 0.5, 0.3, 0.4);
  legendChips.forEach((c, k) => {
    const tk = W('i07', LEGW[LEG[k]]);
    const on = ramp(t, tk - 0.1, 0.3) * la;
    c.style.opacity = on; c.style.transform = `translateX(${(1 - ease(ramp(t, tk - 0.1, 0.35))) * -20}px)`;
    const active = st.onlyKinds && st.onlyKinds.has(LEG[k]);
    c.style.borderColor = active ? REL[LEG[k]].color : 'rgba(255,255,255,0.10)';
    c.style.background = active ? 'rgba(28,32,56,0.86)' : 'rgba(16,20,36,0.72)';
  });
  // star key
  const sa = win(t, S('i08') - 0.1, E('i08') + 0.4, 0.4, 0.4);
  el.starkey.style.opacity = sa;
  if (sa > 0) {
    const ts = [W('i08', '역할'), W('i08', '결합도'), W('i08', '최근성')];
    starRows.forEach((r, k) => (r.style.opacity = ramp(t, ts[k] - 0.1, 0.3)));
    starImg.style.opacity = ramp(t, ts[0], 0.5);
  }
  // star callouts (3-D anchored)
  callouts.forEach((c) => (c.style.opacity = 0));
  if (sa > 0) {
    const cNote = eng.cards[nNoteFile];
    const sp = (i) => { const c = eng.cards[i]; const n = c.node; return c.group.localToWorld(V((-c.width / 2 + n.starSize * 0.55) / c.width, (c.width * 352 / 512 / 2 + n.starSize * 0.65) / c.width + 0.18, 0)); };
    const k1 = W('i08', '결합도');
    const p1 = eng.toScreen(sp(nNoteFile)); const c1 = callouts[0];
    c1.textContent = 'Note.swift · fan-in 23 → 큰 별'; c1.style.color = '#FFD166'; c1.style.left = p1.x + 'px'; c1.style.top = (p1.y - 16) + 'px';
    c1.style.opacity = ramp(t, k1, 0.3) * sa;
  }
  // layout chip
  const t09 = S('i09');
  const lca = win(t, W('i09', '구') - 0.05, S('i10') - 0.5, 0.25, 0.4);
  el.layoutchip.style.opacity = lca;
  if (lca > 0) {
    const L = st.layout; const nm = L.m > 0.04 ? L.b : L.a; const info = LAYOUT[nm];
    if (el.layoutchip.dataset.n !== nm) { el.layoutchip.dataset.n = nm; el.layoutchip.querySelector('.name').textContent = info.label; el.layoutchip.querySelector('.axes').textContent = info.axes; }
  }
  // bubble (host answer while docked)
  const tap = W('i10', '탭하면');
  const ba = win(t, tap + 1.0, E('i10') + 0.4, 0.35, 0.35);
  const bb = win(t, S('i12') + 0.6, E('i12') + 0.9, 0.35, 0.4);
  el.bubble.style.opacity = Math.max(ba, bb);
  if (ba > 0) {
    const ap = st._bubbleAnchor || { x: 900, y: 300 };
    el.bubble.style.left = Math.min(1220, Math.max(60, ap.x + 70)) + 'px'; el.bubble.style.top = Math.min(640, Math.max(150, ap.y - 40)) + 'px';
    el.bubble.querySelector('b').textContent = 'Docked in Views'; el.bubble.querySelector('i').textContent = 'Apple Intelligence · on-device';
    el.bubble.querySelector('.txt').innerHTML = '이 뭉치에는 SwiftUI 뷰 5개가 있어요 — <code>NotesListView</code>, <code>NoteDetailView</code>, <code>NoteEditorView</code>, <code>NoteRowView</code>, <code>TagChipView</code>.';
  } else if (bb > 0) {
    el.bubble.style.left = '1150px'; el.bubble.style.top = '150px';
    el.bubble.querySelector('b').textContent = 'Host orb · free'; el.bubble.querySelector('i').textContent = 'locateCode';
    el.bubble.querySelector('.txt').innerHTML = 'The project contains five SwiftUI views that use <code>@State</code>: NoteDetailView, NoteEditorView, NotesListView, SearchView and SyncSettingsView.';
  }
  const og = el.bubble.querySelector('.orbglyph'); og.style.setProperty('--r1', (t * 120) + 'deg'); og.style.setProperty('--r2', (-t * 160) + 'deg');
  // voice capsule
  const t11 = S('i11');
  const va = win(t, t11 - 0.5, E('i11') + 0.7, 0.3, 0.4);
  el.voice.style.opacity = va;
  if (va > 0) {
    const l = line('i11'); const full = '콘스텔, @State 쓰는 뷰 찾아 줄래?';
    const p = clamp01((t - l.start) / l.dur); el.voice.querySelector('.txt').textContent = t < l.start ? 'Listening… · 듣는 중' : full.slice(0, Math.max(1, Math.round(p * full.length)));
    bars.forEach((b, k) => { const e = envAt(t - k * 0.012); b.style.height = (6 + 34 * e * (0.55 + 0.45 * Math.sin(k * 1.7 + t * 9))) + 'px'; });
  }
  // tour bar
  const tb = win(t, W('i13', '가이드') - 0.2, E('i13') + 1.0, 0.35, 0.4);
  el.tour.style.opacity = tb;
  // privacy
  const pa = win(t, S('i14') - 0.2, E('i14') + 0.8, 0.4, 0.5);
  const pt = [W('i14', '파싱'), W('i14', 'AI') , W('i14', '음성')];
  privCards.forEach((c, k) => { const on = ramp(t, (isFinite(pt[k]) ? pt[k] : S('i14') + k * 0.8) - 0.1, 0.35) * pa; c.style.opacity = on; c.style.transform = `translateY(${(1 - ease(on)) * 16}px)`; });
  // end card
  const ea = ramp(t, S('i15') - 0.2, 0.9);
  el.endcard.style.opacity = ea; el.endcard.style.transform = `translateY(${(1 - ease(ea)) * 16}px)`;
}

const scrim = document.getElementById('titlescrim');
// ---- events for the score (music.py): sparkles / whooshes land on these visual moments
function buildEvents() {
  const ev = []; const add = (t, kind, i = 0) => ev.push({ t: +t.toFixed(3), kind, i });
  // chaos: a dozen cards twinkle into view
  [...graph.nodes].map((n, i) => ({ i, t: 1.0 + delayHash[i] * 5.2 })).filter((x, k) => k % 10 === 0).forEach((x, k) => add(x.t + 0.3, 'twinkle', k));
  add(S('i02') - 0.4, 'morph', 0); add(S('i02') + 0.1, 'title');
  for (let k = 0; k < 8; k++) add(S('i03') + 0.3 + k * 0.45, 'tick', k);
  for (let k = 0; k < 4; k++) add(S('i04') + 0.25 + k * 0.32, 'ring', k);
  const s0 = W('i04', '서브트리'); for (let k = 0; k < 6; k++) add(s0 + k * 0.22, 'sector', k);
  ['화면', '데이터', '테스트'].forEach((w, k) => add(W('i05', w), 'ray', k));
  add(S('i06') + 0.5, 'whooshUp'); add(E('i06') - 0.4, 'whooshDown');
  LEG.forEach((k, j) => add(W('i07', LEGW[k]), 'chip', j));
  ['역할', '결합도', '최근성'].forEach((w, k) => add(W('i08', w), 'star', k));
  const m0 = W('i09', '구') - 0.05, step = (S('i10') - 0.9 - m0) / 6; for (let k = 0; k < 6; k++) add(m0 + k * step, 'morph', k + 1);
  add(S('i10') - 0.2, 'orbs'); const tap = W('i10', '탭하면'); add(tap, 'tap'); add(tap + 1.0, 'dock'); add(E('i10') + 0.35, 'undock');
  add(S('i11') - 0.5, 'mic'); const sumT = S('i12') + 0.25; add(sumT, 'summon'); add(sumT + 0.3, 'beacon');
  add(S('i13') - 1.45, 'morph', 7);
  for (let k = 0; k < 4; k++) add(S('i13') - 0.7 + k * 0.22, 'avatar', k);
  add(W('i13', '레이저'), 'pointer'); add(W('i13', '리뷰'), 'pin'); add(W('i13', '가이드'), 'beacon', 1);
  add(E('i13') + 0.5, 'morph', 8);
  ['파싱', 'AI', '음성'].forEach((w, k) => add(W('i14', w), 'chime', k));
  add(S('i15') - 0.2, 'end');
  return ev.sort((a, b) => a.t - b.t);
}
window.EVENTS = buildEvents();
window.seek = (t) => {
  const st = state(t);
  eng.render(st);
  overlay(t, st);
  scrim.style.opacity = Math.max(+el.title.style.opacity || 0, +el.endcard.style.opacity || 0, (+el.ingest.style.opacity || 0) * 0.85, (+el.legend.style.opacity || 0));
  return true;
};
window.DURATION = TL.duration;
window.__eng = eng; window.__state = state; window.__W = W;
const t0 = parseFloat(Q.get('t') || '0');
window.seek(t0);
window.ready = true;
