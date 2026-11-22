// Photo spots in the world (specs/photo.md P1): spot list, reach, the framing camera, the frame →
// world shot conversion. No DOM, no Babylon: the client feeds the car pose and the camera rig.
import type { Tuning, TuningLoop } from '../gen/tuning';
import { photoConfig, PhotoRules, type PhotoState, type PhotoVerdict } from './rules';

/** A photo spot: parking point and look in metres, the view radius in metres and dm. */
export interface PhotoPoint {
  id: string;
  name: string;
  x: number;
  y: number;
  heading: number;
  lookX: number;
  lookY: number;
  subjectM: number;
  /** look in dm and subject_dm, as the P0 module sees them. */
  lookXDm: number;
  lookYDm: number;
  subjectDm: number;
}

interface SpotLike {
  id: string;
  kind: string;
  name: string;
  parkX: number;
  parkY: number;
  parkHeading: number;
  lookX: number;
  lookY: number;
  subjectDm: number;
}

/** Photo spots = spots `kind: photo` with a view (subject_dm > 0), in spots.pb order. */
export function photoSpotsOf(spots: readonly SpotLike[]): PhotoPoint[] {
  return spots
    .filter((s) => s.kind === 'photo' && s.subjectDm > 0)
    .map((s) => ({
      id: s.id, name: s.name, x: s.parkX / 10, y: s.parkY / 10, heading: s.parkHeading,
      lookX: s.lookX / 10, lookY: s.lookY / 10, subjectM: s.subjectDm / 10,
      lookXDm: s.lookX, lookYDm: s.lookY, subjectDm: s.subjectDm,
    }));
}

/** Same conditions as "Hrát" at a spot (specs/loop.md): standing, layer 0, parking point in reach. */
export function photoInReach(p: PhotoPoint, x: number, y: number, speed: number, layer: number, t: TuningLoop): boolean {
  return speed <= t.stopSpeedMps && layer === 0 && (p.x - x) ** 2 + (p.y - y) ** 2 <= t.spotRadiusM ** 2;
}

/** The nearest photo spot in reach of the car, or null. */
export function photoSpotAt(points: readonly PhotoPoint[], x: number, y: number, speed: number, layer: number, t: TuningLoop): PhotoPoint | null {
  let best: PhotoPoint | null = null, bd = Infinity;
  for (const p of points) {
    if (!photoInReach(p, x, y, speed, layer, t)) continue;
    const d = (p.x - x) ** 2 + (p.y - y) ** 2;
    if (d < bd) {
      bd = d;
      best = p;
    }
  }
  return best;
}

/** The Camera is not offered during a minigame, the Taxi shift or while wanted (spec "Kdy ne"). */
export type PhotoBlock = 'busy' | 'wanted' | null;
export function photoBlocked(s: { busy: boolean; inWorldGame: boolean; wanted: number }): PhotoBlock {
  if (s.busy || s.inWorldGame) return 'busy';
  return s.wanted > 0 ? 'wanted' : null;
}

/** Framing view width (m): max(view_width_m.slow, 2 × subject_m × photo.view_factor). */
export function photoViewWidth(t: Tuning, subjectM: number): number {
  return Math.max(t.viewWidthM.slow, 2 * subjectM * t.photo.viewFactor);
}

/** The camera as the photo code sees it (CameraRig). */
export interface RigPose {
  x: number;
  y: number;
  heading: number;
  viewWidth: number;
}

/** CSS pixel → world point (m): the inverse of CameraRig.toScreen. */
export function screenToWorld(rig: RigPose, sx: number, sy: number, w: number, h: number, t: Tuning): { x: number; y: number } {
  const ppm = w / rig.viewWidth;
  const a = Math.PI / 2 - rig.heading;
  const rx = (sx - w * t.carAnchor.x) / ppm;
  const ry = (h * t.carAnchor.y - sy) / ppm;
  return { x: rig.x + rx * Math.cos(a) + ry * Math.sin(a), y: rig.y - rx * Math.sin(a) + ry * Math.cos(a) };
}

/**
 * Rig position (the point drawn at the car anchor) that puts world point (mx, my) in the middle of
 * the screen with the given heading and view width.
 */
export function rigForCentre(mx: number, my: number, heading: number, viewWidth: number, w: number, h: number, t: Tuning): { x: number; y: number } {
  // The screen centre in a rig sitting at (mx, my) is a world point; shift by the opposite offset.
  const c = screenToWorld({ x: mx, y: my, heading, viewWidth }, w / 2, h / 2, w, h, t);
  return { x: 2 * mx - c.x, y: 2 * my - c.y };
}

/** Whole dm of metres: floor(x × 10 + 0.5). */
export const toDm = (m: number): number => Math.floor(m * 10 + 0.5);

/** A shot in the P0 module's units. */
export interface PhotoShot {
  cx: number;
  cy: number;
  hw: number;
  hh: number;
}

/**
 * The frame dragged between two opposite corners (CSS pixels, screen-aligned) → a shot: the frame
 * centre to a world point, half sides ÷ the camera scale (pixels per metre), whole dm, at least 1.
 */
export function frameToShot(rig: RigPose, x0: number, y0: number, x1: number, y1: number, w: number, h: number, t: Tuning): PhotoShot {
  const ppm = w / rig.viewWidth;
  const c = screenToWorld(rig, (x0 + x1) / 2, (y0 + y1) / 2, w, h, t);
  const half = (px: number): number => Math.max(1, toDm(Math.abs(px) / 2 / ppm));
  return { cx: toDm(c.x), cy: toDm(c.y), hw: half(x1 - x0), hh: half(y1 - y0) };
}

const smooth = (k: number): number => k * k * (3 - 2 * k);

/**
 * The camera glide of the Camera mode (photo.zoom_s): `into` from the driving pose to the framing
 * pose, `out` back to the car. Holds no rig; `pose()` gives the pose for the current time.
 */
export class PhotoGlide {
  private s = 0;
  constructor(private readonly from: RigPose, private readonly to: () => RigPose, readonly seconds: number) {}

  step(dt: number): void {
    this.s += Math.max(0, dt);
  }

  get done(): boolean {
    return this.s >= this.seconds;
  }

  pose(): RigPose {
    const k = this.seconds > 0 ? smooth(Math.min(1, this.s / this.seconds)) : 1;
    const b = this.to(), a = this.from;
    return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k, heading: a.heading, viewWidth: a.viewWidth + (b.viewWidth - a.viewWidth) * k };
  }
}

/** The photo module of one session: photographed spots, shots. */
export class PhotoWorld {
  readonly rules = new PhotoRules();
  state: PhotoState;
  private readonly byId: Map<string, PhotoPoint>;

  constructor(readonly points: readonly PhotoPoint[], tuning: Tuning) {
    this.state = this.rules.init(photoConfig(tuning.photo, points.map((p) => ({ id: p.id, x: p.lookXDm, y: p.lookYDm, r: p.subjectDm }))), 0);
    this.byId = new Map(points.map((p) => [p.id, p]));
  }

  /** From Passport stamps: `photo:<id>` → load (unknown ids drop silently). */
  loadStamps(stamps: readonly string[]): void {
    const taken = stamps.filter((s) => s.startsWith('photo:')).map((s) => s.slice(6));
    this.state = this.rules.apply(this.state, { by: 'player', op: 'load', taken });
  }

  isTaken(id: string): boolean {
    return this.state.taken.includes(id);
  }

  point(id: string): PhotoPoint | undefined {
    return this.byId.get(id);
  }

  /** A shot at spot `id`; the verdict, null for an unknown spot. */
  shoot(id: string, s: PhotoShot): PhotoVerdict | null {
    if (!this.byId.has(id)) return null;
    this.state = this.rules.apply(this.state, { by: 'player', op: 'shoot', spot: id, ...s });
    return this.state.last.verdict;
  }
}
