// Constellate scene renderer for the README videos (three.js r170, deterministic: everything is a function of the
// state passed to render()). Geometry rules are ports of ConstellateKit: EdgeSceneBuilder.arc / tubeRadius / opacity,
// StarEncoder.anchor, ConstellationLayout.project, FlowParticles; visuals use the app's own Blender textures and
// USDZ assets (converted to GLB), so the look follows the app and its Blender renders.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { REL, DARK, CYCLE_COLOR, rgbOfHex } from './theme.js';
import { drawCard, cardContent, CARD_W, CARD_H } from './cards.js';

export const ASPECT = CARD_H / CARD_W;
const V3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);
const clamp01 = (x) => Math.max(0, Math.min(1, x));
export const ease = (x) => { x = clamp01(x); return x * x * (3 - 2 * x); };
export const easeInOut = (x) => { x = clamp01(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
export const easeOut = (x) => { x = clamp01(x); return 1 - Math.pow(1 - x, 3); };

// ---------------------------------------------------------------------------------------------------------------
// Graph model (from web/data/graph.js) + GraphInsights-style file metrics
// ---------------------------------------------------------------------------------------------------------------
export function buildGraph(G) {
  const nodes = G.nodes.map((n, i) => ({ ...n, index: i }));
  const children = {};
  nodes.forEach((n, i) => { if (n.parent !== null && n.parent !== undefined) (children[n.parent] = children[n.parent] || []).push(i); });
  for (const n of nodes) {
    let d = 0, p = n.parent; while (p !== null && p !== undefined) { d++; p = nodes[p].parent; }
    n.depth = d;
    const r = n.cardWidth / 2;
    n.lineCount = r >= 0.3199 ? 0 : Math.max(1, Math.round(Math.pow((r - 0.08) * 90, 2)));
  }
  // folder / module line counts = sum of files below (cards are clamped at max radius)
  const sub = (i) => [i, ...(children[i] || []).flatMap(sub)];
  for (const n of nodes) if (n.kind === 'folder' || n.kind === 'module') n.lineCount = sub(n.index).filter(k => nodes[k].kind === 'file').reduce((s, k) => s + nodes[k].lineCount, 0);
  const edges = G.edges.map((e, k) => ({ ...e, index: k }));
  const fileOf = (i) => { const n = nodes[i]; if (n.kind === 'file') return i; if (n.kind === 'type' || n.kind === 'extensionDecl') return n.parent !== null && nodes[n.parent].kind === 'file' ? n.parent : fileOf(n.parent); return null; };
  const out = {}, inc = {};
  for (const e of edges) {
    if (e.rel === 'contains' || e.rel === 'notifies' || e.rel === 'imports') continue;
    const a = fileOf(e.from), b = fileOf(e.to);
    if (a === null || b === null || a === b) continue;
    (out[a] = out[a] || new Set()).add(b); (inc[b] = inc[b] || new Set()).add(a);
  }
  const impact = (f) => { const seen = new Set(); const st = [f]; while (st.length) { const x = st.pop(); for (const y of (inc[x] || [])) if (!seen.has(y) && y !== f) { seen.add(y); st.push(y); } } return seen.size; };
  // Tarjan SCC for cycles
  let idx = 0; const stack = [], on = new Set(), ix = {}, low = {}, cycles = [];
  const strong = (v) => {
    ix[v] = low[v] = idx++; stack.push(v); on.add(v);
    for (const w of (out[v] || [])) { if (ix[w] === undefined) { strong(w); low[v] = Math.min(low[v], low[w]); } else if (on.has(w)) low[v] = Math.min(low[v], ix[w]); }
    if (low[v] === ix[v]) { const comp = []; let w; do { w = stack.pop(); on.delete(w); comp.push(w); } while (w !== v); if (comp.length > 1) cycles.push(comp); }
  };
  nodes.forEach((n, i) => { if (n.kind === 'file' && ix[i] === undefined) strong(i); });
  const metrics = (i) => {
    const f = fileOf(i); if (f === null) return null;
    const ca = (inc[f] || new Set()).size, ce = (out[f] || new Set()).size;
    return { file: f, fanIn: ca, fanOut: ce, instability: ca + ce ? ce / (ca + ce) : null, impact: impact(f), cycle: cycles.findIndex(c => c.includes(f)) };
  };
  return { nodes, edges, children, metrics, fileOf, cycles, subtree: sub, G };
}

// ---------------------------------------------------------------------------------------------------------------
// Layout projection and relation arcs (ConstellationLayout.project / EdgeSceneBuilder.arc)
// ---------------------------------------------------------------------------------------------------------------
const TIME_DEPTH = 1.2;
function projectPoint(base, center, w, dial, spherical, out) {
  out.copy(base);
  if (!dial) return out;
  const d = Math.max(-1, Math.min(1, dial)), t = w - 0.5;
  if (spherical) {
    const r = new THREE.Vector3().subVectors(base, center); const len = r.length();
    const dir = len > 1e-4 ? r.divideScalar(len) : new THREE.Vector3(0, 0, -1);
    return out.addScaledVector(dir, t * d * TIME_DEPTH);
  }
  const r = new THREE.Vector3(base.x - center.x, 0, base.z - center.z); const len = r.length();
  const dir = len > 1e-4 ? r.divideScalar(len) : new THREE.Vector3(0, 0, -1);
  out.addScaledVector(dir, t * d * TIME_DEPTH); out.y += t * d * TIME_DEPTH * 0.35; return out;
}

function anyPerp(v) { const h = Math.abs(v.y) < 0.9 ? new THREE.Vector3(0, 1, 0) : new THREE.Vector3(1, 0, 0); return new THREE.Vector3().crossVectors(v, h).normalize(); }

export function arcPoints(a, b, center, rel, inward = false) {
  const st = REL[rel];
  const dist = a.distanceTo(b);
  const chord = new THREE.Vector3().subVectors(b, a).divideScalar(Math.max(dist, 1e-6));
  const mid = new THREE.Vector3().addVectors(a, b).multiplyScalar(0.5);
  let out = new THREE.Vector3().subVectors(mid, center); if (out.length() < 1e-3) out.set(0, 1, 0);
  let n0 = out.clone().addScaledVector(chord, -out.dot(chord));
  if (n0.length() < 1e-4) { const up = new THREE.Vector3(0, 1, 0); n0 = up.clone().addScaledVector(chord, -up.dot(chord)); if (n0.length() < 1e-4) n0 = anyPerp(chord); }
  n0.normalize();
  const n = n0.clone().multiplyScalar(Math.cos(st.lane)).add(new THREE.Vector3().crossVectors(chord, n0).multiplyScalar(Math.sin(st.lane)));
  const height = Math.min(1.4, 0.25 * dist + 0.16) * st.altitude * (inward ? -1 : 1);
  const control = mid.clone().addScaledVector(n, height);
  const segments = Math.max(10, Math.min(32, Math.floor(dist / 0.22) + 8));
  const pts = [];
  for (let i = 0; i <= segments; i++) { const t = i / segments, s = 1 - t; pts.push(new THREE.Vector3().addScaledVector(a, s * s).addScaledVector(control, 2 * s * t).addScaledVector(b, t * t)); }
  return pts;
}

function tubeRadius(rel, emphasis, cycle) {
  const base = rel === 'uses' || rel === 'imports' ? 0.0021 : 0.0031;
  const k = emphasis === 'faint' ? 0.8 : emphasis === 'focus' ? 1.6 : 1;
  return base * k * (cycle ? 1.4 : 1);
}
function batchOpacity(rel, emphasis, cycle) {
  if (!rel) return emphasis === 'faint' ? 0.10 : 0.30;
  const quiet = rel === 'uses' || rel === 'imports';
  if (emphasis === 'faint') return quiet ? 0.05 : 0.10;
  if (emphasis === 'normal') return cycle ? 0.85 : (quiet ? 0.26 : 0.62);
  return 0.95;
}

function cumulative(points) { const c = [0]; for (let i = 1; i < points.length; i++) c.push(c[i - 1] + points[i].distanceTo(points[i - 1])); return c; }
function pointAt(points, cum, s) {
  let i = 1; while (i < cum.length - 1 && cum[i] < s) i++;
  const span = Math.max(cum[i] - cum[i - 1], 1e-6), k = clamp01((s - cum[i - 1]) / span);
  return points[i - 1].clone().lerp(points[i], k);
}

// ---------------------------------------------------------------------------------------------------------------
// GPU helpers: anti-aliased glow ribbons (for tubes) and glow points (sprites)
// ---------------------------------------------------------------------------------------------------------------
const LINE_VS = `
attribute vec3 aStart; attribute vec3 aEnd; attribute vec2 aU; attribute vec4 aColor; attribute float aWidth;
uniform vec2 uResolution; uniform float uMinPx; uniform float uMaxPx; uniform float uGlow; uniform float uFocal; uniform float uNear;
varying float vAcross; varying float vU; varying vec4 vColor; varying float vCore; varying float vCover;
void main() {
  vec4 s = modelViewMatrix * vec4(aStart, 1.0); vec4 e = modelViewMatrix * vec4(aEnd, 1.0);
  float nz = -uNear;
  if (s.z > nz && e.z > nz) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
  if (s.z > nz) { s = mix(s, e, (nz - s.z) / (e.z - s.z)); }
  if (e.z > nz) { e = mix(e, s, (nz - e.z) / (s.z - e.z)); }
  vec4 cs = projectionMatrix * s; vec4 ce = projectionMatrix * e;
  vec2 ps = cs.xy / cs.w * uResolution * 0.5; vec2 pe = ce.xy / ce.w * uResolution * 0.5;
  vec2 dir = pe - ps; float len = length(dir); dir = len > 1e-4 ? dir / len : vec2(1.0, 0.0);
  vec2 perp = vec2(-dir.y, dir.x);
  float t = position.x;
  vec4 c = mix(cs, ce, t);
  float viewZ = -mix(s.z, e.z, t);
  float truePx = aWidth * uFocal / max(viewZ, 0.02);
  float corePx = clamp(truePx, uMinPx, uMaxPx);
  float halfPx = corePx * (1.0 + uGlow) + 0.75;
  c.xy += perp * position.y * halfPx * 2.0 / uResolution * c.w;
  gl_Position = c;
  vAcross = position.y * halfPx; vU = mix(aU.x, aU.y, t); vColor = aColor; vCore = corePx; vCover = min(1.0, truePx / max(uMinPx, 1e-3));
}`;
const LINE_FS = `
uniform sampler2D uRamp; uniform float uOpacity; uniform float uGlowAmt; uniform float uGlow;
varying float vAcross; varying float vU; varying vec4 vColor; varying float vCore; varying float vCover;
void main() {
  float d = abs(vAcross);
  float core = 1.0 - smoothstep(vCore - 0.6, vCore + 0.6, d);
  float g = d / max(vCore * (1.0 + uGlow), 1.0);
  float glow = exp(-g * g * 4.0) * uGlowAmt;
  float ramp = texture2D(uRamp, vec2(clamp(vU, 0.0, 1.0), 0.5)).a;
  float a = (core * mix(0.72, 1.0, vCover) + glow) * vColor.a * uOpacity * ramp;
  if (a < 0.002) discard;
  gl_FragColor = vec4(vColor.rgb * a, a);
}`;

export class GlowLines {
  constructor(ramp, { minPx = 0.95, glow = 2.4, glowAmt = 0.4, blending = 'add' } = {}) {
    const quad = new THREE.InstancedBufferGeometry();
    quad.setAttribute('position', new THREE.Float32BufferAttribute([0, -1, 0, 1, -1, 0, 1, 1, 0, 0, -1, 0, 1, 1, 0, 0, 1, 0], 3));
    this.geometry = quad; this.capacity = 0;
    this.material = new THREE.ShaderMaterial({
      vertexShader: LINE_VS, fragmentShader: LINE_FS, transparent: true, depthWrite: false, depthTest: true,
      blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: blending === 'add' ? THREE.OneFactor : THREE.OneMinusSrcAlphaFactor,
      uniforms: { uResolution: { value: new THREE.Vector2(1920, 1080) }, uMinPx: { value: minPx }, uMaxPx: { value: 3.2 }, uGlow: { value: glow }, uGlowAmt: { value: glowAmt },
        uFocal: { value: 1000 }, uNear: { value: 0.06 }, uRamp: { value: ramp }, uOpacity: { value: 1 } },
    });
    this.mesh = new THREE.Mesh(quad, this.material); this.mesh.frustumCulled = false;
    this.ensure(12000);
  }
  ensure(n) {
    if (n <= this.capacity) return;
    const cap = Math.max(n, Math.ceil(this.capacity * 2));
    const grow = (old, k) => { const a = new Float32Array(cap * k); if (old) a.set(old); return a; };
    this.aStart = grow(this.aStart, 3); this.aEnd = grow(this.aEnd, 3); this.aU = grow(this.aU, 2);
    this.aColor = grow(this.aColor, 4); this.aWidth = grow(this.aWidth, 1);
    const g = this.geometry;
    g.setAttribute('aStart', new THREE.InstancedBufferAttribute(this.aStart, 3)); g.setAttribute('aEnd', new THREE.InstancedBufferAttribute(this.aEnd, 3));
    g.setAttribute('aU', new THREE.InstancedBufferAttribute(this.aU, 2)); g.setAttribute('aColor', new THREE.InstancedBufferAttribute(this.aColor, 4));
    g.setAttribute('aWidth', new THREE.InstancedBufferAttribute(this.aWidth, 1));
    this.capacity = cap;
  }
  begin() { this.count = 0; }
  push(a, b, u0, u1, color, alpha, width) {
    if (this.count >= this.capacity) this.ensure(this.count + 1);
    const i = this.count++;
    this.aStart[i * 3] = a.x; this.aStart[i * 3 + 1] = a.y; this.aStart[i * 3 + 2] = a.z;
    this.aEnd[i * 3] = b.x; this.aEnd[i * 3 + 1] = b.y; this.aEnd[i * 3 + 2] = b.z;
    this.aU[i * 2] = u0; this.aU[i * 2 + 1] = u1;
    this.aColor[i * 4] = color[0]; this.aColor[i * 4 + 1] = color[1]; this.aColor[i * 4 + 2] = color[2]; this.aColor[i * 4 + 3] = alpha;
    this.aWidth[i] = width;
  }
  /** Polyline with optional draw fraction; u runs 0→1 along the whole polyline. */
  pushPolyline(points, color, alpha, width, frac = 1, cum = null) {
    if (frac <= 0) return;
    cum = cum || cumulative(points); const total = cum[cum.length - 1] || 1e-6; const lim = total * frac;
    for (let i = 1; i < points.length; i++) {
      if (cum[i - 1] >= lim) break;
      const b = cum[i] <= lim ? points[i] : pointAt(points, cum, lim);
      this.push(points[i - 1], b, cum[i - 1] / total, Math.min(cum[i], lim) / total, color, alpha, width);
    }
  }
  end(camera, res) {
    const g = this.geometry; g.instanceCount = this.count;
    for (const k of ['aStart', 'aEnd', 'aU', 'aColor', 'aWidth']) { g.attributes[k].needsUpdate = true; g.attributes[k].updateRanges = []; }
    this.material.uniforms.uResolution.value.set(res.x, res.y);
    this.material.uniforms.uFocal.value = res.y * 0.5 / Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2);
  }
}

const PT_VS = `
attribute vec4 aColor; attribute float aSize; uniform float uFocal; varying vec4 vColor;
void main() { vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mv;
  float px = aSize * uFocal / max(-mv.z, 0.02); gl_PointSize = clamp(px, 0.0, 900.0); vColor = aColor;
  if (-mv.z < 0.05) gl_PointSize = 0.0; }`;
const PT_FS = `
uniform sampler2D uMap; varying vec4 vColor;
void main() { float a = texture2D(uMap, gl_PointCoord).a * vColor.a; if (a < 0.003) discard; gl_FragColor = vec4(vColor.rgb * a, a); }`;

export class GlowPoints {
  constructor(map, cap = 2048) {
    this.cap = cap;
    this.pos = new Float32Array(cap * 3); this.col = new Float32Array(cap * 4); this.size = new Float32Array(cap);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3)); g.setAttribute('aColor', new THREE.BufferAttribute(this.col, 4));
    g.setAttribute('aSize', new THREE.BufferAttribute(this.size, 1));
    this.geometry = g;
    this.material = new THREE.ShaderMaterial({ vertexShader: PT_VS, fragmentShader: PT_FS, transparent: true, depthWrite: false, depthTest: true,
      blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, uniforms: { uMap: { value: map }, uFocal: { value: 1000 } } });
    this.points = new THREE.Points(g, this.material); this.points.frustumCulled = false;
  }
  begin() { this.n = 0; }
  push(p, color, alpha, size) {
    if (this.n >= this.cap) return; const i = this.n++;
    this.pos[i * 3] = p.x; this.pos[i * 3 + 1] = p.y; this.pos[i * 3 + 2] = p.z;
    this.col[i * 4] = color[0]; this.col[i * 4 + 1] = color[1]; this.col[i * 4 + 2] = color[2]; this.col[i * 4 + 3] = alpha; this.size[i] = size;
  }
  end(camera, res) {
    this.geometry.setDrawRange(0, this.n);
    for (const k of ['position', 'aColor', 'aSize']) this.geometry.attributes[k].needsUpdate = true;
    this.material.uniforms.uFocal.value = res.y * 0.5 / Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2);
  }
}

export function textSprite(text, { size = 0.12, color = '#E8ECF8', font = '600 44px Pretendard', bg = null, pad = 18 } = {}) {
  const c = document.createElement('canvas'); const ctx = c.getContext('2d'); ctx.font = font;
  const w = Math.ceil(ctx.measureText(text).width) + pad * 2, h = 72;
  c.width = w; c.height = h; const g = c.getContext('2d'); g.font = font; g.textBaseline = 'middle';
  if (bg) { g.fillStyle = bg; g.beginPath(); g.roundRect(0, 6, w, h - 12, (h - 12) / 2); g.fill(); }
  g.fillStyle = color; g.shadowColor = 'rgba(0,0,0,0.6)'; g.shadowBlur = 8; g.fillText(text, pad, h / 2 + 1);
  const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 4;
  const m = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, depthTest: true });
  const s = new THREE.Sprite(m); s.scale.set(size * w / h, size, 1); s.userData.aspect = w / h; s.userData.size = size;
  return s;
}

const col = (h) => rgbOfHex(h); // custom shaders write display (sRGB) values directly
export const lin = col;

// ---------------------------------------------------------------------------------------------------------------
// The scene
// ---------------------------------------------------------------------------------------------------------------
export class Constellation {
  constructor(canvas, width, height) {
    this.W = width; this.H = height;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: (new URLSearchParams(location.search).get('aa') ?? '1') !== '0', preserveDrawingBuffer: false, alpha: false, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(1); this.renderer.setSize(width, height, false);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace; this.renderer.toneMapping = THREE.NoToneMapping;
    this.renderer.setClearColor(0x05070f, 1);
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(50, width / height, 0.05, 140);
    this.res = new THREE.Vector2(width, height);
    this.tmp = new THREE.Vector3();
  }

  async load(G, base = 'assets/') {
    const tl = new THREE.TextureLoader();
    const tex = (p, srgb = true) => new Promise((res) => tl.load(base + p, (t) => { if (srgb) t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; res(t); }));
    const [sky, skyTint, floor, glow, spark, ring, beam, ramp, cardGlow] = await Promise.all([
      tex('tex/Sky_Dark_2k.jpg'), tex('tex/Sky_Tint_2k.jpg'), tex('tex/Floor_Grid.png'), tex('tex/FX_Glow.png'), tex('tex/FX_Spark.png'), tex('tex/FX_Ring.png'),
      tex('tex/FX_Beam.png'), tex('tex/FX_EdgeRamp.png', false), tex('tex/FX_CardGlow.png')]);
    ramp.wrapS = ramp.wrapT = THREE.ClampToEdgeWrapping;
    sky.anisotropy = 1; skyTint.anisotropy = 1; floor.anisotropy = 2;
    this.tx = { sky, skyTint, floor, glow, spark, ring, beam, ramp, cardGlow };
    const loader = new GLTFLoader();
    const glb = (n) => new Promise((res, rej) => loader.load(base + 'glb/' + n + '.glb', (g) => res(g.scene), undefined, rej));
    const names = ['HostOrb', 'ClusterOrb', 'Beacon', 'Avatar_Bust', 'Stage_Ring', 'ReviewPin', 'Pointer_Dart', 'NodeStars'];
    const loaded = await Promise.all(names.map(glb));
    // trimesh GLBs carry no normals: flat-shade every asset (crisp facets, like the Blender renders)
    for (const root of loaded) root.traverse((o) => { if (o.isMesh) { let g = o.geometry; if (g.index) g = g.toNonIndexed(); g.computeVertexNormals(); o.geometry = g; } });
    this.glb = Object.fromEntries(names.map((n, i) => [n, loaded[i]]));
    this.matInfo = await (await fetch(base + 'glb/materials.json')).json();
    this.graph = buildGraph(G);
    this.build();
  }

  // USD material → three material (themeable slots overridden by callers)
  usdMaterial(asset, slot, over = {}) {
    const m = (this.matInfo[asset] || {})[slot] || {};
    const d = m.diffuseColor || [0.5, 0.5, 0.5], e = m.emissiveColor || [0, 0, 0];
    const op = m.opacity ?? 1;
    const mat = new THREE.MeshStandardMaterial({ color: new THREE.Color(d[0], d[1], d[2]), emissive: new THREE.Color(Math.min(1, e[0]), Math.min(1, e[1]), Math.min(1, e[2])),
      emissiveIntensity: Math.max(1, Math.max(e[0], e[1], e[2])), roughness: m.roughness ?? 0.5, metalness: m.metallic ?? 0, transparent: op < 1, opacity: op, depthWrite: op >= 1 });
    Object.assign(mat, over);
    return mat;
  }
  cloneAsset(name, mats) {
    const root = this.glb[name].clone(true);
    root.traverse((o) => { if (o.isMesh) { const slot = o.material.name; o.material = mats(slot, o) || this.usdMaterial(name, slot); o.userData.slot = slot; } });
    return root;
  }

  build() {
    const S = this.scene, G = this.graph;
    // lights for the PBR glyphs / assets
    S.add(new THREE.HemisphereLight(0xaab4e8, 0x0b0e1a, 0.8));
    const key = new THREE.DirectionalLight(0xffffff, 1.1); key.position.set(3, 8, 5); S.add(key);
    // sky (dark + tinted, crossfaded)
    const skyGeo = new THREE.SphereGeometry(40, 96, 48);
    this.skyMat = new THREE.MeshBasicMaterial({ map: this.tx.sky, side: THREE.BackSide, depthWrite: false, color: new THREE.Color(1.5, 1.5, 1.5) });
    this.sky = new THREE.Mesh(skyGeo, this.skyMat); this.sky.renderOrder = -10; S.add(this.sky);
    this.skyTintMat = new THREE.MeshBasicMaterial({ map: this.tx.skyTint, side: THREE.BackSide, depthWrite: false, transparent: true, opacity: 0 });
    this.skyT = new THREE.Mesh(skyGeo, this.skyTintMat); this.skyT.renderOrder = -9; S.add(this.skyT);
    // floor (astrolabe grid)
    this.floorMat = new THREE.MeshBasicMaterial({ map: this.tx.floor, color: new THREE.Color(DARK.floorGrid), transparent: true, opacity: 0.55, depthWrite: false });
    this.floor = new THREE.Mesh(new THREE.PlaneGeometry(24, 24), this.floorMat); this.floor.rotation.x = -Math.PI / 2; this.floor.position.y = -0.002; this.floor.renderOrder = -5; S.add(this.floor);
    this.floorBoost = 2.3;
    // stage ring
    this.stage = this.cloneAsset('Stage_Ring', (slot) => slot === 'Accent' ? this.usdMaterial('Stage_Ring', slot, {}) : null);
    S.add(this.stage);

    // cards + stars
    this.cardRoot = new THREE.Group(); S.add(this.cardRoot);
    const unitCard = new THREE.PlaneGeometry(1, ASPECT);
    const glowGeo = new THREE.PlaneGeometry(580 / 512, (424 / 512));
    this.cards = [];
    const starProto = {}; this.glb.NodeStars.traverse((o) => { if (o.isMesh) starProto[o.name] = o.geometry; });
    this.starGeo = starProto;
    const starMats = {};
    const starMat = (color, glow) => {
      const b = Math.round(clamp01(glow) * 4), k = color + b; if (starMats[k]) return starMats[k];
      const c = new THREE.Color(color);
      return (starMats[k] = new THREE.MeshStandardMaterial({ color: c.clone().multiplyScalar(0.55), emissive: c, emissiveIntensity: 0.22 + b * 0.12, roughness: 0.35, metalness: 0.15, transparent: true, opacity: 1 }));
    };
    for (const n of G.nodes) {
      const canvas = document.createElement('canvas');
      drawCard(canvas, cardContent(n, G, G.metrics(n.index)));
      const t = new THREE.CanvasTexture(canvas); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; t.generateMipmaps = true; t.minFilter = THREE.LinearMipmapLinearFilter;
      const mat = new THREE.MeshBasicMaterial({ map: t, transparent: true, opacity: 0.94, depthWrite: true, side: THREE.DoubleSide });
      const card = new THREE.Mesh(unitCard, mat); card.renderOrder = 2;
      const group = new THREE.Group(); group.add(card);
      const gmat = new THREE.MeshBasicMaterial({ map: this.tx.cardGlow, color: new THREE.Color(DARK.highlight), transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending });
      const glowQuad = new THREE.Mesh(glowGeo, gmat); glowQuad.position.z = -0.004; glowQuad.renderOrder = 1; group.add(glowQuad);
      const w = Math.max(0.12, n.cardWidth);
      const geo = starProto[n.glyph] || starProto.Star_Other;
      const smat = starMat(n.starColor, n.starGlow).clone();
      const star = new THREE.Mesh(geo, smat);
      const k = n.starSize / 0.1;
      // StarEncoder.anchor in card-local metres; the group is scaled by w, so divide by w
      star.position.set((-w / 2 + n.starSize * 0.55) / w, (w * ASPECT / 2 + n.starSize * 0.65) / w, 0.01 / w);
      star.scale.setScalar(k / w); star.renderOrder = 3;
      group.add(star);
      group.scale.setScalar(w);
      this.cardRoot.add(group);
      this.cards.push({ node: n, group, card, mat, glowQuad, gmat, star, smat, width: w, canvas, tex: t, pos: new THREE.Vector3(), scale: 1 });
    }
    // lines, particles, glows
    this.lines = new GlowLines(this.tx.ramp); this.lines.mesh.renderOrder = 4; S.add(this.lines.mesh);
    this.flat = new THREE.DataTexture(new Uint8Array([255, 255, 255, 255]), 1, 1); this.flat.needsUpdate = true;
    this.lines2 = new GlowLines(this.flat, { minPx: 0.9, glow: 1.6, glowAmt: 0.45 }); this.lines2.mesh.renderOrder = 4; S.add(this.lines2.mesh); // guides, rays, rings
    this.glows = new GlowPoints(this.tx.glow, 3000); this.glows.points.renderOrder = 5; S.add(this.glows.points);
    this.sparks = new GlowPoints(this.tx.spark, 600); this.sparks.points.renderOrder = 6; S.add(this.sparks.points);
    // arrowheads (instanced cones)
    const cone = new THREE.ConeGeometry(1, 1, 10, 1, false); cone.translate(0, -0.5, 0); // tip at origin, pointing +Y
    this.arrowMat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 1, depthWrite: false, blending: THREE.AdditiveBlending, vertexColors: false });
    this.arrows = new THREE.InstancedMesh(cone, this.arrowMat, 600); this.arrows.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(600 * 3), 3);
    this.arrows.renderOrder = 4; this.arrows.frustumCulled = false; S.add(this.arrows);

    // cluster orbs (folder granularity)
    this.orbRoot = new THREE.Group(); S.add(this.orbRoot);
    this.clusters = G.G.folderClusters.map((c) => {
      const anchor = G.nodes[c.anchor];
      const layerCounts = {}; for (const m of c.members) { const L = G.nodes[m].layer; if (G.nodes[m].kind === 'file') layerCounts[L] = (layerCounts[L] || 0) + 1; }
      const dominant = Object.entries(layerCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || 'unknown';
      const color = new THREE.Color(G.nodes.find(n => n.layer === dominant)?.layerColor || '#A7ADBF');
      const mats = {
        Core: new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: color.clone().lerp(new THREE.Color(1, 1, 1), 0.55), emissiveIntensity: 1.6 }),
        Shell: new THREE.MeshStandardMaterial({ color: color.clone().multiplyScalar(0.4), emissive: color, emissiveIntensity: 0.55, roughness: 0.4 }),
        Glass: new THREE.MeshStandardMaterial({ color: 0xb7beff, transparent: true, opacity: 0.12, roughness: 0.05, depthWrite: false }),
      };
      const obj = this.cloneAsset('ClusterOrb', (slot) => mats[slot]);
      const label = textSprite(anchor.name, { size: 0.085, color: '#' + color.getHexString(), font: '600 44px Pretendard' });
      label.position.y = 0.26; obj.add(label);
      this.orbRoot.add(obj);
      return { ...c, obj, mats, color, label, dominant, pos: new THREE.Vector3() };
    });

    // host orb
    this.host = this.makeHostOrb(); S.add(this.host.root);
    // beacons (pool of 3)
    this.beacons = [0, 1, 2].map(() => this.makeBeacon());
    // avatars (6 seats)
    this.avatars = [0, 1, 2, 3, 4, 5].map((i) => this.makeAvatar(i));
    // pointer dart
    this.dart = this.cloneAsset('Pointer_Dart', () => new THREE.MeshStandardMaterial({ color: 0x6fd8ff, emissive: 0x6fd8ff, emissiveIntensity: 1.4 }));
    this.dart.visible = false; S.add(this.dart);
    // review pins (pool)
    this.pinPool = [];
    for (let i = 0; i < 6; i++) {
      const p = this.cloneAsset('ReviewPin', (slot) => slot === 'Accent' ? new THREE.MeshStandardMaterial({ color: 0xffd166, emissive: 0xffc04d, emissiveIntensity: 1.2, roughness: 0.2 }) : new THREE.MeshStandardMaterial({ color: 0x2a2f45, roughness: 0.4, metalness: 0.6 }));
      p.visible = false; S.add(p); this.pinPool.push(p);
    }
    // summon card copy
    this.summonCard = new THREE.Mesh(unitCard, new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.97, depthWrite: true, side: THREE.DoubleSide }));
    this.summonCard.renderOrder = 7; this.summonCard.visible = false; S.add(this.summonCard);
    this.summonGlow = new THREE.Mesh(glowGeo, new THREE.MeshBasicMaterial({ map: this.tx.cardGlow, color: new THREE.Color(DARK.beacon), transparent: true, opacity: 0.9, depthWrite: false, blending: THREE.AdditiveBlending }));
    this.summonGlow.position.z = -0.01; this.summonCard.add(this.summonGlow);
    this.labels = new THREE.Group(); S.add(this.labels);
    this.setupBloom();
  }

  setupBloom() {
    const bw = Math.round(this.W / 4), bh = Math.round(this.H / 4);
    const opt = { minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, depthBuffer: true };
    this.bloomRT = new THREE.WebGLRenderTarget(bw, bh, opt);
    this.blurA = new THREE.WebGLRenderTarget(bw, bh, { ...opt, depthBuffer: false });
    this.blurB = new THREE.WebGLRenderTarget(bw, bh, { ...opt, depthBuffer: false });
    const vs = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }';
    const blur = (dir, thresh) => new THREE.ShaderMaterial({ vertexShader: vs, depthTest: false, depthWrite: false,
      uniforms: { tDiffuse: { value: null }, uDir: { value: new THREE.Vector2(dir[0] / bw, dir[1] / bh) }, uT: { value: thresh } },
      fragmentShader: `uniform sampler2D tDiffuse; uniform vec2 uDir; uniform float uT; varying vec2 vUv;
        vec3 tap(vec2 uv){ vec3 c = texture2D(tDiffuse, uv).rgb; if (uT > 0.0) { float l = max(c.r, max(c.g, c.b)); c *= smoothstep(uT, uT + 0.45, l); } return c; }
        void main(){ vec3 s = tap(vUv) * 0.227;
          s += (tap(vUv + uDir * 1.38) + tap(vUv - uDir * 1.38)) * 0.316;
          s += (tap(vUv + uDir * 3.23) + tap(vUv - uDir * 3.23)) * 0.070;
          gl_FragColor = vec4(s, 1.0); }` });
    this.matBlurH = blur([1.6, 0], 0.32); this.matBlurV = blur([0, 1.6], 0.0);
    this.matComp = new THREE.ShaderMaterial({ vertexShader: vs, transparent: true, depthTest: false, depthWrite: false,
      blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor,
      uniforms: { tDiffuse: { value: null }, uK: { value: 0.8 } },
      fragmentShader: 'uniform sampler2D tDiffuse; uniform float uK; varying vec2 vUv; void main(){ vec3 c = texture2D(tDiffuse, vUv).rgb; gl_FragColor = vec4(pow(c, vec3(0.80)) * uK, 1.0); }' });
    this.quadScene = new THREE.Scene(); this.quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.matBlurH); this.quad.frustumCulled = false; this.quadScene.add(this.quad);
  }

  /** Resize the drawing buffer (used when a director switches between a windowed viewport and full frame). */
  setViewport(w, h) {
    if (w === this.W && h === this.H) return;
    this.W = w; this.H = h; this.res.set(w, h);
    this.renderer.setSize(w, h, false);
    const bw = Math.round(w / 4), bh = Math.round(h / 4);
    for (const rt of [this.bloomRT, this.blurA, this.blurB]) rt.setSize(bw, bh);
    this.matBlurH.uniforms.uDir.value.set(1.6 / bw, 0); this.matBlurV.uniforms.uDir.value.set(0, 1.6 / bh);
  }

  drawFrame(cam, bloom) {
    const r = this.renderer;
    if (bloom > 0.001) {
      r.setRenderTarget(this.bloomRT); r.render(this.scene, cam);
      this.matBlurH.uniforms.tDiffuse.value = this.bloomRT.texture; this.quad.material = this.matBlurH; r.setRenderTarget(this.blurA); r.render(this.quadScene, this.quadCam);
      this.matBlurV.uniforms.tDiffuse.value = this.blurA.texture; this.quad.material = this.matBlurV; r.setRenderTarget(this.blurB); r.render(this.quadScene, this.quadCam);
    }
    r.setRenderTarget(null); r.render(this.scene, cam);
    if (bloom > 0.001) {
      this.matComp.uniforms.tDiffuse.value = this.blurB.texture; this.matComp.uniforms.uK.value = bloom; this.quad.material = this.matComp;
      const ac = r.autoClear; r.autoClear = false; r.render(this.quadScene, this.quadCam); r.autoClear = ac;
    }
  }

  makeHostOrb() {
    const bands = DARK.orbBands.map((c) => new THREE.MeshStandardMaterial({ color: new THREE.Color(c).multiplyScalar(0.5), emissive: new THREE.Color(c), emissiveIntensity: 1.2, roughness: 0.3 }));
    const mats = {
      Core: new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xf4f2ff, emissiveIntensity: 2.2 }),
      Glass: new THREE.MeshStandardMaterial({ color: 0xc9cdff, transparent: true, opacity: 0.16, roughness: 0.04, depthWrite: false }),
      Band0: bands[0], Band1: bands[1], Band2: bands[2], Band3: bands[3],
    };
    const root = new THREE.Group();
    const obj = this.cloneAsset('HostOrb', (slot) => mats[slot]);
    root.add(obj);
    const parts = {}; obj.traverse((o) => { if (o.isMesh) parts[o.name] = o; });
    root.visible = false;
    return { root, obj, parts, mats, bands };
  }

  makeBeacon() {
    const beaconC = new THREE.Color(DARK.beacon);
    const mats = {
      Accent: new THREE.MeshStandardMaterial({ color: beaconC.clone().multiplyScalar(0.6), emissive: beaconC, emissiveIntensity: 1.5, roughness: 0.3 }),
      Core: new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xfff1cc, emissiveIntensity: 2.0 }),
      Glass: new THREE.MeshStandardMaterial({ color: 0xffd98a, transparent: true, opacity: 0.12, depthWrite: false }),
      Base: new THREE.MeshStandardMaterial({ color: 0x1b1f2e, roughness: 0.35, metalness: 0.6 }),
    };
    const root = new THREE.Group();
    const obj = this.cloneAsset('Beacon', (slot) => mats[slot]);
    root.add(obj);
    const beamMat = new THREE.MeshBasicMaterial({ map: this.tx.beam, color: beaconC.clone().lerp(new THREE.Color(1, 1, 1), 0.2), transparent: true, opacity: 0.9, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide });
    for (let k = 0; k < 2; k++) { const q = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 3), beamMat); q.position.y = 1.5; q.rotation.y = k * Math.PI / 2; q.renderOrder = 5; root.add(q); }
    const ringMat = [0, 1].map(() => new THREE.MeshBasicMaterial({ map: this.tx.ring, color: beaconC, transparent: true, opacity: 0.8, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
    const rings = ringMat.map((m) => { const r = new THREE.Mesh(new THREE.PlaneGeometry(0.75, 0.75), m); r.rotation.x = -Math.PI / 2; r.position.y = 0.01; r.renderOrder = 5; root.add(r); return r; });
    root.visible = false; this.scene.add(root);
    return { root, obj, beamMat, rings, ringMat, mats };
  }

  makeAvatar(i) {
    const accent = new THREE.MeshStandardMaterial({ color: 0x6fb6ff, emissive: 0x6fb6ff, emissiveIntensity: 1.1, roughness: 0.3 });
    const base = new THREE.MeshStandardMaterial({ color: 0x151927, roughness: 0.25, metalness: 0.5 });
    const root = new THREE.Group();
    const obj = this.cloneAsset('Avatar_Bust', (slot) => slot === 'Accent' ? accent : base);
    root.add(obj);
    const angle = i / 6 * Math.PI * 2;
    root.position.set(Math.sin(angle) * 1.2, 0, Math.cos(angle) * 1.2);
    root.rotation.y = angle + Math.PI; // face the centre
    root.visible = false; this.scene.add(root);
    return { root, obj, accent, label: null, angle };
  }

  // ----------------------------------------------------------------------------------------------------------
  position(i, L, dial, out) {
    const a = this.graph.G.positions[L.a][i], b = this.graph.G.positions[L.b][i];
    const m = L.m || 0;
    const base = this.tmp.set(a[0] + (b[0] - a[0]) * m, a[1] + (b[1] - a[1]) * m, a[2] + (b[2] - a[2]) * m);
    const ca = this.graph.G.centers[L.a], cb = this.graph.G.centers[L.b];
    const center = new THREE.Vector3(ca[0] + (cb[0] - ca[0]) * m, ca[1] + (cb[1] - ca[1]) * m, ca[2] + (cb[2] - ca[2]) * m);
    const w = this.graph.nodes[i].recency;
    if (!dial) return out.copy(base);
    const sa = L.a === 'celestial' || L.a === 'sphere', sb = L.b === 'celestial' || L.b === 'sphere';
    const pa = projectPoint(base, center, w, dial, sa, new THREE.Vector3());
    if (sa === sb) return out.copy(pa);
    const pb = projectPoint(base, center, w, dial, sb, new THREE.Vector3());
    return out.copy(pa).lerp(pb, m);
  }
  centerOf(L) { const ca = this.graph.G.centers[L.a], cb = this.graph.G.centers[L.b], m = L.m || 0; return new THREE.Vector3(ca[0] + (cb[0] - ca[0]) * m, ca[1] + (cb[1] - ca[1]) * m, ca[2] + (cb[2] - ca[2]) * m); }

  /** Render one frame from a state object (see timelines). */
  render(st) {
    const G = this.graph, t = st.t || 0;
    const cam = this.camera;
    cam.fov = st.camera.fov || 50; cam.aspect = this.W / this.H; cam.updateProjectionMatrix();
    cam.position.copy(st.camera.pos); cam.lookAt(st.camera.target);
    if (st.camera.roll) cam.rotateZ(st.camera.roll);
    cam.updateMatrixWorld();
    const L = st.layout || { a: 'celestial', b: 'celestial', m: 0 };
    const dial = st.dial || 0;

    // theme
    const th = st.theme || { m: 0 };
    const tm = th.m || 0;
    this.skyMat.color.setScalar(st.skyExposure ?? 1.0);
    this.skyTintMat.opacity = tm; this.skyT.visible = tm > 0.001;
    if (th.b) { this.skyTintMat.color.set(th.b.skyTint); }
    const gridC = new THREE.Color(DARK.floorGrid); if (th.b) gridC.lerp(new THREE.Color(th.b.floorGrid), tm);
    // tinted → tinted (both presets carry a sky tint): crossfade the tint itself
    if (th.a && th.a.skyTint && th.b && th.b.skyTint) {
      this.skyTintMat.opacity = 1; this.skyT.visible = true;
      this.skyTintMat.color.set(th.a.skyTint).lerp(new THREE.Color(th.b.skyTint), tm);
      gridC.set(th.a.floorGrid).lerp(new THREE.Color(th.b.floorGrid), tm);
    }
    this.sky.rotation.y = st.skyRotation ?? 0; this.skyT.rotation.y = this.sky.rotation.y;
    this.floorMat.color.copy(gridC).multiplyScalar(this.floorBoost); this.floorMat.opacity = 0.55 * (st.floorOpacity ?? 1);
    this.stage.visible = st.stage !== false;

    // node positions
    const vis = st.nodeVis; // Float32Array or null
    const pos = this.positions = this.positions || G.nodes.map(() => new THREE.Vector3());
    for (let i = 0; i < G.nodes.length; i++) this.position(i, L, dial, pos[i]);

    // relations
    const mode = st.relMode || 'all';
    const focusSel = st.focus ?? null;
    const focus = new Set(); if (focusSel !== null && focusSel !== undefined) for (const k of G.subtree(focusSel)) focus.add(k);
    const hidden = st.hidden || new Set();
    const related = new Set(focus);
    const center = this.centerOf(L);
    const lines = this.lines; lines.begin();
    const flows = [];
    let arrowCount = 0; const arrows = this.arrows; const m4 = new THREE.Matrix4(); const q = new THREE.Quaternion(); const up = new THREE.Vector3(0, 1, 0);
    const relOpacity = st.relOpacity ?? 1, treeOpacity = st.treeOpacity ?? 1;
    const only = st.onlyKinds || null; // Set of kinds to keep loud (legend demo); others faint
    const draw = st.edgeDraw || null;
    const cyc = st.cycleEdges || null;
    const loudNodes = new Set();
    for (const e of G.edges) {
      const a = pos[e.from], b = pos[e.to];
      if (a.distanceTo(b) <= 0.02) continue;
      let frac = draw ? draw(e) : 1;
      if (vis) frac = Math.min(frac, Math.min(vis[e.from], vis[e.to]) >= 0.999 ? 1 : 0) ;
      if (frac <= 0) continue;
      const ea = st.edgeAlpha ? st.edgeAlpha(e) : 1;
      if (e.rel === 'contains') {
        if (treeOpacity <= 0) continue;
        const emph = focus.size ? 'faint' : 'normal';
        const tc = st.treeColor ? st.treeColor(e) : null;
        if (frac < 1) lines.pushPolyline([a, b], tc || col(DARK.edgeContains), batchOpacity(null, emph) * treeOpacity * 1.2 * ea, emph === 'faint' ? 0.0011 : 0.0016, frac);
        else lines.push(a, b, 0.35, 0.8, tc || col(DARK.edgeContains), batchOpacity(null, emph) * treeOpacity * 1.2 * ea, emph === 'faint' ? 0.0011 : 0.0016);
        continue;
      }
      if (hidden.has(e.rel) || mode === 'off' || relOpacity <= 0) continue;
      const touches = focus.has(e.from) || focus.has(e.to);
      const isCyc = cyc ? cyc.has(e.index) : false;
      if (mode === 'focus' && !touches && !isCyc) continue;
      let emph = touches || isCyc ? 'focus' : (focus.size ? 'faint' : 'normal');
      if (only && !only.has(e.rel)) emph = 'faint';
      if (only && only.has(e.rel)) emph = 'focus';
      const style = REL[e.rel];
      let pts = arcPoints(a, b, center, e.rel, !!st.inward);
      if (e.rel === 'binds') pts = pts.reverse();
      const color = isCyc ? col(CYCLE_COLOR) : col(style.color);
      const loud = only && only.has(e.rel);
      const alpha = batchOpacity(e.rel, emph, isCyc) * relOpacity * (loud ? 1.6 : only ? 0.6 : 1) * ea;
      const radius = tubeRadius(e.rel, emph, isCyc) * (loud ? 1.5 : 1);
      const cum = cumulative(pts);
      if (style.dashed) {
        const total = cum[cum.length - 1]; let s0 = 0;
        while (s0 < total * frac) {
          const s1 = Math.min(total * frac, s0 + 0.06);
          if (s1 - s0 > 0.004) {
            let prev = pointAt(pts, cum, s0), ps = s0;
            for (let i = 0; i < pts.length; i++) if (cum[i] > s0 && cum[i] < s1) { lines.push(prev, pts[i], ps / total, cum[i] / total, color, alpha, radius); prev = pts[i]; ps = cum[i]; }
            lines.push(prev, pointAt(pts, cum, s1), ps / total, s1 / total, color, alpha, radius);
          }
          s0 = s1 + 0.045;
        }
      } else {
        lines.pushPolyline(pts, color, alpha, radius, frac, cum);
      }
      if ((style.flow || emph === 'focus') && frac >= 1 && arrowCount < 600 && emph !== 'faint') {
        const total = cum[cum.length - 1]; const length = Math.max(0.028, radius * 7);
        if (total > length * 2) {
          const tipF = Math.max(0.5, 1 - (0.06 + length * 0.2) / total);
          const tip = pointAt(pts, cum, tipF * total), back = pointAt(pts, cum, (tipF - length / total) * total);
          const dir = tip.clone().sub(back).normalize(); q.setFromUnitVectors(up, dir);
          const rad = Math.max(0.0095, radius * 3.3);
          m4.compose(tip, q, new THREE.Vector3(rad, length, rad)); arrows.setMatrixAt(arrowCount, m4);
          arrows.instanceColor.setXYZ(arrowCount, color[0] * alpha, color[1] * alpha, color[2] * alpha); arrowCount++;
        }
      }
      if (emph === 'focus') { related.add(e.from); related.add(e.to); }
      if (loud) { loudNodes.add(e.from); loudNodes.add(e.to); }
      if (style.flow && emph !== 'faint' && frac >= 1) flows.push({ rel: e.rel, emph, pts, cum, index: flows.length, alpha: relOpacity });
    }
    arrows.count = arrowCount; arrows.instanceMatrix.needsUpdate = true; arrows.instanceColor.needsUpdate = true;
    // extra guide lines from the timeline (summon guide, pointer ray, axis helpers)
    const l2 = this.lines2; l2.begin();
    for (const g of (st.guides || [])) {
      if (g.dashed) {
        const pts = g.points, cum = cumulative(pts), total = cum[cum.length - 1]; let s0 = 0;
        while (s0 < total * (g.frac ?? 1)) { const s1 = Math.min(total * (g.frac ?? 1), s0 + (g.dash || 0.07)); l2.push(pointAt(pts, cum, s0), pointAt(pts, cum, s1), 0, 1, col(g.color), g.alpha ?? 1, g.width || 0.003); s0 = s1 + (g.gap || 0.05); }
      } else l2.pushPolyline(g.points, col(g.color), g.alpha ?? 1, g.width || 0.003, g.frac ?? 1);
    }

    // particles along flow arcs (FlowParticles)
    const glows = this.glows, sparks = this.sparks; glows.begin(); sparks.begin();
    if (st.particles !== false) {
      let used = 0;
      flows.sort((x, y) => (x.emph === y.emph ? REL[y.rel].priority - REL[x.rel].priority : (x.emph === 'focus' ? -1 : 1)));
      for (const f of flows) {
        const n = 2; if (used + n > 240) break; used += n;
        const total = f.cum[f.cum.length - 1]; const speed = f.emph === 'focus' ? 0.55 : 0.42;
        const c = rgbOfHex(REL[f.rel].color).map(v => Math.min(1, v + (f.emph === 'focus' ? 0.25 : 0.1) * (1 - v)));
        const cl = c.map(v => Math.pow(v, 2.2));
        const off = ((f.index * 37) % 100) / 100;
        for (let k = 0; k < n; k++) {
          let ph = (k / n + off + t * speed / Math.max(total, 0.05)) % 1;
          const fade = Math.min(1, ph / 0.12, (1 - ph) / 0.12);
          const p = pointAt(f.pts, f.cum, ph * total);
          if (f.emph === 'focus') sparks.push(p, cl, 1.0 * f.alpha, 0.075 * Math.max(0.05, fade) * 1.6);
          else glows.push(p, cl, 0.85 * f.alpha, 0.045 * Math.max(0.05, fade) * 1.5);
        }
      }
    }

    // cards
    const camPos = cam.position;
    const dimOn = focus.size > 0 && mode !== 'off' && st.dim !== false;
    const hl = st.highlight || new Set();
    const cardOp = st.cardOpacity ?? 1;
    for (const c of this.cards) {
      const i = c.node.index;
      const v = vis ? vis[i] : 1;
      const p = pos[i];
      c.group.position.copy(p);
      c.group.rotation.set(0, Math.atan2(camPos.x - p.x, camPos.z - p.z), 0);
      const pop = v < 1 ? easeOut(v) * (1 + 0.25 * Math.sin(Math.PI * clamp01(v))) : 1;
      c.group.scale.setScalar(c.width * Math.max(0.0001, pop));
      c.group.visible = v > 0.001;
      const dim = (dimOn && !related.has(i) && !hl.has(i)) || (only && !loudNodes.has(i));
      const op = (dim ? 0.22 : 1) * cardOp * clamp01(v * 1.4);
      c.mat.opacity = 0.94 * op; c.smat.opacity = op; c.smat.transparent = op < 0.999;
      c.star.visible = (st.stars ?? 1) > 0.01;
      c.star.scale.setScalar((c.node.starSize / 0.1) / c.width * (st.starScale ?? 1));
      // glow for selection / highlight
      const sel = st.selected === i, isH = hl.has(i);
      const ng = st.nodeGlow ? st.nodeGlow[i] : 0;
      c.gmat.opacity = Math.max(sel ? 1 : isH ? 0.8 : 0, ng) * clamp01(v * 1.4);
      c.gmat.color.set(sel ? (st.selectColor || '#FFFFFF') : (ng > 0 && !isH ? (st.nodeGlowColor ? st.nodeGlowColor(i) : DARK.highlight) : DARK.highlight));
      // star halo glow
      if (c.group.visible && (st.stars ?? 1) > 0.01) {
        const sp = new THREE.Vector3((-c.width / 2 + c.node.starSize * 0.55), (c.width * ASPECT / 2 + c.node.starSize * 0.65), 0.012).applyEuler(c.group.rotation).multiplyScalar(pop).add(p);
        glows.push(sp, col(c.node.starColor), (0.18 + 0.32 * c.node.starGlow) * op * (st.stars ?? 1) * (st.starGlowBoost ?? 1), c.node.starSize * 3.2 * (st.starScale ?? 1));
      }
    }

    // cluster orbs
    const orbVis = st.orbs ?? 0;
    for (const [ci, c] of this.clusters.entries()) {
      c.obj.visible = orbVis > 0.01;
      if (!c.obj.visible) continue;
      const ctr = new THREE.Vector3(); let n = 0;
      for (const m of c.members) { ctr.add(pos[m]); n++; }
      ctr.divideScalar(Math.max(1, n));
      c.pos.copy(ctr);
      c.obj.position.copy(ctr);
      const docked = st.docked === ci;
      const s = 0.9 * orbVis * (docked ? 1 + 0.08 * Math.sin(t * 5) : 1);
      c.obj.scale.setScalar(Math.max(0.001, s));
      c.obj.rotation.y = t * 0.25 + ci; c.obj.rotation.x = 0.2 * Math.sin(t * 0.3 + ci);
      const tint = docked ? new THREE.Color(DARK.orbHalo) : c.color;
      c.mats.Shell.emissive.copy(tint); c.mats.Core.emissive.copy(tint.clone().lerp(new THREE.Color(1, 1, 1), 0.55));
      c.label.visible = st.orbLabels !== false; c.label.material.opacity = orbVis;
      glows.push(ctr, col('#' + tint.getHexString()), (docked ? 0.9 : 0.35) * orbVis, docked ? 0.9 : 0.55);
    }

    // host orb
    const H = st.host;
    this.host.root.visible = !!(H && H.visible > 0.01);
    if (this.host.root.visible) {
      const r = this.host.root; r.position.copy(H.pos); r.scale.setScalar(Math.max(0.001, (H.scale ?? 1) * H.visible));
      const energy = H.energy ?? 0.22;
      const P = this.host.parts;
      if (P.HostOrb_Equator) P.HostOrb_Equator.rotation.y = t * (0.9 + energy * 2);
      if (P.HostOrb_MeridianA) P.HostOrb_MeridianA.rotation.y = -t * (0.7 + energy * 2);
      if (P.HostOrb_MeridianB) P.HostOrb_MeridianB.rotation.x = t * (0.5 + energy * 1.5);
      if (P.HostOrb_Ecliptic) P.HostOrb_Ecliptic.rotation.z = t * (0.4 + energy);
      this.host.obj.rotation.y = t * 0.3;
      const pulse = 1 + Math.sin(t * (2 + energy * 6)) * 0.08 * energy;
      const hs = (H.scale ?? 1) * H.visible;
      const hg = H.glow ?? 1;
      glows.push(H.pos, col(DARK.orbHalo), 0.75 * H.visible * hg, 0.62 * hs * pulse * (0.5 + 0.5 * hg));
      glows.push(H.pos, [1, 1, 1], 0.9 * H.visible * hg, 0.2 * hs * pulse);
      // aura particles
      for (let k = 0; k < 26; k++) {
        const ph = ((t * (0.35 + energy * 0.5)) + k * 0.6180339) % 1;
        const th1 = k * 2.399963, ph1 = Math.acos(1 - 2 * ((k * 0.37 + 0.13) % 1));
        const rr = (0.1 + ph * 0.22) * hs;
        const p = new THREE.Vector3(Math.sin(ph1) * Math.cos(th1 + t * 0.2), Math.cos(ph1), Math.sin(ph1) * Math.sin(th1 + t * 0.2)).multiplyScalar(rr).add(H.pos);
        glows.push(p, col('#C9C2FF'), 0.5 * (1 - ph) * H.visible * hg, 0.03 * hs);
      }
    }

    // beacons
    const B = st.beacons || [];
    this.beacons.forEach((b, k) => {
      const spec = B[k]; b.root.visible = !!spec;
      if (!spec) return;
      const p = pos[spec.node];
      b.root.position.set(p.x, 0, p.z);
      const age = spec.age; const rise = easeOut(age / 0.8);
      b.root.scale.set(1, Math.max(0.001, rise), 1);
      b.beamMat.opacity = 0.85 * rise * (spec.alpha ?? 1);
      b.rings.forEach((r, j) => { const ph = ((age * 0.55) + j * 0.5) % 1; r.scale.setScalar(0.6 + ph * 2.6); b.ringMat[j].opacity = (1 - ph) * 0.9 * rise * (spec.alpha ?? 1); });
      b.obj.rotation.y = age * 0.6;
      glows.push(new THREE.Vector3(p.x, 3.0 * rise, p.z), col(DARK.beacon), 0.9 * rise, 0.35);
      glows.push(new THREE.Vector3(p.x, 0.05, p.z), col(DARK.beacon), 0.6 * rise, 0.9);
    });

    // summon
    const SM = st.summon;
    this.summonCard.visible = !!SM;
    if (SM) {
      const c = this.cards[SM.node];
      this.summonCard.material.map = c.tex; this.summonCard.material.needsUpdate = this.summonCard.material.userData.last !== SM.node; this.summonCard.material.userData.last = SM.node;
      const from = pos[SM.node], k = easeOut(SM.k);
      const target = SM.target;
      this.summonCard.position.copy(from).lerp(target, k);
      const yaw = Math.atan2(camPos.x - this.summonCard.position.x, camPos.z - this.summonCard.position.z);
      this.summonCard.rotation.set(0, yaw, 0);
      this.summonCard.scale.setScalar(c.width + (SM.width - c.width) * k);
      this.summonGlow.material.opacity = 0.7 * k;
      (st.guides = st.guides || []);
      l2.push(from, this.summonCard.position, 0, 1, col(DARK.beacon), 0.0, 0.001);
      // dashed guide from origin to copy
      const g = [from.clone(), this.summonCard.position.clone()]; const cum = cumulative(g), total = cum[1]; let s0 = 0;
      while (s0 < total) { const s1 = Math.min(total, s0 + 0.07); l2.push(pointAt(g, cum, s0), pointAt(g, cum, s1), 0, 1, col(DARK.beacon), 0.8 * k, 0.003); s0 = s1 + 0.05; }
    }

    // avatars
    const A = st.avatars || [];
    this.avatars.forEach((a, k) => {
      const spec = A[k]; a.root.visible = !!spec && (spec.visible ?? 1) > 0.01;
      if (!a.root.visible) return;
      a.accent.color.set(spec.color); a.accent.emissive.set(spec.color);
      const v = spec.visible ?? 1; a.root.scale.setScalar(Math.max(0.001, easeOut(v)));
      if (spec.pos) a.root.position.copy(spec.pos); else a.root.position.set(Math.sin(a.angle) * 1.2, 0, Math.cos(a.angle) * 1.2);
      a.root.position.y += 0.012 * Math.sin(t * 1.3 + k);
      if (spec.rotY !== undefined) a.root.rotation.y = spec.rotY; else a.root.rotation.y = a.angle + Math.PI;
      if (spec.name && (!a.label || a.label.userData.text !== spec.name)) {
        if (a.label) a.root.remove(a.label);
        a.label = textSprite(spec.name, { size: 0.07, color: spec.color, font: '600 40px Pretendard' }); a.label.userData.text = spec.name; a.label.position.y = 0.56; a.root.add(a.label);
      }
      if (spec.lookAt) { const d = new THREE.Vector3().subVectors(spec.lookAt, a.root.position); a.root.rotation.y = Math.atan2(d.x, d.z); }
    });

    // pointer
    const PT = st.pointer;
    this.dart.visible = !!PT;
    if (PT) {
      this.dart.position.copy(PT.hit);
      const d = new THREE.Vector3().subVectors(PT.hit, PT.origin).normalize();
      this.dart.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, -1), d);
      this.dart.scale.setScalar(1.6);
      l2.push(PT.origin, PT.hit, 0, 1, col(PT.color || '#6FD8FF'), 0.85, 0.0022);
      glows.push(PT.hit, col(PT.color || '#6FD8FF'), 0.9, 0.12);
    }
    // review pins
    let pinUsed = 0;
    for (const [nodeStr, count] of Object.entries(st.pins || {})) {
      const c = this.cards[+nodeStr]; if (!c) continue;
      for (let k = 0; k < count && pinUsed < this.pinPool.length; k++) {
        const p = this.pinPool[pinUsed++]; p.visible = true;
        const local = new THREE.Vector3(-c.width / 2 + c.node.starSize * 1.2 + 0.03 + k * 0.045, c.width * ASPECT / 2, 0.01).applyEuler(c.group.rotation);
        p.position.copy(pos[c.node.index]).add(local); p.scale.setScalar(1.4);
        glows.push(p.position.clone().add(new THREE.Vector3(0, 0.07, 0)), col('#FFD166'), 0.6, 0.08);
      }
    }
    for (let k = pinUsed; k < this.pinPool.length; k++) this.pinPool[k].visible = false;

    // extra glow points from timeline
    for (const g of (st.extraGlows || [])) glows.push(g.p, col(g.color), g.alpha, g.size);

    lines.material.uniforms.uOpacity.value = st.lineBoost ?? 1;
    lines.end(cam, this.res); l2.end(cam, this.res); glows.end(cam, this.res); sparks.end(cam, this.res);
    // 3-D labels from the timeline
    this.syncLabels(st.labels || []);
    this.drawFrame(cam, st.bloom ?? 0);
    this.related = related;
  }

  syncLabels(specs) {
    this.labelCache = this.labelCache || {};
    for (const s of Object.values(this.labelCache)) s.visible = false;
    for (const l of specs) {
      const key = l.text + '|' + (l.color || '') + '|' + (l.size || '');
      let s = this.labelCache[key];
      if (!s) { s = textSprite(l.text, { size: l.size || 0.12, color: l.color || '#E8ECF8', font: l.font || '600 44px Pretendard', bg: l.bg || null }); this.labels.add(s); this.labelCache[key] = s; }
      s.visible = true; s.position.copy(l.p); s.material.opacity = l.alpha ?? 1;
    }
  }

  /** Screen position (px) of a world point, for DOM callouts. */
  toScreen(p) { const v = p.clone().project(this.camera); return { x: (v.x + 1) / 2 * this.W, y: (1 - v.y) / 2 * this.H, behind: v.z > 1 }; }
}
