import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { NatureMap } from '../world/nature';
import type { CameraRig } from './worldView';

/**
 * Names of water and parks on the overlay canvas (specs/nature.md "Vykreslení shora"): water along
 * its label axis in italics, a park name at the centre of the park; street-name style (white,
 * shadow, capitals). One label per name, at the axis point nearest the view centre.
 */
export function drawNatureLabels(
  ctx: CanvasRenderingContext2D, nature: NatureMap, rig: CameraRig, size: { w: number; h: number }, tuning: Tuning,
): void {
  if (nature.empty) return;
  const r = rig.visibleRadius(size.w, size.h, tuning);
  const best = new Map<string, { x: number; y: number; dx: number; dy: number; water: boolean; d: number }>();
  const axisDir = new Map<string, { dx: number; dy: number; d: number }>();
  for (const c of nature.chunks.values()) {
    for (const l of c.labels) {
      const a = l.axis, n = a.length >> 1;
      let bx = a[0]!, by = a[1]!, bdx = 1, bdy = 0, bd = Math.hypot(bx - rig.x, by - rig.y);
      for (let i = 0; i + 1 < n; i++) {
        const ax = a[2 * i]!, ay = a[2 * i + 1]!, qx = a[2 * i + 2]!, qy = a[2 * i + 3]!;
        const dx = qx - ax, dy = qy - ay, l2 = dx * dx + dy * dy;
        if (l2 < 1e-6) continue;
        const t = Math.min(1, Math.max(0, ((rig.x - ax) * dx + (rig.y - ay) * dy) / l2));
        const px = ax + dx * t, py = ay + dy * t, d = Math.hypot(px - rig.x, py - rig.y);
        if (d < bd || i === 0) {
          bd = d;
          bx = px;
          by = py;
          const ll = Math.sqrt(l2);
          bdx = dx / ll;
          bdy = dy / ll;
        }
      }
      const ad = axisDir.get(l.name);
      if (!ad || bd < ad.d) axisDir.set(l.name, { dx: bdx, dy: bdy, d: bd });
      if (bd > r) continue;
      const prev = best.get(l.name);
      if (!prev || bd < prev.d) best.set(l.name, { x: bx, y: by, dx: bdx, dy: bdy, water: l.water, d: bd });
    }
  }
  // A river longer than the view: its label axis may lie far away, so the name also sits on the
  // named water nearest the view centre (triangle centroids), along the axis direction when known.
  for (const c of nature.chunks.values()) {
    for (const w of c.water) {
      if (w.name === '') continue;
      const prev = best.get(w.name);
      if (prev && prev.d < r * 0.5) continue;
      if (w.x1 < rig.x - r || w.x0 > rig.x + r || w.y1 < rig.y - r || w.y0 > rig.y + r) continue;
      const xy = w.xy, idx = w.idx;
      for (let i = 0; i + 2 < idx.length; i += 3) {
        const a = 2 * idx[i]!, b = 2 * idx[i + 1]!, q = 2 * idx[i + 2]!;
        const cx = (xy[a]! + xy[b]! + xy[q]!) / 3, cy = (xy[a + 1]! + xy[b + 1]! + xy[q + 1]!) / 3;
        const d = Math.hypot(cx - rig.x, cy - rig.y);
        if (d > r * 0.7) continue;
        const cur = best.get(w.name);
        if (cur && cur.d <= d) continue;
        const wide = w.x1 - w.x0 >= w.y1 - w.y0, ad = axisDir.get(w.name);
        best.set(w.name, { x: cx, y: cy, dx: ad?.dx ?? (wide ? 1 : 0), dy: ad?.dy ?? (wide ? 0 : 1), water: true, d });
      }
    }
  }
  if (best.size === 0) return;
  ctx.save();
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = tokens.colorUiStreetLabel;
  ctx.shadowColor = tokens.colorUiLabelShadow;
  ctx.shadowBlur = 3;
  ctx.letterSpacing = '1.5px';
  for (const [name, l] of best) {
    const p = rig.toScreen(l.x, l.y, size.w, size.h, tuning);
    if (p.x < -50 || p.y < -20 || p.x > size.w + 50 || p.y > size.h + 20) continue;
    ctx.font = `${l.water ? 'italic ' : ''}700 ${tokens.fontLabel}px system-ui, sans-serif`;
    let a = l.water ? rig.screenAngle(Math.atan2(l.dy, l.dx)) : 0;
    while (a > Math.PI / 2) a -= Math.PI;
    while (a < -Math.PI / 2) a += Math.PI;
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(a);
    ctx.fillText(name.toUpperCase(), 0, 0);
    ctx.restore();
  }
  ctx.restore();
}
