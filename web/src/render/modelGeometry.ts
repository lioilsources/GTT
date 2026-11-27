import { ModelRole } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { BuildingData } from '../world/chunk';
import type { ModelData } from '../world/models';
import { cameraHeight, displayHeight, extrusionScale } from '../world/camera';
import { TEX_SIZE, Tris } from './geometry';
import { cityTokenPrefix, rgba, type Palette, type Rgba } from './palette';

/** Texture coordinate of a plain texel of the facade texture (as building roofs). */
const PLAIN_UV = 2 / TEX_SIZE;

/** Role colours (specs/models.md): wall = the city's landmark colour, the rest color.model.<day|night>. */
export function roleColors(pal: Palette, cityId: string): Rgba[] {
  const tk = tokens as unknown as Record<string, unknown>;
  const pre = cityTokenPrefix(cityId) + 'Model';
  const pick = (role: string, day: string, night: string): Rgba => {
    const city = tk[pre + role];
    if (!pal.night && typeof city === 'string') return rgba(city);
    return rgba(pal.night ? night : day);
  };
  const out: Rgba[] = [];
  out[ModelRole.ROLE_WALL] = pal.landmark;
  out[ModelRole.ROLE_ROOF] = pick('Roof', tokens.colorModelDayRoof, tokens.colorModelNightRoof);
  out[ModelRole.ROLE_COPPER] = pick('Copper', tokens.colorModelDayCopper, tokens.colorModelNightCopper);
  out[ModelRole.ROLE_STONE] = pick('Stone', tokens.colorModelDayStone, tokens.colorModelNightStone);
  out[ModelRole.ROLE_GLASS] = pick('Glass', tokens.colorModelDayGlass, tokens.colorModelNightGlass);
  out[ModelRole.ROLE_GOLD] = pick('Gold', tokens.colorModelDayGold, tokens.colorModelNightGold);
  return out;
}

function lit(c: Rgba, k: number): Rgba {
  return [Math.min(1, c[0] * k), Math.min(1, c[1] * k), Math.min(1, c[2] * k), 1];
}

/**
 * The full model (specs/models.md "Šikmý pohled"): vertices at z = base_z + displayHeight(z_v),
 * flat shaded per triangle: walls ambient + (1 − ambient) × max(0, n · sun) as buildings, roofs
 * roofLight, in between by the slope.
 */
export function modelTris(m: ModelData, pal: Palette, cityId: string, tuning: Tuning, out: Tris, relief = true): void {
  const H = cameraHeight(tuning);
  const cols = roleColors(pal, cityId);
  // Foot vertices may lie below the foot (they follow the terrain down, specs/models.md "Pata").
  const disp = (z: number): number => (z <= 0 ? z : displayHeight(extrusionScale(z, tuning), H));
  for (const p of m.parts) {
    const base = relief ? p.baseZ : 0;
    const P = p.pos;
    for (let k = 0; k + 2 < p.tris.length; k += 3) {
      const a = 3 * p.tris[k]!, b = 3 * p.tris[k + 1]!, c = 3 * p.tris[k + 2]!;
      const ax = P[a]!, ay = P[a + 1]!, az = base + disp(P[a + 2]!);
      const bx = P[b]!, by = P[b + 1]!, bz = base + disp(P[b + 2]!);
      const cx = P[c]!, cy = P[c + 1]!, cz = base + disp(P[c + 2]!);
      const ux = bx - ax, uy = by - ay, uz = bz - az, vx = cx - ax, vy = cy - ay, vz = cz - az;
      const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      const nl = Math.hypot(nx, ny, nz);
      if (nl < 1e-9) continue;
      // Lit like buildings: walls by the palette sun, roofs by roofLight, blended by the slope.
      const nh = Math.hypot(nx, ny);
      const wall = pal.ambient + (1 - pal.ambient) * (nh > 1e-9 ? Math.max(0, (nx * pal.sunX + ny * pal.sunY) / nh) : 0);
      const t = Math.abs(nz) / nl;
      const light = (1 - t) * wall + t * pal.roofLight;
      const col = lit(cols[k / 3 < p.roles.length ? p.roles[k / 3]! : 0] ?? pal.landmark, light);
      const i0 = out.vertex(ax, ay, az, col, PLAIN_UV, PLAIN_UV);
      const i1 = out.vertex(bx, by, bz, col, PLAIN_UV, PLAIN_UV);
      const i2 = out.vertex(cx, cy, cz, col, PLAIN_UV, PLAIN_UV);
      out.tri(i0, i1, i2);
    }
  }
}

/** Roof colour of a plan polygon: roof × (0.7 + 0.1 × shade) (specs/models.md "Pohled shora"). */
export function planRoofColor(pal: Palette, cityId: string, shade: number): Rgba {
  return lit(roleColors(pal, cityId)[ModelRole.ROLE_ROOF]!, 0.7 + 0.1 * shade);
}

/** The roof plan as buildings: each polygon a prism from base_z to height_m (top-down view, shadows). */
export function planBuildings(m: ModelData, relief = true): BuildingData[] {
  return m.plan.map((p) => {
    const n = p.xy.length >> 1;
    let cx = 0, cy = 0;
    const outer = p.ringEnds[0] ?? n;
    for (let i = 0; i < outer; i++) {
      cx += p.xy[2 * i]!;
      cy += p.xy[2 * i + 1]!;
    }
    cx /= outer;
    cy /= outer;
    let r2 = 0;
    const wallU = new Float32Array(n);
    for (let i = 0; i < outer; i++) r2 = Math.max(r2, (p.xy[2 * i]! - cx) ** 2 + (p.xy[2 * i + 1]! - cy) ** 2);
    return {
      xy: p.xy, ringEnds: p.ringEnds, roof: Uint16Array.from(p.tris), height: p.height, minHeight: 0, landmark: 1,
      collide: false, seed: 0, cx, cy, radius: Math.sqrt(r2), wallU, baseZ: relief ? p.baseZ : 0,
    };
  });
}

/** Top-down roof plan: prisms with walls in the landmark colour and roofs by shade. */
export function planTris(m: ModelData, pal: Palette, cityId: string, tuning: Tuning, out: Tris, relief = true): void {
  const H = cameraHeight(tuning);
  const blds = planBuildings(m, relief);
  const order = blds.map((_, i) => i).sort((a, b) => m.plan[a]!.height - m.plan[b]!.height);
  for (const i of order) {
    const b = blds[i]!;
    const z0 = b.baseZ ?? 0;
    const z1 = z0 + displayHeight(extrusionScale(Math.max(0.1, b.height), tuning), H);
    const xy = b.xy;
    let start = 0;
    for (const end of b.ringEnds) {
      for (let k = start; k < end; k++) {
        const j = k + 1 < end ? k + 1 : start;
        const ax = xy[2 * k]!, ay = xy[2 * k + 1]!, bx = xy[2 * j]!, by = xy[2 * j + 1]!;
        const len = Math.hypot(bx - ax, by - ay);
        if (len < 0.05) continue;
        const nx = (by - ay) / len, ny = -(bx - ax) / len;
        const col = lit(pal.landmark, pal.ambient + (1 - pal.ambient) * Math.max(0, nx * pal.sunX + ny * pal.sunY));
        const v0 = out.vertex(ax, ay, z0, col, PLAIN_UV, PLAIN_UV);
        const v1 = out.vertex(bx, by, z0, col, PLAIN_UV, PLAIN_UV);
        const v2 = out.vertex(bx, by, z1, col, PLAIN_UV, PLAIN_UV);
        const v3 = out.vertex(ax, ay, z1, col, PLAIN_UV, PLAIN_UV);
        out.idx.push(v0, v2, v1, v0, v3, v2);
      }
      start = end;
    }
    const roofC = planRoofColor(pal, cityId, m.plan[i]!.shade);
    const rb = out.vertexCount;
    for (let k = 0; k < xy.length / 2; k++) out.vertex(xy[2 * k]!, xy[2 * k + 1]!, z1, roofC, PLAIN_UV, PLAIN_UV);
    for (let k = 0; k + 2 < b.roof.length; k += 3) out.tri(rb + b.roof[k]!, rb + b.roof[k + 1]!, rb + b.roof[k + 2]!);
  }
}
