// Placeholder postcard picture (specs/passport.md "Pohlednice"): a list of shapes on a 300 × 200
// canvas, drawn by the UI. Real game-style illustrations come later from ComfyUI (tools/artgen).
import { tokens } from '../gen/tokens';

export type Shape =
  | { t: 'rect'; x: number; y: number; w: number; h: number; fill: string }
  | { t: 'circle'; x: number; y: number; r: number; fill: string }
  | { t: 'poly'; pts: number[]; fill: string };

export const POSTCARD_W = 300;
export const POSTCARD_H = 200;

/** 32-bit FNV-1a over the UTF-8 bytes of s. */
export function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(s)) {
    h ^= b;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

export function postcardShapes(id: string, heightM: number): Shape[] {
  const base = 170;
  const out: Shape[] = [
    { t: 'rect', x: 0, y: 0, w: POSTCARD_W, h: POSTCARD_H, fill: tokens.colorPassportSky },
  ];
  const hash = fnv1a(id);
  for (let i = 0; i < 6; i++) {
    const h = 30 + ((hash >>> (4 * i)) & 31);
    out.push({ t: 'rect', x: 6 + 50 * i, y: base - h, w: 44, h, fill: tokens.colorPassportSkyline });
  }
  if (heightM > 0) {
    out.push({ t: 'rect', x: 0, y: base, w: POSTCARD_W, h: POSTCARD_H - base, fill: tokens.colorPassportGround });
    const bh = Math.round(30 + (120 * Math.min(heightM, 541)) / 541);
    const bw = heightM >= 150 ? 56 : 110;
    const left = 150 - bw / 2;
    const top = base - bh;
    out.push({ t: 'rect', x: left, y: top, w: bw, h: bh, fill: tokens.colorPassportTower });
    for (let r = 0; top + 9 + 12 * r + 6 <= 164; r++) {
      for (let c = 0; left + 9 + 12 * c + 6 <= left + bw - 3; c++) {
        out.push({ t: 'rect', x: left + 9 + 12 * c, y: top + 9 + 12 * r, w: 6, h: 6, fill: tokens.colorPassportWindow });
      }
    }
    if (heightM >= 300) {
      out.push({ t: 'poly', pts: [150 - bw / 6, top, 150 + bw / 6, top, 150, top - 22], fill: tokens.colorPassportTower });
    }
  } else {
    out.push({ t: 'rect', x: 0, y: 130, w: POSTCARD_W, h: POSTCARD_H - 130, fill: tokens.colorPassportPark });
    for (let i = 0; i < 5; i++) out.push({ t: 'circle', x: 60 + 45 * i, y: 128, r: 14, fill: tokens.colorPassportTree });
  }
  return out;
}
