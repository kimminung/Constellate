// Port of Constellate/Spatial/TextureFactory.cardImage + Support/SyntaxHighlighter.tokenize (Canvas2D).
import { CODE_PALETTE as P, ROLE } from './theme.js';

export const CARD_W = 512, CARD_H = 352;
const MONO = '"DejaVu Sans Mono", Menlo, monospace';

const KEYWORDS = new Set(('import struct class enum protocol extension actor func var let init deinit return if else guard for in while repeat switch case default break continue ' +
  'where do try catch throw throws rethrows async await some any self Self super static final private fileprivate internal public open override mutating ' +
  'nonisolated isolated inout typealias associatedtype subscript defer is as nil true false weak unowned lazy indirect convenience required operator precedencegroup').split(' '));

export function tokenize(line) {
  const out = []; let i = 0; const n = line.length;
  const isLetter = (c) => /[A-Za-zÀ-￿]/.test(c);
  const isDigit = (c) => /[0-9]/.test(c);
  while (i < n) {
    const c = line[i];
    if (c === '/' && line[i + 1] === '/') { out.push([line.slice(i), 'comment']); return out; }
    if (c === '#' && (i === 0 || /\s/.test(line[i - 1]))) {
      const rest = line.slice(i);
      if (/^#(if|else|endif|available|Preview)/.test(rest)) { const m = rest.match(/^#\w+/)[0]; out.push([m, 'keyword']); i += m.length; continue; }
      out.push([rest, 'comment']); return out;
    }
    if (c === '"') {
      let j = i + 1;
      while (j < n) { if (line[j] === '\\') { j += 2; continue; } if (line[j] === '"') { j++; break; } j++; }
      out.push([line.slice(i, j), 'string']); i = j; continue;
    }
    if (isDigit(c)) { let j = i; while (j < n && /[0-9._xA-Fa-f]/.test(line[j])) j++; out.push([line.slice(i, j), 'number']); i = j; continue; }
    if (isLetter(c) || c === '_' || c === '@') {
      let j = i + 1; while (j < n && (isLetter(line[j]) || isDigit(line[j]) || line[j] === '_')) j++;
      const w = line.slice(i, j);
      let kind = 'plain';
      if (w.startsWith('@') || KEYWORDS.has(w)) kind = 'keyword';
      else if (/^[A-Z]/.test(w)) kind = 'type';
      else if (line[j] === '(') kind = 'function';
      out.push([w, kind]); i = j; continue;
    }
    out.push([c, 'plain']); i++;
  }
  return out;
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}

function rgba(hexc, a) { const n = parseInt(hexc.slice(1), 16); return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`; }

function fitText(ctx, text, maxW) {
  if (ctx.measureText(text).width <= maxW) return text;
  let t = text; while (t.length > 1 && ctx.measureText(t + '…').width > maxW) t = t.slice(0, -1);
  return t + '…';
}

/** Draws one code card (title, subtitle, highlighted lines, layer band, role chip). */
export function drawCard(canvas, { title, subtitle, lines, band, chip }) {
  canvas.width = CARD_W; canvas.height = CARD_H;
  const ctx = canvas.getContext('2d');
  const W = CARD_W, H = CARD_H;
  ctx.clearRect(0, 0, W, H);
  roundRect(ctx, 2, 2, W - 4, H - 4, 22);
  ctx.fillStyle = '#0E1220'; ctx.fill();
  ctx.save(); roundRect(ctx, 2, 2, W - 4, H - 4, 22); ctx.clip();
  ctx.fillStyle = band; ctx.fillRect(0, 0, 12, H);
  const g = ctx.createLinearGradient(0, 0, 0, 90); g.addColorStop(0, rgba(band, 0.22)); g.addColorStop(1, rgba(band, 0));
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, 90);
  ctx.restore();
  roundRect(ctx, 2, 2, W - 4, H - 4, 22); ctx.strokeStyle = rgba(band, 0.75); ctx.lineWidth = 3; ctx.stroke();

  const left = 30; let titleRight = 20;
  ctx.textBaseline = 'alphabetic';
  if (chip && chip.label) {
    ctx.font = `bold 13px ${MONO}`;
    const tw = ctx.measureText(chip.label).width;
    const cx = W - 18 - tw - 20, cy = 20, cw = tw + 20, chh = 24;
    roundRect(ctx, cx, cy, cw, chh, 12); ctx.fillStyle = rgba(chip.color, 0.22); ctx.fill();
    roundRect(ctx, cx, cy, cw, chh, 12); ctx.strokeStyle = rgba(chip.color, 0.8); ctx.lineWidth = 1.5; ctx.stroke();
    ctx.fillStyle = chip.color; ctx.fillText(chip.label, cx + 10, 37);
    titleRight = W - cx + 8;
  }
  ctx.font = `bold 24px ${MONO}`; ctx.fillStyle = P.plain;
  ctx.fillText(fitText(ctx, title, W - left - titleRight), left, 40);
  ctx.font = `14px ${MONO}`; ctx.fillStyle = P.comment;
  ctx.fillText(fitText(ctx, subtitle, W - left - 20), left, 62);
  ctx.strokeStyle = 'rgba(255,255,255,0.14)'; ctx.lineWidth = 1;
  ctx.beginPath(); ctx.moveTo(left, 76.5); ctx.lineTo(W - 20, 76.5); ctx.stroke();

  ctx.font = `15px ${MONO}`;
  let y = 100;
  for (const raw of lines) {
    if (y > H - 14) break;
    const line = raw.replace(/\t/g, '    ');
    let x = left;
    for (const [text, kind] of tokenize(line)) {
      if (x >= W - 24) break;
      ctx.fillStyle = P[kind] || P.plain;
      const t = fitText(ctx, text, W - 24 - x);
      ctx.fillText(t, x, y);
      x += ctx.measureText(t).width;
    }
    y += 20;
  }
  return canvas;
}

/** Card content for a snapshot node, matching CardContent.subtitle / chip and SourceProvider's folder previews. */
export function cardContent(node, graph, metrics) {
  const lines = node.lineCount;
  const parts = [node.kind, node.layer, `${lines} lines`];
  if (metrics && (node.kind === 'file' || node.kind === 'type' || node.kind === 'extensionDecl')) {
    if (metrics.fanIn + metrics.fanOut > 0) parts.push(`in ${metrics.fanIn} / out ${metrics.fanOut}`);
  }
  let code = node.preview.filter((l, i) => !(i === 0 && l === ''));
  if (node.kind === 'folder' || node.kind === 'module') {
    const kids = graph.children[node.index] || [];
    code = [`// ${node.id}`, `// ${node.kind === 'module' ? 'Module' : 'Folder'} ${node.name}: ${kids.length} items`];
    for (const k of kids.slice(0, 9)) code.push(`//   ├─ ${graph.nodes[k].name}`);
  }
  const role = node.role ? ROLE[node.role] : null;
  return { title: node.name, subtitle: parts.join(' · '), lines: code, band: node.layerColor, chip: role && role.label ? role : null };
}
