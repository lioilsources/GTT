import { Engine } from '@babylonjs/core/Engines/engine';
import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { WebGPUEngine } from '@babylonjs/core/Engines/webgpuEngine';

import { ASSET_BASE_URL } from './config';
import { Autopilot, frameStats } from './drive/autopilot';
import { resolveRoute } from './drive/route';
import { applyKeys, createScheme, SchemeA, SchemeB, SchemeC, type ControlScheme, type ControlSchemeId } from './drive/controls';
import { DriveWorld } from './drive/driveWorld';
import { t as tr, type Locale, type MessageKey } from './gen/i18n';
import { cityIdValues, type CityId } from './gen/ids';
import type { BenchResult, BenchRoute, CarSpec } from './gen/schema';
import { tokens } from './gen/tokens';
import { carPose, PedestrianWorld } from './peds/pedestrians';
import { drawPedBubbles, PedView } from './render/pedView';
import { Tuning } from './gen/tuning';
import { WorldView } from './render/worldView';
import { HttpPackSource } from './world/citypack';
import { City } from './world/model';
import { ChunkStreamer } from './world/streaming';

const params = new URLSearchParams(location.search);
const locale: Locale = navigator.language.startsWith('cs') ? 'cs' : 'en';
const t = (k: MessageKey, a?: Record<string, string | number>): string => tr(locale, k, a);
const $ = <T extends HTMLElement>(id: string): T => document.getElementById(id) as T;

const canvas = $<HTMLCanvasElement>('world');
const overlay = $<HTMLCanvasElement>('overlay');
const ctx = overlay.getContext('2d')!;

/** WebGL2 by default; WebGPU only on request (?gpu=webgpu), never required (DUALSTACK 2). */
async function createEngine(): Promise<AbstractEngine> {
  if (params.get('gpu') === 'webgpu' && (await WebGPUEngine.IsSupportedAsync)) {
    const e = new WebGPUEngine(canvas, { antialias: true, adaptToDeviceRatio: true });
    await e.initAsync();
    return e;
  }
  return new Engine(canvas, true, { preserveDrawingBuffer: false, stencil: false, powerPreference: 'high-performance' }, true);
}

async function json<T>(path: string): Promise<T> {
  const res = await fetch(ASSET_BASE_URL + path, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  return (await res.json()) as T;
}

async function main(): Promise<void> {
  // ?gallery / ?mg=<id>: minigames without the world (specs/minigames/README.md "Galerie").
  if (params.has('gallery') || params.has('mg')) {
    const [{ runGallery }, tuning] = await Promise.all([
      import('./minigames/gallery'),
      json<unknown>('content/tuning.json').then((j) => Tuning.fromJson(j)),
    ]);
    for (const id of ['world', 'overlay', 'hud', 'loading']) $(id).hidden = true;
    const host = document.createElement('div');
    host.id = 'minigames';
    document.body.append(host);
    runGallery(host, { tuning, locale, t }, params);
    return;
  }
  const cityId = (cityIdValues as readonly string[]).includes(params.get('city') ?? '') ? (params.get('city') as CityId) : 'nyc';
  $('loading').textContent = t('loading', { city: cityId });
  $('about').textContent = t('aboutMaps');
  const tStart = performance.now();

  const [tuning, car, source] = await Promise.all([
    json<unknown>('content/tuning.json').then((j) => Tuning.fromJson(j)),
    json<CarSpec>('content/cars/m0_coupe.json'),
    HttpPackSource.open(ASSET_BASE_URL, cityId),
  ]);
  const city = await City.load(source);
  const engine = await createEngine();
  const drive = new DriveWorld(city, car, tuning);

  // ?spot=<id> puts the player on a spot (DUALSTACK 6.6).
  const spot = city.spots.items.find((s) => s.id === params.get('spot'));
  if (spot) drive.spawn(spot.parkX / 10, spot.parkY / 10, spot.parkHeading);

  const view = new WorldView(engine, city, tuning, drive);
  const peds = new PedestrianWorld(city, tuning);
  const pedView = new PedView(view.scene);
  const streamer = new ChunkStreamer(city, source, tuning, (c) => {
    drive.addChunk(c);
    view.addChunk(c);
  }, (c) => {
    drive.removeChunk(c);
    view.removeChunk(c);
  });
  // ?bench: the autopilot drives the route of specs/bench.md and reports the numbers.
  const pilot = params.has('bench')
    ? new Autopilot(resolveRoute(city.graph, await json<BenchRoute>(`content/bench/${cityId}.json`)), tuning)
    : null;
  if (pilot) {
    pilot.start(drive);
    view.carChanged();
    drive.beforeStep = (step) => pilot.step(drive, drive.input, step);
  }
  view.rig.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
  // Own chunk and its ring first (3×3 = 9); the rest streams in while driving.
  await streamer.preload(drive.car.x, drive.car.y, drive.car.heading, 9);
  $('loading').hidden = true;
  let firstFrameMs = 0;
  const loadMs = performance.now() - tStart;

  // ---------- input
  let scheme: ControlScheme = createScheme((['a', 'b', 'c'].includes(params.get('scheme') ?? '') ? params.get('scheme') : 'a') as ControlSchemeId, tuning.controls);
  const schemeBtn = $('btn-scheme');
  const schemeLabel = (): void => {
    schemeBtn.textContent = scheme.id.toUpperCase();
    schemeBtn.title = t(scheme.id === 'a' ? 'schemeA' : scheme.id === 'b' ? 'schemeB' : 'schemeC');
  };
  schemeLabel();
  schemeBtn.addEventListener('click', () => {
    scheme = createScheme(scheme.id === 'a' ? 'b' : scheme.id === 'b' ? 'c' : 'a', tuning.controls);
    schemeLabel();
  });
  let night = false;
  $('btn-night').title = t('dayNight');
  $('btn-night').addEventListener('click', () => {
    night = !night;
    view.setNight(night);
  });
  $('btn-respawn').title = t('respawn');
  $('btn-respawn').addEventListener('click', () => {
    drive.spawn(city.startX, city.startY, city.startHeading);
    view.carChanged();
    view.rig.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
  });

  const size = { w: 1, h: 1 };
  const pt = (e: PointerEvent): { x: number; y: number } => ({ x: e.clientX, y: e.clientY });
  canvas.addEventListener('pointerdown', (e) => {
    canvas.setPointerCapture(e.pointerId);
    scheme.down(e.pointerId, pt(e), size.w, size.h);
  });
  canvas.addEventListener('pointermove', (e) => scheme.move(e.pointerId, pt(e), size.w, size.h));
  const up = (e: PointerEvent): void => scheme.up(e.pointerId);
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);
  canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  const keys = new Set<string>();
  window.addEventListener('keydown', (e) => {
    keys.add(e.code);
    if (e.code.startsWith('Arrow') || e.code === 'Space') e.preventDefault();
  });
  window.addEventListener('keyup', (e) => keys.delete(e.code));
  window.addEventListener('blur', () => keys.clear());

  const resize = (): void => {
    size.w = window.innerWidth;
    size.h = window.innerHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    overlay.width = Math.round(size.w * dpr);
    overlay.height = Math.round(size.h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    engine.setHardwareScalingLevel(1 / dpr);
    engine.resize();
  };
  resize();
  window.addEventListener('resize', resize);

  // ---------- loop
  const perf = { frames: 0, acc: 0, fps: 0, frameMs: 0, worst: 0, worstAcc: 0, hudTimer: 0 };
  const frameTimes: number[] = [];
  let last = performance.now();
  engine.runRenderLoop(() => {
    const now = performance.now();
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    if (firstFrameMs === 0) firstFrameMs = now;
    if (!pilot) {
      const input = drive.input;
      input.reset();
      scheme.update(input);
      applyKeys(keys, input);
    }
    drive.update(dt);
    const c = drive.car;
    view.rig.follow(c.x, c.y, c.heading, c.speed, dt, tuning, c.forwardSpeed < -0.5);
    streamer.update(c.x, c.y, c.heading, now);
    peds.update(dt, [carPose(c)], view.rig.visibleRadius(size.w, size.h, tuning), night);
    pedView.update(peds);
    view.render();
    drawOverlay();

    frameTimes.push(dt * 1000);
    if (frameTimes.length > 600) frameTimes.shift();
    perf.frames++;
    perf.acc += dt;
    perf.worstAcc = Math.max(perf.worstAcc, dt * 1000);
    if (perf.acc >= 0.5) {
      perf.fps = perf.frames / perf.acc;
      perf.frameMs = (perf.acc * 1000) / perf.frames;
      perf.worst = perf.worstAcc;
      perf.frames = 0;
      perf.acc = 0;
      perf.worstAcc = 0;
    }
    if (pilot) benchFrame(now, dt);
    perf.hudTimer += dt;
    if (perf.hudTimer >= 0.1) {
      perf.hudTimer = 0;
      hud();
    }
  });

  const streetEl = $('street'), speedEl = $('speed'), perfEl = $('perf'), noticeEl = $('notice');
  noticeEl.textContent = t('borderNotice');
  function hud(): void {
    const c = drive.car;
    const edge = drive.layers.edge;
    const street = edge?.name ? edge.name : t('unnamedRoad');
    const tag = c.layer > 0 ? ` · ${t('bridgeTag')}` : c.layer < 0 ? ` · ${t('tunnelTag')}` : '';
    const district = city.districtAt(c.x, c.y);
    streetEl.textContent = [street + tag, district].filter(Boolean).join('  ·  ');
    speedEl.textContent = city.imperial
      ? t('speedMph', { speed: Math.round(c.speed * 2.23694) })
      : t('speedKmh', { speed: Math.round(c.speed * 3.6) });
    const s = view.stats;
    perfEl.textContent =
      `${perf.fps.toFixed(0)} fps  ${perf.frameMs.toFixed(1)} ms  max ${perf.worst.toFixed(0)}\n` +
      `draw ${s.drawCalls}  tri ${(s.triangles / 1000).toFixed(0)}k\n` +
      `chunks ${s.chunks}  ${engine.isWebGPU ? 'WebGPU' : 'WebGL2'}  ${scheme.id.toUpperCase()}`;
    perfEl.style.color = perf.fps >= 57 ? tokens.colorUiFpsOk : tokens.colorUiFpsBad;
    const d = drive.borderDistance();
    noticeEl.hidden = !(d !== null && d < tuning.hud.borderNoticeM);
  }

  // ---------- benchmark (specs/bench.md)
  const bench = { start: 0, times: [] as number[], done: false };
  function benchFrame(now: number, dt: number): void {
    if (!pilot || bench.done) return;
    if (bench.start === 0) bench.start = now;
    if (now - bench.start >= tuning.bench.warmupS * 1000) bench.times.push(dt * 1000);
    if (!pilot.finished) {
      noticeEl.hidden = false;
      noticeEl.textContent = t('benchRunning', { percent: Math.floor((100 * pilot.s) / pilot.route.length) });
      return;
    }
    bench.done = true;
    const st = frameStats(bench.times);
    const mem = (performance as unknown as { memory?: { usedJSHeapSize: number } }).memory;
    const r: BenchResult = {
      client: 'web',
      route: 'midtown-42nd',
      device: navigator.userAgent,
      renderer: engine.isWebGPU ? 'WebGPU' : 'WebGL2',
      completed: true,
      duration_s: round((now - bench.start) / 1000, 1),
      frames: bench.times.length,
      fps_avg: round(st.fpsAvg, 1),
      fps_1low: round(st.fps1Low, 1),
      frame_ms_p50: round(st.p50, 2),
      frame_ms_p99: round(st.p99, 2),
      first_frame_ms: Math.round(firstFrameMs),
      ...(mem ? { memory_mb: round(mem.usedJSHeapSize / 1e6, 0) } : {}),
      respawns: pilot.respawns,
      date: new Date().toISOString(),
    };
    showBench(r);
  }
  const round = (v: number, d: number): number => Math.round(v * 10 ** d) / 10 ** d;
  function showBench(r: BenchResult): void {
    const text = JSON.stringify(r, null, 2);
    noticeEl.textContent = t('benchDone');
    $('bench-json').textContent = text;
    const copy = $('bench-copy');
    copy.textContent = t('copy');
    copy.onclick = () => void navigator.clipboard?.writeText(text).then(() => (copy.textContent = t('copied')));
    $('bench').hidden = false;
    console.info('[metro bench]', text);
  }

  // ---------- overlay: street labels and control hints (screen space)
  const labelFont = `700 ${tokens.fontLabel}px system-ui, sans-serif`;
  function drawOverlay(): void {
    ctx.clearRect(0, 0, size.w, size.h);
    const c = drive.car, h = tuning.hud, rig = view.rig;
    if (c.speed <= h.streetLabelsBelowMps) {
      const hits = city.graph
        .near(c.x, c.y, h.streetLabelRadiusM)
        .filter((x) => x.edge.kept && x.edge.name !== '' && x.edge.drawLayer === c.layer)
        .sort((a, b) => a.dist - b.dist);
      const shown = new Set<string>();
      ctx.font = labelFont;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = tokens.colorUiStreetLabel;
      ctx.shadowColor = tokens.colorUiLabelShadow;
      ctx.shadowBlur = 3;
      ctx.letterSpacing = '1.5px';
      for (const hit of hits) {
        if (shown.size >= h.streetLabelsMax || shown.has(hit.edge.name)) continue;
        shown.add(hit.edge.name);
        const p = rig.toScreen(hit.x, hit.y, size.w, size.h, tuning);
        let a = rig.screenAngle(Math.atan2(hit.dirY, hit.dirX));
        while (a > Math.PI / 2) a -= Math.PI;
        while (a < -Math.PI / 2) a += Math.PI;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(a);
        ctx.fillText(hit.edge.name.toUpperCase(), 0, 0);
        ctx.restore();
      }
      ctx.shadowBlur = 0;
    }
    drawPedBubbles(ctx, peds, rig, size, tuning, t('pedestrianBubble'));
    controlHints();
  }

  function controlHints(): void {
    const { w, h } = size;
    if (scheme instanceof SchemeA && scheme.active) {
      ctx.strokeStyle = ctx.fillStyle = tokens.colorUiControlHint;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(scheme.origin.x, scheme.origin.y, 34, 0, 2 * Math.PI);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(scheme.pos.x, scheme.pos.y, 18, 0, 2 * Math.PI);
      ctx.fill();
    } else if (scheme instanceof SchemeB) {
      ctx.fillStyle = tokens.colorUiControlHalf;
      if (scheme.leftHeld) ctx.fillRect(0, h * 0.6, w / 2, h * 0.4);
      if (scheme.rightHeld) ctx.fillRect(w / 2, h * 0.6, w / 2, h * 0.4);
    } else if (scheme instanceof SchemeC) {
      const ctr = SchemeC.wheelCentre(w, h), r = SchemeC.wheelRadius(w);
      ctx.strokeStyle = tokens.colorUiControlWheel;
      ctx.lineWidth = r * 0.16;
      ctx.beginPath();
      ctx.arc(ctr.x, ctr.y, r, 0, 2 * Math.PI);
      ctx.stroke();
      ctx.lineWidth = r * 0.1;
      ctx.lineCap = 'round';
      for (const a0 of [-Math.PI / 2, Math.PI / 2, Math.PI]) {
        const a = a0 + scheme.wheelAngle - Math.PI / 2;
        ctx.beginPath();
        ctx.moveTo(ctr.x, ctr.y);
        ctx.lineTo(ctr.x + Math.cos(a) * r, ctr.y + Math.sin(a) * r);
        ctx.stroke();
      }
      const rr = (s: { left: number; top: number; width: number; height: number }, col: string): void => {
        ctx.fillStyle = col;
        ctx.beginPath();
        ctx.roundRect(s.left, s.top, s.width, s.height, 10);
        ctx.fill();
      };
      rr(SchemeC.pedal(w, h), scheme.brakeHeld ? tokens.colorUiControlBrake : tokens.colorUiControlHint);
      rr(SchemeC.handButton(w, h), scheme.handHeld ? tokens.colorUiControlHand : tokens.colorUiControlHint);
    }
  }

  // WebGL context loss (DUALSTACK 6.3): Babylon restores GPU resources itself; keep the loop alive.
  engine.onContextLostObservable.add(() => console.warn('WebGL context lost'));
  engine.onContextRestoredObservable.add(() => console.warn('WebGL context restored'));

  if (import.meta.env.DEV || params.has('debug')) {
    (window as unknown as Record<string, unknown>)['metro'] = {
      engine, view, drive, city, tuning, frameTimes, pilot, bench, peds,
      timing: () => ({ firstFrameMs, loadMs }),
    };
  }
}

main().catch((e: unknown) => {
  const el = document.getElementById('loading');
  if (el) {
    el.hidden = false;
    el.textContent = tr(locale, 'loadFailed', { error: String(e) });
  }
  throw e;
});
