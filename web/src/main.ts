import { Engine } from '@babylonjs/core/Engines/engine';
import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { WebGPUEngine } from '@babylonjs/core/Engines/webgpuEngine';

import { ASSET_BASE_URL } from './config';
import { Autopilot, frameStats } from './drive/autopilot';
import { resolveRoute, routeFile } from './drive/route';
import { hillPanel } from './drive/hillPanel';
import { BoostHint, boostHintKey, readBoostHint, writeBoostHint } from './drive/boostHint';
import { applyKeys, createScheme, SchemeA, SchemeB, SchemeC, type ControlScheme, type ControlSchemeId } from './drive/controls';
import { DriveWorld } from './drive/driveWorld';
import { installFlowHud } from './drive/flowHud';
import { TERRAIN_SPEC } from './drive/slope';
import { t as tr, type Locale, type MessageKey } from './gen/i18n';
import { carIdValues, cityIdNames, cityIdValues, minigameCatalog, type CityId, type MinigameId } from './gen/ids';
import { CarFleet } from './cars/fleet';
import { CarsHud } from './cars/ui';
import { HopHud } from './cars/hopHud';
import type { BenchResult, BenchRoute, CarSpec, NpcPack } from './gen/schema';
import { tokens } from './gen/tokens';
import { carPose, PedestrianWorld } from './peds/pedestrians';
import { drawPedBubbles, PedView } from './render/pedView';
import { Tuning } from './gen/tuning';
import { TrafficView } from './render/trafficView';
import { TramView } from './render/tramView';
import { installPassport } from './passport/hud';
import { overlays, PauseGate } from './pause';
import { WorldView } from './render/worldView';
import { installPhone } from './phone';
import { installPolice } from './police';
import { installBooths } from './booths';
import { installPhoto } from './photo';
import { installShops } from './shops';
import { installWeather } from './weather';
import { installGarage } from './garage';
import { installLoop } from './loop';
import { opponentIndex } from './loop/logic';
import { loadArt } from './art';
import { installTaxi } from './minigames/taxi';
import { installDrift } from './minigames/drift';
import { installSprint } from './minigames/sprint';
import { installTravel } from './travel';
import { installFastTravel } from './travel/fastTravel';
import { cityUrl, pickStartCity, readLastCity, switchCity, writeLastCity } from './travel/cities';
import { chunkPath, HttpPackSource } from './world/citypack';
import { LoadProgress, ProgressSource } from './firstrun/progress';
import { introStore, rememberIntro, shouldShowIntro, showIntro } from './firstrun/intro';
import './firstrun/intro.css';
import { City } from './world/model';
import { ChunkStreamer } from './world/streaming';
import { MapNatureSource } from './phone/mapNature';
import { drawNatureLabels } from './render/natureLabels';
import { treeHitSound } from './render/treeSound';
import { readCameraMode, TwoFingerTap, writeCameraMode, type CameraMode } from './render/chase';
import { registerPhoneApp } from './phone';
import { h } from './minigames/dom';
import { AppIconChoice, appIconLinks, appIconSection } from './appicon';
import './appicon/appicon.css';

const params = new URLSearchParams(location.search);
const locale: Locale = navigator.language.startsWith('cs') ? 'cs' : 'en';
const t = (k: MessageKey, a?: Record<string, string | number>): string => tr(locale, k, a);
const $ = <T extends HTMLElement>(id: string): T => document.getElementById(id) as T;

// App icon (specs/appicon.md): the tab icon follows the remembered mode before anything loads; ?icon= for debug.
const appIcon = new AppIconChoice(params.get('icon'), appIconLinks(document));

// Start city (specs/cities.md "Výchozí město"): ?city → last city → first bundled city.
const lastCity = readLastCity();
const cityId: CityId = pickStartCity(params.get('city'), lastCity, cityIdValues);
/** Where the error screen links back to while the pack is loading (null once it loaded). */
let backCity: CityId | null = lastCity !== null && lastCity !== cityId ? lastCity : null;

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
  // Generated art index (specs/art.md): fetched once; missing = placeholders everywhere.
  const artReady = loadArt();
  // ?gallery / ?mg=<id>: minigames without the world (specs/minigames/README.md "Galerie").
  // ?skits: NPC dialogue debug list (specs/dialogue.md); the gallery also gets NPC opponents.
  // ?mg=<id> of a world minigame (engine drive, Taxi) opens the world at its spot and starts it there.
  const worldMg = minigameCatalog[params.get('mg') as MinigameId]?.engine === 'drive' ? params.get('mg') : null;
  if (params.has('gallery') || (params.has('mg') && !worldMg) || params.has('skits')) {
    const [{ runGallery }, { runSkits }, { DialogueSession, setDialogueSession }, tuning, npcPack] = await Promise.all([
      import('./minigames/gallery'),
      import('./dialogue/skits'),
      import('./dialogue/session'),
      json<unknown>('content/tuning.json').then((j) => Tuning.fromJson(j)),
      json<NpcPack>('content/npc.json'),
      artReady,
    ]);
    const npc = new DialogueSession(npcPack, tuning.npc, cityId, (Math.random() * 0xffffffff) >>> 0);
    setDialogueSession(npc);
    for (const id of ['world', 'overlay', 'hud', 'loading']) $(id).hidden = true;
    const host = document.createElement('div');
    host.id = 'minigames';
    document.body.append(host);
    if (params.has('skits')) runSkits(host, { locale, t }, npc, params.get('skits'));
    else runGallery(host, { tuning, locale, t }, params, npc, cityId);
    return;
  }
  // ?cars: debug contact sheet of every car shape (specs/cars.md "Kreslení"), without the world.
  if (params.has('cars')) {
    const [{ runCarSheet }, tuning, cars] = await Promise.all([
      import('./cars/sheet'),
      json<unknown>('content/tuning.json').then((j) => Tuning.fromJson(j)),
      Promise.all(carIdValues.map(async (id) => [id, await json<CarSpec>(`content/cars/${id}.json`)] as const)).then((e) => new Map<string, CarSpec>(e)),
      artReady,
    ]);
    for (const id of ['world', 'overlay', 'hud', 'loading']) $(id).hidden = true;
    const host = document.createElement('div');
    document.body.append(host);
    runCarSheet(host, cars, tuning, t);
    return;
  }
  $('loading').textContent = t('loading', { city: cityIdNames[cityId] });
  $('about').textContent = t('aboutMaps');
  const tStart = performance.now();

  const [tuning, cars, source] = await Promise.all([
    json<unknown>('content/tuning.json').then((j) => Tuning.fromJson(j)),
    Promise.all(carIdValues.map(async (id) => [id, await json<CarSpec>(`content/cars/${id}.json`)] as const)).then((e) => new Map<string, CarSpec>(e)),
    HttpPackSource.open(ASSET_BASE_URL, cityId),
    artReady,
  ]);
  // Download progress in % until the first frame (specs/firstrun.md).
  const progress = new LoadProgress((pct) => {
    $('loading').textContent = t('loadingProgress', { city: cityIdNames[cityId], pct });
  });
  const loadSource = new ProgressSource(source.root, progress);
  const city = await City.load(loadSource);
  // ?flat (debug, A/B): drive and draw the pack without its heights (specs/terrain.md flat pack).
  if (params.has('flat')) city.terrain.enabled = false;
  // The pack loaded: remember the city now, not only when leaving it (specs/cities.md).
  writeLastCity(cityId);
  backCity = null;
  const engine = await createEngine();
  const drive = new DriveWorld(city, cars.get(tuning.cars.startCar)!, tuning);
  // Cars, switching and the garage (specs/cars.md).
  const garageSpot = city.spots.items.find((s) => s.kind === 'garage');
  const fleet = new CarFleet(drive, cars, tuning, garageSpot
    ? { id: garageSpot.id, x: garageSpot.parkX / 10, y: garageSpot.parkY / 10, heading: garageSpot.parkHeading }
    : null);
  // Passport (specs/passport.md); ?passport / ?about open its screens.
  const passport = installPassport(city, tuning.passport, { t }, { root: $('hud'), about: $('about') });
  if (params.has('passport')) passport.openPassport();
  if (params.has('about')) passport.openAbout();

  if (worldMg) {
    const s = city.spots.items.find((x) => x.minigame === worldMg);
    if (s) {
      params.set('spot', s.id);
      params.set('play', s.id);
    }
  }
  // ?spot=<id> puts the player on a spot (DUALSTACK 6.6).
  const spot = city.spots.items.find((s) => s.id === params.get('spot'));
  if (spot) drive.spawn(spot.parkX / 10, spot.parkY / 10, spot.parkHeading);

  const view = new WorldView(engine, city, tuning, drive);
  view.setPackSource(source);
  // Camera mode (specs/terrain.md "Upřesnění T2"): ?camera=, else the remembered choice, else top-down.
  view.setCameraMode(readCameraMode(params.get('camera')));
  const peds = new PedestrianWorld(city, tuning);
  const pedView = new PedView(view.scene);
  const trafficView = drive.traffic ? new TrafficView(view.scene, drive.traffic, tuning) : null;
  // Trams (specs/trams.md): drive.trams exposes items, onHit and stops for police and dialogue.
  const tramView = drive.trams ? new TramView(view.scene, drive.trams, tuning) : null;
  // Heights (specs/terrain.md): trams and pedestrians stand on the terrain or their bridge.
  if (tramView) tramView.terrain = city.terrain;
  pedView.terrain = city.terrain;
  // Police and wanted level (specs/police.md).
  const police = installPolice({ drive, cars: fleet, tuning, t, hud: $('hud'), scene: view.scene });
  // Vehicle ground shadows in the city skin's colour by day (specs/style.md).
  const applyShadows = (): void => {
    trafficView?.setShadow(view.palette.shadow);
    tramView?.setShadow(view.palette.shadow);
    police.setShadow(view.palette.shadow);
  };
  applyShadows();
  const streamer = new ChunkStreamer(city, loadSource, tuning, (c) => {
    drive.addChunk(c);
    fleet.addChunk(c);
    police.addChunk(c);
    view.addChunk(c);
  }, (c) => {
    fleet.removeChunk(c);
    police.removeChunk(c);
    drive.removeChunk(c);
    view.removeChunk(c);
  });
  // ?bench: the autopilot drives the route of specs/bench.md and reports the numbers.
  // A city without content/bench/<cityId>.json has no benchmark (specs/cities.md).
  // ?route=<id> (bench v2): the route content/bench/<cityId>-<id>.json; the player starts on it with
  // the navigation along it, with ?bench the autopilot drives it.
  const routeId = params.get('route');
  const benchRoute = params.has('bench') || routeId !== null
    ? await json<BenchRoute>(`content/bench/${routeFile(cityId, routeId)}`).catch((e: unknown) => {
      console.warn(`no route ${routeId ?? 'benchmark'} for ${cityId}`, e);
      return null;
    })
    : null;
  const routePath = benchRoute ? resolveRoute(city.graph, benchRoute) : null;
  const pilot = routePath && params.has('bench') ? new Autopilot(routePath, tuning) : null;
  if (pilot) {
    pilot.start(drive);
    view.carChanged();
    drive.beforeStep = (step) => pilot.step(drive, drive.input, step);
  } else if (routePath) {
    const p = routePath.at(0);
    drive.spawn(p.x, p.y, p.dir);
    view.carChanged();
  }
  view.setFleet(fleet);
  // Car sprites (specs/art.md v2): one atlas set for the player, parked cars, traffic and patrols.
  if (view.sprites) {
    trafficView?.setSprites(view.sprites);
    police.setSprites(view.sprites);
  }
  view.rig.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
  // Own chunk and its ring first (3×3 = 9); the rest streams in while driving. Their sizes join the
  // download total from the manifest right away (specs/firstrun.md).
  const sizes = new Map(city.manifest.chunks.map((c) => [chunkPath(c.x, c.y), c.bytes]));
  for (const [cx, cy] of streamer.window.wanted(drive.car.x, drive.car.y, drive.car.heading).slice(0, 9)) {
    const p = chunkPath(cx, cy);
    progress.announce(p, sizes.get(p) ?? 0);
  }
  await streamer.preload(drive.car.x, drive.car.y, drive.car.heading, 9);
  progress.stop();
  $('loading').hidden = true;
  let firstFrameMs = 0;
  // In-game phone, feed, map and GPS navigation (specs/phone.md).
  const phone = installPhone({ city, drive, tuning, t, rig: view.rig, parent: document.body, buttons: $('buttons'), params,
    mapNature: city.manifest.natureVersion > 0 ? new MapNatureSource(city, source) : null,
    discovered: () => new Set(passport.tracker.stamps.filter((s) => s.startsWith('landmark:')).map((s) => s.slice(9))) });
  const loadMs = performance.now() - tStart;
  // ?route=: navigation along the route to its last crossing (specs/bench.md v2).
  if (routeId !== null && routePath && benchRoute && routePath.edges.length > 0) {
    const end = routePath.at(routePath.length), last = benchRoute.legs[benchRoute.legs.length - 1]!.to;
    phone.followRoute({ id: `route:${benchRoute.id}`, name: last.b, edge: routePath.edges[routePath.edges.length - 1]!,
      parkX: Math.round(end.x * 10), parkY: Math.round(end.y * 10) }, routePath.pts);
  }

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
    if (drive.traffic) drive.traffic.night = night;
    tramView?.setNight(night);
    applyShadows();
  });
  $('btn-respawn').title = t('respawn');
  $('btn-respawn').addEventListener('click', () => {
    drive.spawn(city.startX, city.startY, city.startHeading);
    police.police.clearRoadblock();
    view.carChanged();
    view.rig.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
  });

  // Camera switch (specs/terrain.md "Upřesnění T2"): HUD button, two-finger double tap, Settings app.
  const cameraBtn = $('btn-camera');
  const cameraLabel = (): void => {
    const chase = view.cameraMode === 'chase';
    cameraBtn.textContent = chase ? '◢' : '◎';
    cameraBtn.title = t(chase ? 'cameraTopdown' : 'cameraChase');
  };
  const setCamera = (m: CameraMode): void => {
    view.setCameraMode(m);
    writeCameraMode(m);
    cameraLabel();
  };
  const toggleCamera = (): void => setCamera(view.cameraMode === 'chase' ? 'topdown' : 'chase');
  cameraLabel();
  cameraBtn.addEventListener('click', toggleCamera);
  registerPhoneApp('settings', (host) => {
    const modes = ['topdown', 'chase'] as const;
    const label = (m: CameraMode): string => `${view.cameraMode === m ? '✓ ' : ''}${t(m === 'chase' ? 'cameraChase' : 'cameraTopdown')}`;
    const names = modes.map((m) => h('span.travel-name', {}, label(m)));
    const rows = modes.map((m, i) => h('button.travel-row', { type: 'button', onclick: () => {
      setCamera(m);
      modes.forEach((k, j) => (names[j]!.textContent = label(k)));
    } }, names[i]!));
    // App icon mode under the camera rows (specs/appicon.md "Výběr ve hře").
    host.append(h('div.taxi-app', {}, ...rows), appIconSection(appIcon, t));
    return () => {};
  });

  const size = { w: 1, h: 1 };
  const pt = (e: PointerEvent): { x: number; y: number } => ({ x: e.clientX, y: e.clientY });
  const taps = new TwoFingerTap();
  canvas.addEventListener('pointerdown', (e) => {
    canvas.setPointerCapture(e.pointerId);
    scheme.down(e.pointerId, pt(e), size.w, size.h);
    if (e.pointerType === 'touch') taps.pointerDown(e.pointerId, e.clientX, e.clientY, e.timeStamp / 1000);
  });
  canvas.addEventListener('pointermove', (e) => {
    scheme.move(e.pointerId, pt(e), size.w, size.h);
    taps.pointerMove(e.pointerId, e.clientX, e.clientY);
  });
  const up = (e: PointerEvent): void => {
    scheme.up(e.pointerId);
    if (taps.pointerUp(e.pointerId, e.timeStamp / 1000)) toggleCamera();
  };
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', (e) => {
    scheme.up(e.pointerId);
    taps.cancel(e.pointerId);
  });
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

  // Car name, "Přesednout" / garage button and the garage list (specs/cars.md).
  const carsHud = new CarsHud(fleet, t, $('hud'), () => view.carChanged());
  carsHud.toast = (text) => phone.toast(text);
  // "Skok" over traffic (specs/hop.md): HUD button and key J.
  const hopHud = new HopHud(drive, t, $('hud'), tuning.nav.toastS);
  window.addEventListener('keydown', (e) => {
    if (e.code === 'KeyJ' && !e.repeat && !pilot) hopHud.press();
  });

  // Loop glue: arrival → minigame → result → cash, stamp, save (specs/loop.md); loads the save.
  const npcPack = await json<NpcPack>('content/npc.json').catch(() => null);
  // Feed cards of a spot are hosted by its NPC (the spot's opponent, specs/loop.md); the bust
  // replaces the silhouette when it exists (specs/art.md).
  const hosts = npcPack?.characters ?? [];
  phone.feedHost = (spot) => hosts[opponentIndex(spot, hosts.length)]?.id ?? null;
  const loop = await installLoop({
    city, tuning, locale, t, drive, fleet, passport, phone, params, hud: $('hud'), buttons: $('buttons'),
    npcPack,
    onCarChanged: () => view.carChanged(),
    settings: {
      get: () => ({ scheme: scheme.id, night }),
      set: (st) => {
        scheme = createScheme(st.scheme, tuning.controls);
        schemeLabel();
        night = st.night;
        view.setNight(night);
        if (drive.traffic) drive.traffic.night = night;
        tramView?.setNight(night);
        applyShadows();
      },
    },
  });
  // No test drive during a world minigame (specs/testdrive.md "Pořadí").
  carsHud.blockTest = () => loop.inWorldGame;
  // Taxi: a world minigame started by the loop at the taxi stand (specs/minigames/taxi.md).
  const taxi = installTaxi({ city, tuning, t, drive, fleet, phone, rig: view.rig, cars, hud: $('hud'), onCarChanged: () => view.carChanged() });
  loop.worldGames.taxi = taxi;
  // Drift zone and Sprint A→B: world minigames in the player's own car (specs/minigames/drift.md, sprint.md).
  const drift = installDrift({ city, tuning, t, drive, fleet, rig: view.rig, hud: $('hud') });
  loop.worldGames.drift = drift;
  const sprint = installSprint({ city, tuning, t, drive, fleet, phone, rig: view.rig, hud: $('hud'), onCarChanged: () => view.carChanged() });
  loop.worldGames.sprint = sprint;
  // Travel app: switch cities from the phone (specs/cities.md).
  // Ringing phone booths (specs/booths.md): offer a minigame with a cash bonus.
  const booths = installBooths({
    city, tuning, t, drive, phone, loop, carsHud, npcPack, hud: $('hud'), rig: view.rig, wanted: () => police.police.wantedLevel,
  });
  // Photo spots and the Camera (specs/photo.md): after the booths, whose "Zvednout" goes first.
  const photo = installPhoto({
    city, tuning, t, drive, phone, loop, carsHud, tracker: passport.tracker, hud: $('hud'), rig: view.rig,
    wanted: () => police.police.wantedLevel, size: () => size,
  });
  // Shops and bars (specs/shops.md): after the photo, whose "Foťák" goes first.
  const shops = installShops({
    city, tuning, locale, t, drive, fleet, phone, loop, carsHud, npcPack, hud: $('hud'), rig: view.rig,
  });
  // Tuning and looks (specs/garage.md): after the shops (the shelf tab); rebuilds the car from its upgrades.
  const garage = installGarage({ tuning, t, fleet, carsHud, loop, view, shops, phone });
  // Weather (specs/weather.md): random seed per start, starts clear; ?weather= sets a kind.
  const weather = installWeather({ cityId, tuning, t, drive, view, hud: $('hud'), params });
  installTravel({ cityId, tuning, t, phone, tracker: passport.tracker, store: loop.store, save: () => loop.save(), onSwitch: () => booths.clear() });
  // First run intro card (specs/firstrun.md): controls and the city choice, once per device.
  const store = introStore();
  if (shouldShowIntro(params, store)) {
    const release = overlays.open('intro');
    showIntro({
      parent: document.body, t, cities: cityIdValues, names: cityIdNames, current: cityId,
      onClose: (target) => {
        rememberIntro(store);
        release();
        if (target) void switchCity(target, { save: () => loop.save(), navigate: (url) => location.assign(url), href: location.href });
      },
    });
  }
  // Boost hint (specs/controls.md v2): a toast for the active scheme until the player boosts.
  const boostHint = new BoostHint(tuning.controls, readBoostHint(store));
  const finePointer = ((): boolean => {
    try {
      return window.matchMedia('(pointer: fine)').matches;
    } catch {
      return false;
    }
  })();
  // Fast travel by metro and taxi (specs/travel.md): stations unlock by passing, the move resets
  // traffic, patrols and pedestrians like a teleport.
  const fastTravel = installFastTravel({
    city, tuning, t, drive, fleet, phone, loop, wanted: () => police.police.wantedLevel, police: police.police, peds, hud: $('hud'), rig: view.rig,
    onMoved: () => {
      view.carChanged();
      view.rig.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
    },
  });
  // Wall slide, trail, rescue and "Na silnici" (specs/flow.md, F-069).
  const flow = installFlowHud({
    drive, tuning, t, cityId, hud: $('hud'), buttons: $('buttons'), phone: phone.phone, route: () => phone.nav.ahead(),
    debug: import.meta.env.DEV || params.has('debug'),
    onMoved: () => view.rig.snap(drive.car.x, drive.car.y, drive.car.heading, tuning),
  });
  // Water fall (specs/nature.md "Voda"): the sunk car is towed to the nearest road for a fee; a
  // world minigame or taxi shift in progress ends as cancelled.
  drive.onSunk = () => {
    for (const g of [taxi, drift, sprint]) g.quit();
    const paid = loop.book.tow();
    void loop.save();
    phone.toast(t('natureTow', { fee: paid.amount }));
    view.carChanged();
    view.rig.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
  };
  view.nature.onHit = (size) => treeHitSound(size);
  // Police fines take cash through the economy (specs/economy.md).
  police.police.onFined((e) => loop.fine(e.amount));

  // ---------- loop
  const perf = { frames: 0, acc: 0, fps: 0, frameMs: 0, worst: 0, worstAcc: 0, hudTimer: 0 };
  const frameTimes: number[] = [];
  // Pause under overlays (specs/pause.md): the world steps with 0 while one is open.
  const gate = new PauseGate(overlays);
  let last = performance.now();
  engine.runRenderLoop(() => {
    const now = performance.now();
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    if (loop.busy) return; // minigame up: the world neither steps nor renders (DUALSTACK 6.5)
    if (firstFrameMs === 0) firstFrameMs = now;
    // Paused: no step, no game clock, input dropped; on resume the controls start from zero.
    const stepDt = gate.frame(dt, pilot ? null : drive.input, () => {
      scheme = createScheme(scheme.id, tuning.controls);
      keys.clear();
    });
    if (!pilot && !gate.paused) {
      const input = drive.input;
      input.reset();
      scheme.update(input);
      applyKeys(keys, input);
      // Too many beers (specs/shops.md "Piva"): input ignored, the car brakes to a stop.
      shops.brake();
      // Sprint countdown: the car stands on the start line.
      sprint.brake();
    }
    // Ticks with the game clock; the grip multiplier goes into this frame's drive step.
    weather.update(stepDt, dt);
    drive.update(stepDt);
    if (!pilot) {
      const ev = boostHint.step(stepDt, drive.car.speed, drive.input.boost);
      if (ev) writeBoostHint(store, boostHint.shown);
      if (ev === 'show') phone.toast(t(boostHintKey(scheme.id, finePointer)));
    }
    // Test drive countdown in game time (specs/testdrive.md "Odpočet").
    carsHud.tick(stepDt);
    police.update(stepDt, dt);
    phone.update(dt);
    taxi.update(stepDt);
    drift.update(stepDt);
    sprint.update(stepDt);
    booths.update(stepDt, dt);
    shops.update(stepDt, dt);
    const c = drive.car;
    // The Camera glides the rig to its framing view and back (specs/photo.md); otherwise it follows.
    const framing = photo.camera(dt);
    // The framing view is a map from above: the chase camera waits until it ends.
    view.chaseSuspended = framing;
    if (!framing) view.rig.follow(c.x, c.y, c.heading, c.speed, dt, tuning, c.forwardSpeed < -0.5);
    streamer.update(c.x, c.y, c.heading, now);
    peds.update(stepDt, [carPose(c)], view.rig.visibleRadius(size.w, size.h, tuning), night);
    pedView.update(peds);
    trafficView?.update(view.rig.x, view.rig.y, view.rig.visibleRadius(size.w, size.h, tuning), c.layer);
    tramView?.update(c.layer);
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

  const streetEl = $('street'), speedEl = $('speed'), perfEl = $('perf'), noticeEl = $('notice'), terrainEl = $('terrain');
  noticeEl.textContent = t('borderNotice');
  function hud(): void {
    booths.hud();
    photo.hud(0.1);
    shops.hud();
    fastTravel.hud(0.1);
    fleet.update();
    carsHud.update();
    hopHud.update(0.1);
    if (!pilot) flow.update();
    const c = drive.car;
    const edge = drive.layers.edge;
    const street = edge?.name ? edge.name : t('unnamedRoad');
    const tag = c.layer > 0 ? ` · ${t('bridgeTag')}` : c.layer < 0 ? ` · ${t('tunnelTag')}` : '';
    // Inside a named park the park replaces the district (specs/nature.md "Vykreslení shora").
    const park = c.layer === 0 ? drive.nature.parkAt(c.x, c.y) : '';
    const district = park || city.districtAt(c.x, c.y);
    streetEl.textContent = [street + tag, district].filter(Boolean).join('  ·  ');
    speedEl.textContent = city.imperial
      ? t('speedMph', { speed: Math.round(c.speed * 2.23694) })
      : t('speedKmh', { speed: Math.round(c.speed * 3.6) });
    terrainHud();
    const s = view.stats;
    // Stuck count of the last 10 minutes of driving (specs/flow.md "Měření zaseknutí").
    const stuck = flow.stuckLine();
    perfEl.textContent =
      `${perf.fps.toFixed(0)} fps  ${perf.frameMs.toFixed(1)} ms  max ${perf.worst.toFixed(0)}\n` +
      `draw ${s.drawCalls}  tri ${(s.triangles / 1000).toFixed(0)}k\n` +
      `chunks ${s.chunks}  cars ${drive.traffic?.cars.length ?? 0}  trams ${drive.trams?.trams.length ?? 0}  ${engine.isWebGPU ? 'WebGPU' : 'WebGL2'}  ${scheme.id.toUpperCase()}\n` +
      stuck.text;
    perfEl.style.color = perf.fps >= 57 && !stuck.over ? tokens.colorUiFpsOk : tokens.colorUiFpsBad;
    const d = drive.borderDistance();
    noticeEl.hidden = !(d !== null && d < tuning.hud.borderNoticeM);
    if (!pilot) passport.update(c.x, c.y);
    loop.update(0.1);
  }

  /**
   * Relief HUD (specs/terrain.md "Nápovědy reliéfu shora"): the grade along the direction of
   * travel in % (rounded, only above 2 %) and the approximate elevation z0 + z / exaggeration.
   */
  function terrainHud(): void {
    const ter = city.terrain;
    terrainEl.hidden = !ter.enabled;
    if (!ter.enabled) return;
    const c = drive.car, v = c.body.getLinearVelocity();
    const sp = Math.hypot(v.x, v.y);
    const dx = sp > 0.5 ? v.x / sp : Math.cos(c.heading), dy = sp > 0.5 ? v.y / sp : Math.sin(c.heading);
    const grade = drive.grad.x * dx + drive.grad.y * dy;
    const parts: string[] = [];
    if (Math.abs(grade) > TERRAIN_SPEC.hudMinGrade) parts.push(t('terrainGrade', { pct: Math.round(grade * 100) }));
    parts.push(t('terrainAltitude', { m: Math.round(ter.altitude(drive.jump.z - drive.jump.gap)) }));
    terrainEl.textContent = parts.join('  ·  ');
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
    overlays.open('bench');
    console.info('[metro bench]', text);
  }

  // ---------- overlay: street labels and control hints (screen space)
  const labelFont = `700 ${tokens.fontLabel}px system-ui, sans-serif`;
  function drawOverlay(): void {
    ctx.clearRect(0, 0, size.w, size.h);
    const c = drive.car, h = tuning.hud, rig = view.rig;
    drawNatureLabels(ctx, drive.nature, rig, size, tuning);
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
    booths.draw(ctx, size.w, size.h);
    shops.draw(ctx, size.w, size.h);
    fastTravel.draw(ctx, size.w, size.h);
    phone.draw(ctx, size.w, size.h);
    taxi.draw(ctx, size.w, size.h);
    drift.draw(ctx, size.w, size.h);
    sprint.draw(ctx, size.w, size.h);
    drawPedBubbles(ctx, peds, rig, size, tuning, t('pedestrianBubble'));
    // Camera icons, crosshair, frame and flash above the world labels (specs/photo.md).
    photo.draw(ctx, size.w, size.h);
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
      boostButton(SchemeB.boostButton(w, h), scheme.boostHeld);
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
      boostButton(SchemeC.boostButton(w, h), scheme.boostHeld);
    }
  }

  /** The Boost button of schemes B and C (specs/controls.md v2): a rounded pad with its label. */
  function boostButton(s: { left: number; top: number; width: number; height: number }, held: boolean): void {
    ctx.fillStyle = held ? tokens.colorUiControlBoost : tokens.colorUiControlHint;
    ctx.beginPath();
    ctx.roundRect(s.left, s.top, s.width, s.height, 10);
    ctx.fill();
    ctx.fillStyle = tokens.colorUiText;
    ctx.font = `600 ${Math.round(Math.min(s.width * 0.22, 18))}px system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(t('boostButton'), s.left + s.width / 2, s.top + s.height / 2);
  }

  // WebGL context loss (DUALSTACK 6.3): Babylon restores GPU resources itself; keep the loop alive.
  engine.onContextLostObservable.add(() => console.warn('WebGL context lost'));
  engine.onContextRestoredObservable.add(() => console.warn('WebGL context restored'));

  if (params.has('debug')) {
    // Hill tuning (specs/bench.md v2 "Ladění kopců"): live sliders over the client-side keys.
    const hp = hillPanel(tuning, { title: t('debugPanel'), copy: t('copyYaml'), copied: t('copied') });
    $('buttons').append(hp.button);
    document.body.append(hp.panel);
  }
  if (import.meta.env.DEV || params.has('debug')) {
    (window as unknown as Record<string, unknown>)['metro'] = {
      engine, view, drive, fleet, city, tuning, frameTimes, pilot, bench, peds, phone, passport, loop, taxi, drift, sprint, police: police.police, booths, fastTravel, photo, shops, weather, garage, carsHud, flow,
      timing: () => ({ firstFrameMs, loadMs }),
      setCamera,
      appIcon,
      /** Debug teleport: puts the car at (x, y) heading h (radians) and snaps the camera. */
      teleport: async (x: number, y: number, h = 0) => {
        drive.spawn(x, y, h);
        view.carChanged();
        view.rig.snap(x, y, h, tuning);
        await streamer.preload(x, y, h, 9);
      },
    };
  }
}

main().catch((e: unknown) => {
  const el = document.getElementById('loading');
  if (el) {
    el.hidden = false;
    el.textContent = tr(locale, 'loadFailed', { error: String(e) });
    // The city pack failed (e.g. offline): offer the previous city (specs/cities.md "Edge cases").
    if (backCity !== null) {
      const a = document.createElement('a');
      a.href = cityUrl(location.href, backCity);
      a.textContent = `${tr(locale, 'back')} · ${cityIdNames[backCity]}`;
      a.style.pointerEvents = 'auto';
      el.append(document.createElement('br'), a);
    }
  }
  throw e;
});
