import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { TargetCamera } from '@babylonjs/core/Cameras/targetCamera';
import { Material } from '@babylonjs/core/Materials/material';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import type { Texture } from '@babylonjs/core/Materials/Textures/texture';
import { Color3, Color4 } from '@babylonjs/core/Maths/math.color';
import { Matrix, Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import { SceneInstrumentation } from '@babylonjs/core/Instrumentation/sceneInstrumentation';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexBuffer } from '@babylonjs/core/Buffers/buffer';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import { TransformNode } from '@babylonjs/core/Meshes/transformNode';
import { Scene } from '@babylonjs/core/scene';
import '@babylonjs/core/Meshes/thinInstanceMesh';

import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { Car } from '../drive/car';
import type { DriveWorld } from '../drive/driveWorld';
import { propKinds, type PropKind } from '../drive/props';
import type { ChunkData } from '../world/chunk';
import { chunkKey, type City } from '../world/model';
import { cameraHeight, displayHeight, extrusionScale, fovX } from '../world/camera';
import { bollardPoints, bollardTris, buildRoads, buildingTris, groundTris, Tris, Z, type RoadChunk } from './geometry';
import { dayPalette, nightPalette, rgba, type Palette, type Rgba } from './palette';
import { facadeTexture } from './textures';
import { carShadowTris, carTris, carUndersideTris, parkedTris } from '../cars/carTris';
import { hopArc, hopFlip } from '../drive/hop';
import type { CarFleet } from '../cars/fleet';

/** Rotating follow camera state (port of world_engine camera.dart). */
export class CameraRig {
  x = 0;
  y = 0;
  /** World heading that points up on screen (radians, 0 = east, CCW). */
  heading = Math.PI / 2;
  viewWidth = 1;

  snap(px: number, py: number, h: number, t: Tuning): void {
    this.x = px;
    this.y = py;
    this.heading = h;
    this.viewWidth = t.viewWidthM.slow;
  }

  /** Heading and zoom are smoothed so drifts do not whip the map around. */
  follow(px: number, py: number, carHeading: number, speed: number, dt: number, t: Tuning, reversing: boolean): void {
    this.x = px;
    this.y = py;
    if (!reversing) {
      const d = wrap(carHeading - this.heading);
      this.heading = wrap(this.heading + d * (1 - Math.exp(-dt * t.camera.headingFollowRate)));
    }
    const k = Math.min(1, Math.max(0, speed / Math.max(t.speedMps.topDefault, 1)));
    const target = t.viewWidthM.slow + (t.viewWidthM.fast - t.viewWidthM.slow) * k;
    this.viewWidth += (target - this.viewWidth) * (1 - Math.exp(-dt * t.camera.zoomFollowRate));
  }

  /** World point → CSS pixels; the ground plane is what fovX frames (DUALSTACK 6.2). */
  toScreen(wx: number, wy: number, w: number, h: number, t: Tuning): { x: number; y: number } {
    const ppm = w / this.viewWidth;
    const a = Math.PI / 2 - this.heading;
    const dx = wx - this.x, dy = wy - this.y;
    const rx = dx * Math.cos(a) - dy * Math.sin(a);
    const ry = dx * Math.sin(a) + dy * Math.cos(a);
    return { x: w * t.carAnchor.x + rx * ppm, y: h * t.carAnchor.y - ry * ppm };
  }

  /** Screen angle (radians, clockwise from screen-right) of a world direction. */
  screenAngle(worldAngle: number): number {
    return -(worldAngle - this.heading + Math.PI / 2);
  }

  /** Radius around the car (metres) that covers the whole screen. */
  visibleRadius(w: number, h: number, t: Tuning): number {
    const vw = this.viewWidth, vh = (this.viewWidth * h) / w;
    const dx = Math.max(t.carAnchor.x, 1 - t.carAnchor.x) * vw;
    const dy = Math.max(t.carAnchor.y, 1 - t.carAnchor.y) * vh;
    return Math.sqrt(dx * dx + dy * dy);
  }
}

function wrap(a: number): number {
  while (a > Math.PI) a -= 2 * Math.PI;
  while (a < -Math.PI) a += 2 * Math.PI;
  return a;
}

/** Per-frame numbers for the FPS overlay. */
export interface RenderStats {
  chunks: number;
  drawCalls: number;
  triangles: number;
}

interface ChunkMeshes {
  flat: Mesh | null;
  buildings: Mesh | null;
}

interface ChunkEntry {
  data: ChunkData;
  meshes: ChunkMeshes;
  /** Bollard positions (x, y interleaved), fixed for the chunk's lifetime. */
  bollards: Float32Array;
}

interface RoadMeshes {
  ground: Mesh | null;
  bridge: Mesh | null;
  tunnel: Mesh | null;
}

/**
 * The 3D world of client W: same image as client F's 2.5D renderer (DUALSTACK 6.2). Geometry is
 * merged per chunk and material, world matrices frozen, props as thin instances (6.3).
 */
export class WorldView {
  readonly scene: Scene;
  readonly camera: TargetCamera;
  readonly rig = new CameraRig();
  palette: Palette = dayPalette;
  readonly stats: RenderStats = { chunks: 0, drawCalls: 0, triangles: 0 };

  private readonly H: number;
  private readonly flatMat: StandardMaterial;
  private readonly buildingMat: StandardMaterial;
  private readonly textures: { day: Texture; night: Texture };
  private readonly chunks = new Map<number, ChunkEntry>();
  private roadGeo: Map<number, RoadChunk>;
  private readonly roads = new Map<number, RoadMeshes>();
  private readonly tunnelShade: Mesh;
  private readonly carRoot: TransformNode;
  private carParts!: {
    wheels: TransformNode[]; brake: Mesh; reverse: Mesh; cone: Mesh; root: TransformNode; lights: boolean;
    /** Hop (specs/hop.md): the lifted, flipped body; its top and underside; the ground shadow. */
    lift: TransformNode; top: TransformNode; under: Mesh; shadow: TransformNode;
  };
  private readonly propMeshes = new Map<PropKind, Mesh>();
  private readonly lampGlow: Mesh;
  private propsVersion = -1;
  /** All bollards of the loaded chunks as thin instances; rebuilt only when chunks change. */
  private bollardMesh: Mesh;
  private bollardsDirty = true;
  private readonly bollardH: number;
  private readonly skidMesh: Mesh;
  private readonly skidPos: Float32Array;
  private skidsVersion = -1;
  private readonly proj = Matrix.Identity();
  private readonly projArr = new Float32Array(16);
  private inTunnel = false;
  private readonly instr: SceneInstrumentation;
  /** Parked cars (specs/cars.md), one merged mesh rebuilt when the fleet's version changes. */
  private fleet: CarFleet | null = null;
  private parkedMesh: Mesh | null = null;
  private parkedVersion = -1;

  constructor(
    readonly engine: AbstractEngine,
    readonly city: City,
    readonly tuning: Tuning,
    readonly drive: DriveWorld,
  ) {
    const scene = (this.scene = new Scene(engine));
    scene.skipPointerMovePicking = true;
    scene.autoClear = true;
    this.H = cameraHeight(tuning);

    const cam = (this.camera = new TargetCamera('camera', new Vector3(0, this.H, 0), scene));
    cam.fovMode = TargetCamera.FOVMODE_HORIZONTAL_FIXED;
    cam.minZ = this.H * 0.25;
    cam.maxZ = this.H * 1.5;

    this.flatMat = this.unlit('flat');
    this.buildingMat = this.unlit('buildings');
    this.textures = { day: facadeTexture(scene, false), night: facadeTexture(scene, true) };
    this.buildingMat.diffuseTexture = this.textures.day;
    this.buildingMat.emissiveTexture = this.textures.day;
    this.roadGeo = buildRoads(city, tuning, this.palette);

    this.tunnelShade = this.mesh('tunnel-shade', quadTris(4000, Z.tunnelShade, rgba(tokens.colorWorldTunnelShade)), this.flatMat, true, false);
    this.tunnelShade.setEnabled(false);
    this.carRoot = new TransformNode('car', scene);
    this.buildCar(drive.car);
    for (const k of propKinds) this.propMeshes.set(k, this.propMesh(k));
    this.lampGlow = this.mesh('lamp-glow', discTris(10, 0.02, rgba(tokens.colorPropsLampGlow)), this.flatMat, true, false);
    this.lampGlow.setEnabled(false);
    this.bollardH = displayHeight(extrusionScale(tuning.zones.bollardHeightM, tuning), this.H);
    this.bollardMesh = this.makeBollardMesh();

    const n = tuning.skids.maxSegments * 2;
    this.skidPos = new Float32Array(n * 4 * 3);
    const idx = new Uint32Array(n * 6);
    for (let i = 0; i < n; i++) idx.set([4 * i, 4 * i + 2, 4 * i + 1, 4 * i, 4 * i + 3, 4 * i + 2], 6 * i);
    const skidCol = rgba(tokens.colorCarSkid);
    const cols = new Float32Array(n * 16);
    for (let i = 0; i < n * 4; i++) cols.set(skidCol, 4 * i);
    this.skidMesh = new Mesh('skids', scene);
    const vd = new VertexData();
    vd.positions = this.skidPos;
    vd.indices = idx;
    vd.colors = cols;
    vd.applyToMesh(this.skidMesh, true);
    this.skidMesh.material = this.flatMat;
    this.skidMesh.hasVertexAlpha = true;
    this.skidMesh.alwaysSelectAsActiveMesh = true;

    this.applyClearColor();
    this.instr = new SceneInstrumentation(scene);
  }

  private unlit(name: string): StandardMaterial {
    // Colours are baked into vertices like client F; lighting off, emissive white = vertex × texture.
    const m = new StandardMaterial(name, this.scene);
    m.disableLighting = true;
    m.emissiveColor = Color3.White();
    m.diffuseColor = Color3.Black();
    m.specularColor = Color3.Black();
    m.backFaceCulling = true;
    // Explicit: geometry.ts winds front faces clockwise (the default differs between versions).
    m.sideOrientation = Material.ClockWiseSideOrientation;
    return m;
  }

  private mesh(name: string, t: Tris, mat: StandardMaterial, alpha = false, frozen = true): Mesh {
    const m = new Mesh(name, this.scene);
    const vd = new VertexData();
    vd.positions = new Float32Array(t.pos);
    vd.colors = new Float32Array(t.col);
    if (mat === this.buildingMat) vd.uvs = new Float32Array(t.uv);
    vd.indices = t.vertexCount > 65535 ? new Uint32Array(t.idx) : new Uint16Array(t.idx);
    vd.applyToMesh(m, false);
    m.material = mat;
    m.hasVertexAlpha = alpha;
    m.isPickable = false;
    if (frozen) {
      m.doNotSyncBoundingInfo = true;
      m.freezeWorldMatrix();
    }
    return m;
  }

  private applyClearColor(): void {
    const l = this.palette.land;
    this.scene.clearColor = new Color4(l[0], l[1], l[2], 1);
  }

  setNight(night: boolean): void {
    this.palette = night ? nightPalette : dayPalette;
    this.applyClearColor();
    const tex = night ? this.textures.night : this.textures.day;
    this.buildingMat.diffuseTexture = tex;
    this.buildingMat.emissiveTexture = tex;
    for (const c of this.chunks.values()) this.disposeChunk(c.meshes);
    for (const [k, c] of this.chunks) c.meshes = this.chunkMeshes(c.data, k);
    for (const r of this.roads.values()) this.disposeRoads(r);
    this.roads.clear();
    this.roadGeo = buildRoads(this.city, this.tuning, this.palette);
    this.buildCar(this.drive.car);
    for (const m of this.propMeshes.values()) m.dispose();
    for (const k of propKinds) this.propMeshes.set(k, this.propMesh(k));
    this.propsVersion = -1;
    this.bollardMesh.dispose();
    this.bollardMesh = this.makeBollardMesh();
    this.bollardsDirty = true;
  }

  // ---------- chunks

  private chunkMeshes(c: ChunkData, key: number): ChunkMeshes {
    const flat = new Tris();
    groundTris(c, this.palette, flat);
    const b = new Tris();
    buildingTris(c, this.palette, this.tuning, b);
    return {
      flat: flat.empty ? null : this.mesh(`ground-${key}`, flat, this.flatMat),
      buildings: b.empty ? null : this.mesh(`buildings-${key}`, b, this.buildingMat),
    };
  }

  addChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    if (this.chunks.has(key)) return;
    const bollards = bollardPoints(c, this.tuning.zones.bollardSpacingM);
    this.chunks.set(key, { data: c, meshes: this.chunkMeshes(c, key), bollards });
    if (bollards.length > 0) this.bollardsDirty = true;
  }

  removeChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    const e = this.chunks.get(key);
    if (!e) return;
    this.disposeChunk(e.meshes);
    this.chunks.delete(key);
    if (e.bollards.length > 0) this.bollardsDirty = true;
  }

  private disposeChunk(m: ChunkMeshes): void {
    m.flat?.dispose();
    m.buildings?.dispose();
  }

  private disposeRoads(r: RoadMeshes): void {
    r.ground?.dispose();
    r.bridge?.dispose();
    r.tunnel?.dispose();
  }

  /** Road meshes live per chunk key around the camera, independent of which chunks have buildings. */
  private updateRoads(): void {
    const cm = this.city.chunkM;
    const r = this.rig.visibleRadius(this.engine.getRenderWidth(), this.engine.getRenderHeight(), this.tuning) + cm;
    const x0 = Math.floor((this.rig.x - r) / cm), x1 = Math.floor((this.rig.x + r) / cm);
    const y0 = Math.floor((this.rig.y - r) / cm), y1 = Math.floor((this.rig.y + r) / cm);
    for (let cx = x0; cx <= x1; cx++) {
      for (let cy = y0; cy <= y1; cy++) {
        const k = chunkKey(cx, cy);
        if (this.roads.has(k)) continue;
        const g = this.roadGeo.get(k);
        const m: RoadMeshes = {
          ground: g && !g.ground.empty ? this.mesh(`roads-${k}`, g.ground, this.flatMat) : null,
          bridge: g && !g.bridge.empty ? this.mesh(`bridges-${k}`, g.bridge, this.flatMat) : null,
          tunnel: g && !g.tunnel.empty ? this.mesh(`tunnels-${k}`, g.tunnel, this.flatMat) : null,
        };
        m.tunnel?.setEnabled(this.inTunnel);
        this.roads.set(k, m);
      }
    }
    const keep = this.tuning.streaming.keep;
    const ccx = Math.floor(this.rig.x / cm), ccy = Math.floor(this.rig.y / cm);
    for (const [k, m] of this.roads) {
      const cx = Math.floor(k / 65536) - 32768, cy = (k % 65536) - 32768;
      if (Math.abs(cx - ccx) > keep || Math.abs(cy - ccy) > keep) {
        this.disposeRoads(m);
        this.roads.delete(k);
      }
    }
  }

  // ---------- car

  private buildCar(car: Car): void {
    if (this.carParts) this.carParts.root.dispose();
    const holder = new TransformNode('car-parts', this.scene);
    holder.parent = this.carRoot;
    // The shadow stays on the ground during a hop; the body is lifted and flipped (specs/hop.md).
    const shadowNode = new TransformNode('car-shadow', this.scene);
    shadowNode.parent = holder;
    const lift = new TransformNode('car-lift', this.scene);
    lift.parent = holder;
    const root = new TransformNode('car-body', this.scene);
    root.parent = lift;
    const hl = car.halfLength, hw = car.halfWidth;
    const night = this.palette.night;
    // Scooters and bicycles have no lights, cone or side wheels (specs/cars.md).
    const micro = car.spec.class === 'micro';
    const body = new Tris();
    const z = 0.0;
    // Class-specific vector shape (specs/cars.md "Kreslení"); lights go above its top part.
    const top = carTris(body, car.spec, hl, hw, car.axleOffset, 0, 0, 0, z - 0.01, night, false, false) - 0.01;
    this.mesh('car-body', body, this.flatMat, true, false).parent = root;
    const shadow = new Tris();
    carShadowTris(shadow, car.spec, hl, hw, z - 0.01);
    this.mesh('car-shadow', shadow, this.flatMat, true, false).parent = shadowNode;
    const underTris = new Tris();
    carUndersideTris(underTris, hl, hw, top);
    const under = this.mesh('car-under', underTris, this.flatMat, false, false);
    under.parent = lift;
    under.setEnabled(false);

    const lights = (c: string): Mesh => {
      const t = new Tris();
      t.rect(0, 0, 0, -hl, hw * 0.5, -hl * 0.92, hw * 0.85, top + 0.01, rgba(c));
      t.rect(0, 0, 0, -hl, -hw * 0.85, -hl * 0.92, -hw * 0.5, top + 0.01, rgba(c));
      const m = this.mesh('car-lights', t, this.flatMat, false, false);
      m.parent = root;
      m.setEnabled(false);
      return m;
    };
    const brake = lights(tokens.colorCarBrake), reverse = lights(tokens.colorCarReverse);

    const cone = new Tris();
    const a = cone.vertex(hl, hw * 0.6, z + 0.01, rgba(tokens.colorCarHeadlightCone));
    const b = cone.vertex(hl + 14 * hw, hw * 4, z + 0.01, rgba(tokens.colorCarHeadlightCone));
    const c = cone.vertex(hl + 14 * hw, -hw * 4, z + 0.01, rgba(tokens.colorCarHeadlightCone));
    const d = cone.vertex(hl, -hw * 0.6, z + 0.01, rgba(tokens.colorCarHeadlightCone));
    cone.tri(a, d, c);
    cone.tri(a, c, b);
    const coneMesh = this.mesh('car-cone', cone, this.flatMat, true, false);
    coneMesh.parent = root;
    coneMesh.setEnabled(night && !micro);

    const wheels: TransformNode[] = [];
    const ww = hl * 0.36, wt = hw * 0.32;
    const tyre = new Tris();
    tyre.rect(0, 0, 0, -ww / 2, -wt / 2, ww / 2, wt / 2, z + 0.01, rgba(tokens.colorCarTyre));
    for (const fx of micro ? [] : [car.axleOffset, -car.axleOffset]) {
      for (const sy of [hw * 0.92, -hw * 0.92]) {
        const w = new TransformNode('wheel', this.scene);
        w.parent = root;
        w.position.set(fx, 0, sy);
        this.mesh('tyre', tyre, this.flatMat, false, false).parent = w;
        if (fx > 0) wheels.push(w);
      }
    }
    this.carParts = { wheels, brake, reverse, cone: coneMesh, root: holder, lights: !micro, lift, top: root, under, shadow: shadowNode };
  }

  setFleet(f: CarFleet): void {
    this.fleet = f;
    this.parkedVersion = -1;
  }

  private updateParked(): void {
    const f = this.fleet;
    if (!f || f.version === this.parkedVersion) return;
    this.parkedVersion = f.version;
    this.parkedMesh?.dispose();
    const t = parkedTris(f.parked, f.specs, this.tuning.carScale, this.tuning.drive.axleOffset, Z.car);
    this.parkedMesh = t.empty ? null : this.mesh('parked-cars', t, this.flatMat, true, false);
  }

  /** Rebuilds the car after a respawn (new body, maybe new size). */
  carChanged(): void {
    this.buildCar(this.drive.car);
  }

  private updateCar(car: Car): void {
    const lift = car.layer > 0 ? this.tuning.layers.deckLiftM * car.layer : 0;
    this.carRoot.position.set(car.x, lift + Z.car, car.y);
    // Babylon rotates about +Y clockwise seen from above; world headings are CCW.
    this.carRoot.rotation.y = -car.heading;
    for (const w of this.carParts.wheels) w.rotation.y = -car.wheelAngle;
    this.carParts.brake.setEnabled(this.carParts.lights && car.braking && !car.reversing);
    this.carParts.reverse.setEnabled(this.carParts.lights && car.reversing);
    this.updateHop();
  }

  /**
   * Hop drawing (specs/hop.md "Kreslení", P2): the body rises by hopArc, shown at the display height
   * of an extruded building that tall (so it grows like roofs); the ground shadow shrinks by the
   * same roof scale; the flip squeezes the body width by cos(2π·flips·t/air_s) and past a quarter
   * turn shows the underside.
   */
  private updateHop(): void {
    const p = this.carParts, hop = this.drive.hop, ht = this.tuning.hop;
    const arc = hop.airborne ? hopArc(hop.t, ht.airS, ht.heightM) : 0;
    const flip = hop.airborne ? hopFlip(hop.t, ht.airS, ht.flips) : 1;
    const s = extrusionScale(arc, this.tuning);
    p.lift.position.y = displayHeight(s, this.H);
    p.lift.scaling.z = Math.abs(flip);
    p.shadow.scaling.x = p.shadow.scaling.z = 1 / s;
    const upside = flip < 0;
    if (p.top.isEnabled(false) === upside) p.top.setEnabled(!upside);
    if (p.under.isEnabled(false) !== upside) p.under.setEnabled(upside);
  }

  // ---------- props and skids

  private propMesh(kind: PropKind): Mesh {
    const t = new Tris();
    const c = (hex: string): Rgba => rgba(hex);
    switch (kind) {
      case 'lamp':
        t.disc(0, 0, 1, 0, c(tokens.colorPropsLamp));
        t.disc(0, 0, 0.5, 0.01, c(tokens.colorPropsLampBulb));
        break;
      case 'hydrant':
        t.disc(0, 0, 1, 0, c(tokens.colorPropsHydrant));
        break;
      case 'bin':
        t.disc(0, 0, 1, 0, c(tokens.colorPropsBin));
        t.disc(0, 0, 0.6, 0.01, c(tokens.colorPropsBinInner));
        break;
      case 'newsbox':
        t.rect(0, 0, 0, -0.8, -0.6, 0.8, 0.6, 0, c(tokens.colorPropsNewsbox));
        break;
      case 'planter':
        t.disc(0, 0, 1, 0, c(tokens.colorPropsPlanter));
        t.disc(0, 0, 0.75, 0.01, c(tokens.colorPropsPlanterGreen));
        break;
    }
    const m = this.mesh(`prop-${kind}`, t, this.flatMat, false, false);
    return m;
  }

  private updateProps(): void {
    const d = this.drive;
    if (d.propsVersion === this.propsVersion && !d.propsMoving) return;
    this.propsVersion = d.propsVersion;
    const byKind = new Map<PropKind, number[]>();
    const glow: number[] = [];
    const m = Matrix.Identity();
    for (const set of d.props.values()) {
      for (const p of set.props) {
        let list = byKind.get(p.kind);
        if (!list) byKind.set(p.kind, (list = []));
        const x = p.x + p.ox, y = p.y + p.oy;
        const s = p.radius;
        Matrix.ComposeToRef(new Vector3(s, 1, s), rotY(-(p.angle + p.rot)), new Vector3(x, Z.props, y), m);
        list.push(...m.m);
        if (p.kind === 'lamp' && !p.knocked) {
          Matrix.ComposeToRef(new Vector3(s, 1, s), rotY(0), new Vector3(x, Z.props - 0.01, y), m);
          glow.push(...m.m);
        }
      }
    }
    for (const [k, mesh] of this.propMeshes) {
      const list = byKind.get(k) ?? [];
      mesh.thinInstanceSetBuffer('matrix', list.length ? new Float32Array(list) : null, 16, false);
      mesh.thinInstanceRefreshBoundingInfo(false);
    }
    const night = this.palette.night;
    this.lampGlow.setEnabled(night && glow.length > 0);
    if (night) {
      this.lampGlow.thinInstanceSetBuffer('matrix', glow.length ? new Float32Array(glow) : null, 16, false);
      this.lampGlow.thinInstanceRefreshBoundingInfo(false);
    }
  }

  private makeBollardMesh(): Mesh {
    const t = new Tris();
    bollardTris(this.palette, t);
    return this.mesh('bollards', t, this.flatMat, false, false);
  }

  /** Writes one scale-and-translate matrix per bollard; runs only after a chunk change. */
  private updateBollards(): void {
    if (!this.bollardsDirty) return;
    this.bollardsDirty = false;
    let n = 0;
    for (const c of this.chunks.values()) n += c.bollards.length >> 1;
    const r = this.tuning.zones.bollardRadiusM, h = this.bollardH;
    const buf = n > 0 ? new Float32Array(n * 16) : null;
    if (buf) {
      let o = 0;
      for (const c of this.chunks.values()) {
        const p = c.bollards;
        for (let i = 0; i + 1 < p.length; i += 2, o += 16) {
          buf[o] = r;
          buf[o + 5] = h;
          buf[o + 10] = r;
          buf[o + 12] = p[i]!;
          buf[o + 14] = p[i + 1]!;
          buf[o + 15] = 1;
        }
      }
    }
    this.bollardMesh.thinInstanceSetBuffer('matrix', buf, 16, false);
    this.bollardMesh.thinInstanceRefreshBoundingInfo(false);
    this.bollardMesh.setEnabled(buf !== null);
  }

  private updateSkids(width: number): void {
    const d = this.drive;
    if (d.skidsVersion === this.skidsVersion) return;
    this.skidsVersion = d.skidsVersion;
    const s = d.skids, out = this.skidPos;
    out.fill(0);
    const n = Math.min(s.length / 4, out.length / 12);
    const hw = width / 2;
    for (let i = 0; i < n; i++) {
      const x0 = s[4 * i]!, y0 = s[4 * i + 1]!, x1 = s[4 * i + 2]!, y1 = s[4 * i + 3]!;
      const dx = x1 - x0, dy = y1 - y0;
      const l = Math.sqrt(dx * dx + dy * dy);
      if (l < 1e-3 || l > 30) continue; // teleports
      const nx = (-dy / l) * hw, ny = (dx / l) * hw;
      out.set([x0 + nx, Z.skids, y0 + ny, x1 + nx, Z.skids, y1 + ny, x1 - nx, Z.skids, y1 - ny, x0 - nx, Z.skids, y0 - ny], 12 * i);
    }
    this.skidMesh.updateVerticesData(VertexBuffer.PositionKind, out, false, false);
  }

  // ---------- frame

  /** Off-axis projection: the car sits at car_anchor without moving the camera (DUALSTACK 6.2). */
  private updateCamera(): void {
    const cam = this.camera, rig = this.rig, t = this.tuning;
    cam.position.set(rig.x, this.H, rig.y);
    cam.upVector.set(Math.cos(rig.heading), 0, Math.sin(rig.heading));
    cam.setTarget(new Vector3(rig.x, 0, rig.y));
    cam.fov = fovX(rig.viewWidth, this.H);
    cam.unfreezeProjectionMatrix();
    const base = cam.getProjectionMatrix(true);
    this.projArr.set(base.m);
    this.projArr[8]! += 2 * t.carAnchor.x - 1;
    this.projArr[9]! += 1 - 2 * t.carAnchor.y;
    Matrix.FromArrayToRef(this.projArr, 0, this.proj);
    cam.freezeProjectionMatrix(this.proj);
  }

  render(): void {
    const car = this.drive.car;
    const tunnel = car.layer < 0;
    if (tunnel !== this.inTunnel) {
      this.inTunnel = tunnel;
      this.tunnelShade.setEnabled(tunnel);
      for (const r of this.roads.values()) r.tunnel?.setEnabled(tunnel);
      this.buildingMat.alpha = tunnel ? 90 / 255 : 1;
    }
    if (tunnel) this.tunnelShade.position.set(this.rig.x, 0, this.rig.y);
    this.updateRoads();
    this.updateCamera();
    this.updateCar(car);
    this.updateProps();
    this.updateBollards();
    this.updateParked();
    this.updateSkids(car.halfWidth * 0.32);
    this.scene.render();
    this.stats.chunks = this.chunks.size;
    this.stats.drawCalls = this.instr.drawCallsCounter.current;
    this.stats.triangles = this.scene.getActiveIndices() / 3;
  }

  dispose(): void {
    this.scene.dispose();
  }
}

function rotY(a: number): Quaternion {
  return Quaternion.RotationAxis(Vector3.Up(), a);
}

function quadTris(size: number, h: number, c: Rgba): Tris {
  const t = new Tris();
  t.rect(0, 0, 0, -size, -size, size, size, h, c);
  return t;
}

function discTris(r: number, h: number, c: Rgba): Tris {
  const t = new Tris();
  t.disc(0, 0, r, h, c, 16);
  return t;
}

