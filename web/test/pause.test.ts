import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { parse } from 'yaml';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';

import { ControlInput } from '../src/drive/controls';
import { DriveWorld } from '../src/drive/driveWorld';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { OverlayRegistry, overlays, paused, PauseGate, pausingOverlays, type OverlayKind } from '../src/pause';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const car = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;

afterEach(() => overlays.clear());

describe('pause registry (specs/pause.md)', () => {
  it('paused(overlays): every listed overlay pauses, toasts do not', () => {
    expect(paused([])).toBe(false);
    expect(paused(['toast'])).toBe(false);
    expect(paused(['toast', 'toast'])).toBe(false);
    for (const k of pausingOverlays) {
      expect(paused([k]), k).toBe(true);
      expect(paused(['toast', k]), k).toBe(true);
    }
    expect([...pausingOverlays].sort()).toEqual(
      ['about', 'arrival', 'bench', 'booth', 'debug', 'dialogue', 'gallery', 'garage', 'intro', 'minigame', 'passport', 'phone', 'photo', 'postcard', 'result', 'shop', 'travel'],
    );
  });

  it('counts each opening; release is idempotent', () => {
    const r = new OverlayRegistry();
    const a = r.open('postcard');
    const b = r.open('postcard');
    const toast = r.open('toast');
    expect(r.paused).toBe(true);
    a();
    a();
    expect(r.paused).toBe(true);
    expect(r.isOpen('postcard')).toBe(true);
    b();
    expect(r.paused).toBe(false);
    expect(r.kinds).toEqual(['toast']);
    toast();
    expect(r.kinds).toEqual([]);
  });

  it('the gate gives 0 dt while paused and zeroes the input on resume', () => {
    const r = new OverlayRegistry();
    const gate = new PauseGate(r);
    const input = new ControlInput();
    let resumed = 0;
    const onResume = (): void => void resumed++;
    expect(gate.frame(0.016, input, onResume)).toBe(0.016);
    const close = r.open('phone');
    input.throttle = 1;
    input.steer = -1;
    input.handbrake = true;
    expect(gate.frame(0.016, input, onResume)).toBe(0);
    expect(input).toMatchObject({ throttle: 0, steer: 0, handbrake: false });
    // A finger still "held" from before the overlay: dropped on resume.
    input.throttle = 1;
    input.brake = 1;
    close();
    expect(gate.frame(0.016, input, onResume)).toBe(0.016);
    expect(input).toMatchObject({ throttle: 0, brake: 0, steer: 0, handbrake: false, boost: false });
    expect(resumed).toBe(1);
    input.throttle = 1;
    gate.frame(0.016, input, onResume);
    expect(input.throttle).toBe(1);
    expect(resumed).toBe(1);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };

describe.skipIf(!existsSync(pack))('pause freezes the world in NYC', () => {
  let city: City;
  const chunks: ChunkData[] = [];
  beforeAll(async () => {
    city = await City.load(source);
    const cx = Math.floor(city.startX / city.chunkM), cy = Math.floor(city.startY / city.chunkM);
    for (const c of city.manifest.chunks) {
      if (Math.abs(c.x - cx) <= 2 && Math.abs(c.y - cy) <= 2) chunks.push(await prepareChunk(await source.read(chunkPath(c.x, c.y))));
    }
  });

  type Snap = { x: number; y: number; time: number; clock: number; traffic: number[] };
  const snap = (d: DriveWorld): Snap => ({
    x: d.car.x,
    y: d.car.y,
    time: d.time,
    clock: d.traffic?.clockMs ?? 0,
    traffic: d.traffic?.cars.flatMap((c) => [c.x, c.y]) ?? [],
  });

  it('phone, garage and postcard stop the car and the traffic; a toast does not', () => {
    const d = new DriveWorld(city, car, tuning);
    for (const c of chunks) d.addChunk(c);
    const gate = new PauseGate(overlays);
    const frame = (): void => d.update(gate.frame(1 / 60, d.input));
    for (let i = 0; i < 60; i++) frame();
    expect(d.car.speed).toBeGreaterThan(1);
    expect(d.traffic?.cars.length ?? 0).toBeGreaterThan(0);
    for (const kind of ['phone', 'garage', 'postcard'] as OverlayKind[]) {
      const close = overlays.open(kind);
      const before = snap(d);
      for (let i = 0; i < 30; i++) frame();
      expect(snap(d), kind).toEqual(before);
      close();
      for (let i = 0; i < 30; i++) frame();
      const after = snap(d);
      expect(Math.hypot(after.x - before.x, after.y - before.y), kind).toBeGreaterThan(1);
      expect(after.time, kind).toBeGreaterThan(before.time);
      expect(after.clock, kind).toBeGreaterThan(before.clock);
    }
    // A short notice (cash, fine, wanted, nav) does not pause.
    const toast = overlays.open('toast');
    const before = snap(d);
    for (let i = 0; i < 30; i++) frame();
    const after = snap(d);
    expect(Math.hypot(after.x - before.x, after.y - before.y)).toBeGreaterThan(1);
    expect(after.time).toBeGreaterThan(before.time);
    toast();
  });
});
