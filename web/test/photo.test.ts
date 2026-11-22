import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Tuning } from '../src/gen/tuning';
import { passportCity, PassportTracker } from '../src/passport/tracker';
import { overlays, paused, pausingOverlays } from '../src/pause';
import {
  frameToShot, photoBlocked, PhotoGlide, photoInReach, photoSpotAt, photoSpotsOf, photoViewWidth, PhotoWorld, rigForCentre,
  screenToWorld, toDm, type RigPose,
} from '../src/photo/photo';
import { frameVerdict, isqrt, photoConfig, PhotoRules, type PhotoAction, type PhotoConfig } from '../src/photo/rules';
import { CameraRig } from '../src/render/worldView';
import { decodeSpots } from '../src/world/citypack';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

afterEach(() => overlays.clear());

const A = { id: 'a', x: 1000, y: 2000, r: 300 };
const B = { id: 'b', x: -500, y: 400, r: 100 };
const cfg: PhotoConfig = { spots: [A, B], loosePct: 400 };
const shoot = (spot: string, cx: number, cy: number, hw: number, hh = hw): PhotoAction => ({ by: 'player', op: 'shoot', spot, cx, cy, hw, hh });

describe('photo rules (specs/photo.md)', () => {
  it('init: nothing taken, empty last; config from tuning', () => {
    const r = new PhotoRules();
    expect(r.init(cfg, 7)).toEqual({ taken: [], last: { spot: '', verdict: '' } });
    expect(photoConfig(tuning.photo, [A])).toEqual({ spots: [A], loosePct: tuning.photo.loosePct });
    expect(r.result(r.init(cfg, 0))).toBeNull();
  });

  it('load: only known ids, no duplicates, list order; last empty', () => {
    const r = new PhotoRules();
    let s = r.apply(r.init(cfg, 0), shoot('a', 1000, 2000, 300));
    s = r.apply(s, { by: 'player', op: 'load', taken: ['b', 'gone', 'a', 'b'] });
    expect(s).toEqual({ taken: ['b', 'a'], last: { spot: '', verdict: '' } });
  });

  it('shoot: ok, again, cut (off centre, too small, short side), loose with the inclusive limit', () => {
    const r = new PhotoRules();
    let s = r.init(cfg, 0);
    s = r.apply(s, shoot('a', 1000, 2000, 300));
    expect(s).toEqual({ taken: ['a'], last: { spot: 'a', verdict: 'ok' } });
    s = r.apply(s, shoot('a', 1000, 2000, 400, 500));
    expect(s.last.verdict).toBe('again');
    expect(s.taken).toEqual(['a']);
    expect(r.apply(s, shoot('b', -499, 400, 100)).last.verdict).toBe('cut');
    expect(r.apply(s, shoot('b', -500, 400, 99)).last.verdict).toBe('cut');
    expect(r.apply(s, shoot('b', -500, 400, 1000, 99)).last.verdict).toBe('cut');
    expect(r.apply(s, shoot('b', -500, 400, 401)).last.verdict).toBe('loose');
    const ok = r.apply(s, shoot('b', -500, 400, 400));
    expect(ok).toEqual({ taken: ['a', 'b'], last: { spot: 'b', verdict: 'ok' } });
  });

  it('distance is floor(sqrt(dx² + dy²))', () => {
    expect([isqrt(0), isqrt(1), isqrt(2), isqrt(24), isqrt(25), isqrt(26)]).toEqual([0, 1, 1, 4, 5, 5]);
    expect(isqrt(4503599627370495)).toBe(67108863);
    // d = floor(sqrt(2)) = 1: 1 + 50 ≤ 51 fits.
    expect(frameVerdict({ id: 'c', x: 0, y: 0, r: 50 }, 400, 1, 1, 51, 51)).toBe('fits');
    expect(frameVerdict({ id: 'c', x: 0, y: 0, r: 50 }, 400, 3, 4, 54, 54)).toBe('cut');
  });

  it('illegal: unknown spot, hw or hh < 1, non-integers, unknown op, by ≠ player, bad load', () => {
    const r = new PhotoRules();
    const s = r.init(cfg, 0);
    const bad: unknown[] = [
      shoot('zzz', 1000, 2000, 300),
      shoot('a', 1000, 2000, 0, 300),
      shoot('a', 1000, 2000, 300, 0),
      shoot('a', 1000, 2000, -5),
      shoot('a', 1000.5, 2000, 300),
      shoot('a', 1000, 2000, 300.5),
      { by: 'player', op: 'snap' },
      { by: 'ai', op: 'load', taken: [] },
      { by: 'player', op: 'load', taken: [1] },
      { by: 'player', op: 'load' },
    ];
    for (const a of bad) expect(() => r.apply(s, a as PhotoAction), JSON.stringify(a)).toThrow();
  });

  it('legalActions: load [] and the exact view of every spot, all legal', () => {
    const r = new PhotoRules();
    const s = r.init(cfg, 0);
    const acts = r.legalActions(s);
    expect(acts).toEqual([{ by: 'player', op: 'load', taken: [] }, shoot('a', 1000, 2000, 300), shoot('b', -500, 400, 100)]);
    for (const a of acts) expect(() => r.apply(s, a)).not.toThrow();
  });
});

const spot = (id: string, kind: string, o: Partial<Record<'parkX' | 'parkY' | 'lookX' | 'lookY' | 'subjectDm', number>> = {}) => ({
  id, kind, name: `Spot ${id}`, minigame: '', parkX: 0, parkY: 0, parkHeading: 0.5, lookX: 0, lookY: 0, subjectDm: 0, ...o,
});

describe('photo spots in the world', () => {
  const spots = [
    spot('p1', 'photo', { parkX: 100, parkY: 200, lookX: 600, lookY: 200, subjectDm: 400 }),
    spot('bar', 'bar'),
    spot('p2', 'photo', { parkX: -1000, parkY: 0, lookX: -1000, lookY: 1000, subjectDm: 300 }),
    spot('p0', 'photo', { subjectDm: 0 }),
  ];

  it('photo spots in spots.pb order, metres and dm', () => {
    const p = photoSpotsOf(spots);
    expect(p.map((x) => x.id)).toEqual(['p1', 'p2']);
    expect(p[0]).toMatchObject({ x: 10, y: 20, lookX: 60, lookY: 20, subjectM: 40, lookXDm: 600, lookYDm: 200, subjectDm: 400, heading: 0.5 });
  });

  it('reach: the "Hrát" conditions; the nearest spot in reach', () => {
    const [p1, p2] = photoSpotsOf(spots);
    const l = tuning.loop;
    expect(photoInReach(p1!, 10, 20, 0, 0, l)).toBe(true);
    expect(photoInReach(p1!, 10, 20, l.stopSpeedMps + 1, 0, l)).toBe(false);
    expect(photoInReach(p1!, 10, 20, 0, 1, l)).toBe(false);
    expect(photoInReach(p1!, 10 + l.spotRadiusM + 0.1, 20, 0, 0, l)).toBe(false);
    expect(photoSpotAt([p1!, p2!], -100, 0, 0, 0, l)?.id).toBe('p2');
    expect(photoSpotAt([p1!, p2!], 500, 500, 0, 0, l)).toBeNull();
  });

  it('blocked during a minigame, the Taxi shift and while wanted', () => {
    expect(photoBlocked({ busy: false, inWorldGame: false, wanted: 0 })).toBeNull();
    expect(photoBlocked({ busy: true, inWorldGame: false, wanted: 0 })).toBe('busy');
    expect(photoBlocked({ busy: false, inWorldGame: true, wanted: 0 })).toBe('busy');
    expect(photoBlocked({ busy: false, inWorldGame: false, wanted: 2 })).toBe('wanted');
  });

  it('view width: max(view_width_m.slow, 2 × subject × view_factor)', () => {
    expect(photoViewWidth(tuning, 1)).toBe(tuning.viewWidthM.slow);
    expect(photoViewWidth(tuning, 100)).toBeCloseTo(200 * tuning.photo.viewFactor);
  });

  it('screenToWorld inverts CameraRig.toScreen; rigForCentre puts a point mid-screen', () => {
    const rig = new CameraRig();
    rig.x = 120;
    rig.y = -40;
    rig.heading = 1.1;
    rig.viewWidth = 180;
    const w = 400, h = 800;
    for (const [x, y] of [[0, 0], [130, -20], [-300, 250]] as const) {
      const s = rig.toScreen(x, y, w, h, tuning);
      const back = screenToWorld(rig, s.x, s.y, w, h, tuning);
      expect(back.x).toBeCloseTo(x, 6);
      expect(back.y).toBeCloseTo(y, 6);
    }
    const at = rigForCentre(55, 66, rig.heading, rig.viewWidth, w, h, tuning);
    rig.x = at.x;
    rig.y = at.y;
    const c = rig.toScreen(55, 66, w, h, tuning);
    expect(c.x).toBeCloseTo(w / 2, 6);
    expect(c.y).toBeCloseTo(h / 2, 6);
  });

  it('frame → shot: centre to world dm, half sides ÷ scale, rounding, at least 1', () => {
    const rig: RigPose = { x: 0, y: 0, heading: Math.PI / 2, viewWidth: 100 };
    const w = 400, h = 800; // 4 px per metre, north up
    const ax = w * tuning.carAnchor.x, ay = h * tuning.carAnchor.y;
    // A 40 × 20 px frame centred 40 px right and 80 px above the anchor: (10 m, 20 m), half sides 5 m and 2.5 m.
    expect(frameToShot(rig, ax + 20, ay - 70, ax + 60, ay - 90, w, h, tuning)).toEqual({ cx: 100, cy: 200, hw: 50, hh: 25 });
    // A tap: zero size → 1 dm.
    expect(frameToShot(rig, ax, ay, ax, ay, w, h, tuning)).toEqual({ cx: 0, cy: 0, hw: 1, hh: 1 });
    expect([toDm(1.04), toDm(1.05), toDm(-1.04), toDm(-1.06)]).toEqual([10, 11, -10, -11]);
  });

  it('glide: from the start pose to the target over the seconds, smooth', () => {
    const g = new PhotoGlide({ x: 0, y: 0, heading: 1, viewWidth: 50 }, () => ({ x: 10, y: 20, heading: 1, viewWidth: 150 }), 0.6);
    expect(g.pose()).toEqual({ x: 0, y: 0, heading: 1, viewWidth: 50 });
    g.step(0.3);
    expect(g.pose().x).toBeCloseTo(5);
    expect(g.done).toBe(false);
    g.step(0.4);
    expect(g.done).toBe(true);
    expect(g.pose()).toEqual({ x: 10, y: 20, heading: 1, viewWidth: 150 });
  });

  it('PhotoWorld: loads photo:* stamps, shoots in dm', () => {
    const pw = new PhotoWorld(photoSpotsOf(spots), tuning);
    pw.loadStamps(['landmark:x', 'photo:p2', 'photo:gone', 'photo:p2']);
    expect(pw.state.taken).toEqual(['p2']);
    expect(pw.isTaken('p2')).toBe(true);
    expect(pw.shoot('nope', { cx: 0, cy: 0, hw: 1, hh: 1 })).toBeNull();
    expect(pw.shoot('p1', { cx: 600, cy: 200, hw: 10, hh: 10 })).toBe('cut');
    expect(pw.shoot('p1', { cx: 600, cy: 200, hw: 400, hh: 600 })).toBe('ok');
    expect(pw.shoot('p2', { cx: -1000, cy: 1000, hw: 300, hh: 300 })).toBe('again');
    expect(pw.state.taken).toEqual(['p2', 'p1']);
  });

  it('passport catalog photo = photo spot ids in spot order; visit photo stamps once', () => {
    const city = passportCity({ landmarks: { items: [] }, districts: [], spots: { items: spots } });
    const tr = new PassportTracker(city, tuning.passport, ['photo:p2', 'photo:gone']);
    expect(tr.state.catalog.photo).toEqual(['p1', 'p2', 'p0']);
    expect(tr.stamps).toEqual(['photo:p2']);
    expect(tr.photoNames.get('p1')).toBe('Spot p1');
    const events: string[] = [];
    tr.onStamp((e) => events.push(`${e.kind}:${e.id}`));
    expect(tr.photo('p1')).toBe(true);
    expect(tr.photo('p1')).toBe(false);
    expect(tr.photo('bar')).toBe(false);
    expect(events).toEqual(['photo:p1']);
    expect(tr.result.kinds.photo).toEqual([2, 3]);
  });

  it('pause: the Camera mode is the pausing kind photo', () => {
    expect(pausingOverlays).toContain('photo');
    expect(paused(['photo'])).toBe(true);
    const release = overlays.open('photo');
    expect(overlays.paused).toBe(true);
    release();
    expect(overlays.paused).toBe(false);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');

describe.skipIf(!existsSync(join(pack, 'spots.pb')))('photo spots in NYC', () => {
  it('the pack has photo spots with a view; their exact view is ok', async () => {
    const spots = await decodeSpots(new Uint8Array(readFileSync(join(pack, 'spots.pb'))));
    const points = photoSpotsOf(spots.items);
    expect(points.length).toBe(spots.items.filter((s) => s.kind === 'photo').length);
    expect(points.length).toBeGreaterThan(0);
    const pw = new PhotoWorld(points, tuning);
    for (const p of points) {
      expect(Math.hypot(p.lookX - p.x, p.lookY - p.y)).toBeLessThanOrEqual(1500);
      expect(pw.shoot(p.id, { cx: p.lookXDm, cy: p.lookYDm, hw: p.subjectDm, hh: p.subjectDm })).toBe('ok');
    }
  });
});
