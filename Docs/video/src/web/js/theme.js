// Port of ConstellateKit/Theme/ConstellateTheme.swift (colours only) + RelationKind / CodeRole styles.

export function hex(c) { return '#' + c.map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, '0')).join(''); }
export function rgbOfHex(h) { const n = parseInt(h.slice(1), 16); return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255]; }

export function hsl(hue, s, l) {
  const h = (((hue % 360) + 360) % 360) / 360;
  if (s === 0) return [l, l, l];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const ch = (t) => { if (t < 0) t += 1; if (t > 1) t -= 1; if (t < 1 / 6) return p + (q - p) * 6 * t; if (t < 1 / 2) return q; if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6; return p; };
  return [ch(h + 1 / 3), ch(h), ch(h - 1 / 3)];
}

function hueOf([r, g, b]) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
  if (mx === mn) return 0;
  const d = mx - mn; let h;
  if (mx === r) h = (g - b) / d + (g < b ? 6 : 0); else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4;
  return h * 60;
}

const CODE = { plain: '#F4F6FB', keyword: '#FF7AB6', type: '#5EE1FF', function: '#FFD166', string: '#B8FF7A', number: '#B89CFF', comment: '#8A93A6' };
export const CODE_PALETTE = CODE;
const RESERVED = ['keyword', 'type', 'function', 'string', 'number'].map(k => hueOf(rgbOfHex(CODE[k])));

function hueDistance(a, b) { const d = Math.abs(a - b) % 360; return Math.min(d, 360 - d); }
function signedDelta(a, b) { let d = (b - a) % 360; if (d > 180) d -= 360; if (d < -180) d += 360; return d; }
function safeHue(hue, minDistance = 22) {
  let h = ((hue % 360) + 360) % 360;
  for (let i = 0; i < 12; i++) {
    const clash = RESERVED.find(r => hueDistance(r, h) < minDistance);
    if (clash === undefined) return h;
    const delta = signedDelta(clash, h);
    h = ((clash + (delta >= 0 ? minDistance : -minDistance)) + 360) % 360;
  }
  return h;
}

export const DARK = {
  name: 'Dark', hue: null,
  skyTop: '#05070F', skyHorizon: '#121733', skyBottom: '#0A0B14', floor: '#0B0E1A', floorGrid: '#2A3150', floorGridA: 0.55,
  orbHalo: '#9B8CFF', orbBands: ['#7F7CFF', '#58D7E8', '#FF8FD1', '#FFFFFF'], avatarAccent: '#6FB6FF', beacon: '#FFD166', highlight: '#5EE1FF',
  edgeContains: '#6B7390',
};

export function tinted(rawHue, name) {
  const hue = safeHue(rawHue);
  return {
    ...DARK, name: name || `Tint ${Math.round(hue)}°`, hue,
    skyTop: hex(hsl(hue, 0.30, 0.06)), skyHorizon: hex(hsl(hue, 0.34, 0.17)), skyBottom: hex(hsl(hue, 0.28, 0.07)),
    floor: hex(hsl(hue, 0.22, 0.08)), floorGrid: hex(hsl(hue, 0.26, 0.28)), floorGridA: 0.55,
    orbHalo: hex(hsl(hue, 0.75, 0.72)),
    orbBands: [hex(hsl(hue, 0.8, 0.7)), hex(hsl(hue + 40, 0.7, 0.7)), hex(hsl(hue - 40, 0.7, 0.72)), '#FFFFFF'],
    avatarAccent: hex(hsl(hue + 180, 0.6, 0.68)),
    skyTint: hex(hsl(hue, 0.45, 0.42)),
  };
}

export const PRESETS = [DARK, tinted(210, 'Ocean'), tinted(150, 'Moss'), tinted(20, 'Ember'), tinted(275, 'Nebula')];

export const LAYER_COLOR = { presentation: '#5EE1FF', domain: '#C9B6FF', data: '#FFD166', infrastructure: '#8A93A6', test: '#B8FF7A', unknown: '#A7ADBF' };

// RelationKind.style
export const REL = {
  conforms:  { ko: '채택·상속', en: 'Conforms', hint: '타입 → 프로토콜/부모 클래스', color: '#BB9AF7', flow: false, dashed: true,  lane: -0.62, altitude: 0.85, priority: 70 },
  extends:   { ko: '확장', en: 'Extends', hint: 'extension → 원본 타입', color: '#7DCFFF', flow: false, dashed: true,  lane: 0.18, altitude: 0.7, priority: 60 },
  composes:  { ko: '뷰 포함', en: 'Composes', hint: '부모 뷰 → 자식 뷰', color: '#7AA2F7', flow: false, dashed: false, lane: 0.44, altitude: 1.0, priority: 80 },
  presents:  { ko: '화면 전환', en: 'Presents', hint: 'sheet / NavigationLink / present → 목적지', color: '#FF9E64', flow: true, dashed: false, lane: 1.22, altitude: 1.45, priority: 95 },
  binds:     { ko: '상태 흐름', en: 'Binds', hint: '데이터 원본 → 관찰하는 뷰', color: '#9ECE6A', flow: true, dashed: false, lane: 0.87, altitude: 1.15, priority: 90 },
  creates:   { ko: '생성', en: 'Creates', hint: '생성하는 곳 → 생성되는 타입', color: '#E0AF68', flow: true, dashed: false, lane: -0.96, altitude: 1.25, priority: 85 },
  delegates: { ko: '델리게이트', en: 'Delegates', hint: '구현 → 프로토콜', color: '#F7768E', flow: true, dashed: true,  lane: -0.35, altitude: 1.05, priority: 75 },
  notifies:  { ko: '알림', en: 'Notifies', hint: 'post → observe', color: '#FFD60A', flow: true, dashed: false, lane: -1.31, altitude: 1.6, priority: 88 },
  uses:      { ko: '타입 참조', en: 'Uses', hint: '사용 → 정의', color: '#8B93A5', flow: false, dashed: false, lane: 0, altitude: 0.55, priority: 10 },
  imports:   { ko: 'import', en: 'Imports', hint: '파일 → 모듈/최상위 폴더', color: '#58D7E8', flow: false, dashed: false, lane: 0, altitude: 0.38, priority: 20 },
  calls:     { ko: '호출', en: 'Calls', hint: '함수 → 함수', color: '#FFD166', flow: true, dashed: false, lane: -1.1, altitude: 1.3, priority: 65 },
};
export const LEGEND_ORDER = Object.keys(REL).sort((a, b) => REL[b].priority - REL[a].priority);

export const ROLE = {
  app: { label: 'App', color: '#F7768E' }, view: { label: 'View', color: '#7AA2F7' }, controller: { label: 'Controller', color: '#7DCFFF' },
  viewModel: { label: 'ViewModel', color: '#BB9AF7' }, model: { label: 'Model', color: '#9ECE6A' }, service: { label: 'Service', color: '#E0AF68' },
  extension: { label: 'Extension', color: '#8B93A5' }, test: { label: 'Test', color: '#FF9E64' }, doc: { label: 'Doc', color: '#8B93A5' },
  config: { label: 'Config', color: '#8B93A5' }, script: { label: 'Script', color: '#89E051' }, other: { label: '', color: '#8B93A5' },
};

export const LAYOUT = {
  celestial: { label: '천구 · Celestial', axes: '거리 = 트리 깊이 · 방위 = 서브트리 · 고도 = 레이어 · 바깥 = 최근', proj: 'spherical' },
  shells: { label: '셸 · Shells', axes: '반지름 = 트리 깊이 · 각도 = 서브트리 · 높이 = 레이어', proj: 'cylindrical' },
  sphere: { label: '구 · Sphere', axes: '구면 순서 = 경로 · 폴더 = 바깥 허브', proj: 'spherical' },
  treeRadial: { label: '트리 방사형 · Tree radial', axes: '링 = 깊이 · 각도 = 파일 수 비례 · 높이 = 레이어', proj: 'cylindrical' },
  wall: { label: '벽 · Wall', axes: '열·행 = 경로 순서 · 폴더 = 위 라벨', proj: 'cylindrical' },
  spiral: { label: '나선 · Spiral', axes: '높이·회전 = 경로 순서', proj: 'cylindrical' },
};
export const RELATION_MODE = { off: '관계 끔 · Off', focus: '선택 · Focus', all: '전체 · All' };
export const CYCLE_COLOR = '#FF5F6D';
