import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { TargetCamera } from '@babylonjs/core/Cameras/targetCamera';
import { Material } from '@babylonjs/core/Materials/material';
import { Constants } from '@babylonjs/core/Engines/constants';
import { ShaderStore } from '@babylonjs/core/Engines/shaderStore';
import { PostProcess } from '@babylonjs/core/PostProcesses/postProcess';
import type { SubMesh } from '@babylonjs/core/Meshes/subMesh';
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
import { bollardPoints, bollardTris, buildRoads, buildingTris, castShadowTris, groundTris, Tris, Z, type RoadChunk } from './geometry';
import { cityInks, cityPalette, dayPalette, nightPalette, rgba, type Palette, type Rgba } from './palette';
import {
  DEPTH_LAYER, DYNAMIC_LAYERS, RISOGRAPH_FRAGMENT, RISOGRAPH_UNIFORMS, WORLD_LAYER, cityFlag, mainCameraMask, risographOn, risographUniforms,
} from './risograph';
import { facadeTexture } from './textures';
import { CAR_PART_DZ, carGlowTris, carShadowTris, carTris, carUndersideTris, parkedTris, wheelRects } from '../cars/carTris';
import { carShape } from '../cars/shape';
import type { ParkedCar } from '../cars/parked';
import { glowStrength, lookRim } from '../garage/looks';
import type { Look } from '../garage/rules';
import { RESCUE_ANIM_S } from '../drive/flow';
import { hopArc, hopFlip } from '../drive/hop';
import type { CarFleet } from '../cars/fleet';
import { CarSpriteView, LIGHTS_BRAKE, LIGHTS_FULL, LIGHTS_OFF } from './carSprites';
import { lookPaint } from '../garage/looks';
import { paintHex } from '../cars/shape';
import { NatureView } from './natureView';
import { bankTris, greenTris } from './natureGeometry';

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

/**
 * Layer masks for the risograph (specs/style.md): it applies to the world layer only. World meshes
 * (ground, roads, zones, buildings, rails, tunnel shade) carry WORLD_LAYER; buildings and bridge
 * decks also DEPTH_LAYER, so the second camera redraws them depth-only and cars still hide behind
 * them. Everything else keeps Babylon's default mask (0x0FFFFFFF).
 */

ShaderStore.ShadersStore['risographFragmentShader'] = RISOGRAPH_FRAGMENT;

/** Opaque order of the dynamic camera: depth-only world casters first, then Babylon's material order. */
function depthFirst(a: SubMesh, b: SubMesh): number {
  const ma = a.getMesh(), mb = b.getMesh();
  const da = (ma.layerMask & DEPTH_LAYER) !== 0 ? 0 : 1, db = (mb.layerMask & DEPTH_LAYER) !== 0 ? 0 : 1;
  if (da !== db) return da - db;
  if (ma.material && mb.material) return ma.material.uniqueId - mb.material.uniqueId;
  return ma.uniqueId - mb.uniqueId;
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
  /** Building cast shadows (style A, specs/style.md v2), day only. */
  shadows: Mesh | null;
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
  /** Day palette of the loaded city (specs/style.md); a city switch reloads the page (specs/cities.md). */
  readonly dayPalette: Palette;
  readonly stats: RenderStats = { chunks: 0, drawCalls: 0, triangles: 0 };

  private readonly H: number;
  private readonly flatMat: StandardMaterial;
  /** Roads, sidewalks and alleys (with their markings): own material for the wet look (specs/weather.md). */
  private readonly roadMat: StandardMaterial;
  private wet = 1;
  private readonly buildingMat: StandardMaterial;
  private readonly shadowMat: StandardMaterial;
  private readonly textures: { day: Texture; night: Texture };
  private readonly chunks = new Map<number, ChunkEntry>();
  private roadGeo: Map<number, RoadChunk>;
  private readonly roads = new Map<number, RoadMeshes>();
  private readonly tunnelShade: Mesh;
  private readonly carRoot: TransformNode;
  /** Visibility of the car meshes (rescue fade, specs/flow.md). */
  private carAlpha = 1;
  private carParts!: {
    wheels: TransformNode[]; brake: Mesh; reverse: Mesh; cone: Mesh; root: TransformNode; lights: boolean;
    /** Hop (specs/hop.md): the lifted, flipped body; its top and underside; the ground shadow. */
    lift: TransformNode; top: TransformNode; under: Mesh; shadow: TransformNode;
    /** Underglow of an own car (specs/garage.md), null without one. */
    glow: Mesh | null;
    /** The sprite's lights.png shows the brake lights (the procedural brake mesh stays off). */
    spriteLights: boolean;
  };
  /**
   * Looks of own cars (specs/garage.md "Kreslení"): the driven car's (null for a stolen car or no
   * garage) and of the player's parked cars; set by the garage, then `looksChanged()`.
   */
  looks: { driven(): Look | null; parked(p: ParkedCar): Look | null } | null = null;
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
  private readonly spriteM = Matrix.Identity();
  /** Parked cars (specs/cars.md), one merged mesh rebuilt when the fleet's version changes. */
  private fleet: CarFleet | null = null;
  private parkedMesh: Mesh | null = null;
  private parkedVersion = -1;
  /**
   * Car sprites (specs/art.md v2 "Auta"): atlases and three thin-instance meshes shared with
   * traffic and patrols; null until the fleet is set. Cars without a sprite stay procedural.
   */
  sprites: CarSpriteView | null = null;
  /** The driven car draws its sprite (decided in buildCar). */
  private carSprite = false;
  /** Risograph: second camera for everything above the world layer, the pass, depth-only material. */
  private readonly topCamera: TargetCamera;
  private readonly depthMat: StandardMaterial;
  private riso: PostProcess | null = null;
  /** Water plane, trees and hit effects (specs/nature.md); idle for a pack without nature. */
  readonly nature: NatureView;
  private lastFrame = 0;

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
    // World meshes live on WORLD_LAYER, outside Babylon's default camera mask: without the risograph
    // the main camera must see every layer (NYC, or any city loaded at night).
    cam.layerMask = mainCameraMask(false);
    const top = (this.topCamera = new TargetCamera('camera-top', new Vector3(0, this.H, 0), scene, false));
    top.fovMode = TargetCamera.FOVMODE_HORIZONTAL_FIXED;
    top.minZ = cam.minZ;
    top.maxZ = cam.maxZ;
    this.dayPalette = cityPalette(city.id);
    this.palette = this.dayPalette;

    this.flatMat = this.unlit('flat');
    this.roadMat = this.unlit('roads');
    this.buildingMat = this.unlit('buildings');
    // Cast shadows must not add up where they overlap (specs/style.md v2): all shadow triangles
    // lie in one plane and write depth, and a fragment at equal depth fails LESS, so each pixel
    // is darkened once. Drawn first among the alpha meshes (alphaIndex), so cars and peds blend over it.
    this.shadowMat = this.unlit('cast-shadows');
    this.shadowMat.forceDepthWrite = true;
    this.shadowMat.depthFunction = Constants.LESS;
    this.textures = { day: facadeTexture(scene, false), night: facadeTexture(scene, true) };
    this.buildingMat.diffuseTexture = this.textures.day;
    this.buildingMat.emissiveTexture = this.textures.day;
    this.depthMat = this.unlit('world-depth');
    this.depthMat.disableColorWrite = true;
    this.roadGeo = buildRoads(city, tuning, this.palette);

    this.tunnelShade = this.world(this.mesh('tunnel-shade', quadTris(4000, Z.tunnelShade, rgba(tokens.colorWorldTunnelShade)), this.flatMat, true, false), false);
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

    this.nature = new NatureView({
      scene, city, tuning, drive, H: this.H,
      unlit: (n) => this.unlit(n),
      mesh: (n, t, mat, alpha, frozen) => this.mesh(n, t, mat, alpha, frozen),
      world: (m) => this.world(m, false),
    }, this.palette);
    this.applyClearColor();
    this.applyRisograph();
    this.instr = new SceneInstrumentation(scene);
  }

  /** Puts a mesh in the world layer; [depth]: also drawn depth-only under the dynamic layer. */
  private world(m: Mesh, depth: boolean): Mesh {
    m.layerMask = depth ? WORLD_LAYER | DEPTH_LAYER : WORLD_LAYER;
    if (depth) m.setMaterialForRenderPass(this.topCamera.renderPassId, this.depthMat);
    return m;
  }

  /**
   * Risograph on/off (specs/style.md "Risograf"): by day in a city with style.risograph.<id>. On:
   * the main camera renders only the world layer through one post-process pass, then the top
   * camera draws cars, peds, props, trams over it (world buildings and bridges depth-only, so
   * occlusion stays as without the effect). Off: one camera renders everything, as before.
   */
  private applyRisograph(): void {
    const on = risographOn(this.tuning.style, this.city.id, this.palette.night);
    if (on === (this.riso !== null)) return;
    const scene = this.scene, cam = this.camera;
    if (!on) {
      cam.detachPostProcess(this.riso!);
      this.riso!.dispose(cam);
      this.riso = null;
      cam.layerMask = mainCameraMask(false);
      scene.activeCameras = [];
      scene.activeCamera = cam;
      scene.setRenderingOrder(0, null);
      return;
    }
    const style = this.tuning.style;
    const ink = cityInks(this.city.id)[0] ?? this.palette.rail;
    const pp = new PostProcess('risograph', 'risograph', {
      uniforms: [...RISOGRAPH_UNIFORMS, 'texelSize'],
      size: 1,
      camera: cam,
      samplingMode: 1, // nearest: the pass samples whole pixels
      engine: this.engine,
      reusable: false,
    });
    pp.samples = this.engine.getCaps().maxMSAASamples >= 4 ? 4 : 1;
    pp.autoClear = true;
    pp.onApply = (fx) => {
      const u = risographUniforms(style, ink, 1 / this.engine.getHardwareScalingLevel());
      fx.setFloat2('texelSize', 1 / Math.max(pp.width, 1), 1 / Math.max(pp.height, 1));
      fx.setFloat3('ink', u.ink[0], u.ink[1], u.ink[2]);
      fx.setFloat('offsetPx', u.offsetPx);
      fx.setFloat('fringe', u.fringe);
      fx.setFloat('cellPx', u.cellPx);
      fx.setFloat('halftoneStrength', u.halftoneStrength);
      fx.setFloat('halftoneLow', u.halftoneLow);
      fx.setFloat('halftoneHigh', u.halftoneHigh);
      fx.setFloat('grainPx', u.grainPx);
      fx.setFloat('grainStrength', u.grainStrength);
    };
    this.riso = pp;
    cam.layerMask = mainCameraMask(true);
    this.updateTopMask();
    scene.activeCameras = [cam, this.topCamera];
    scene.setRenderingOrder(0, depthFirst);
  }

  /** In a tunnel the buildings are see-through, so they must not hide what drives under them. */
  private updateTopMask(): void {
    this.topCamera.layerMask = this.inTunnel ? DYNAMIC_LAYERS : DYNAMIC_LAYERS | DEPTH_LAYER;
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

  /**
   * Wet roads (specs/weather.md "Déšť"): road, sidewalk and alley colours × [f] (1 − wet_darken
   * in full rain, 1 dry). A material colour, so no geometry is rebuilt during the blend.
   */
  setWet(f: number): void {
    if (f === this.wet) return;
    this.wet = f;
    this.roadMat.emissiveColor.set(f, f, f);
  }

  setNight(night: boolean): void {
    this.palette = night ? nightPalette : this.dayPalette;
    this.applyClearColor();
    this.applyRisograph();
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
    this.parkedVersion = -1;
    this.nature.setPalette(this.palette);
  }

  // ---------- chunks

  private chunkMeshes(c: ChunkData, key: number): ChunkMeshes {
    const flat = new Tris();
    groundTris(c, this.palette, flat);
    // Green fills and the bank line share the chunk's flat mesh (no extra draw call, specs/nature.md).
    if (c.nature) {
      greenTris(c.nature, this.palette, flat);
      bankTris(c.nature, this.city.chunkM, this.palette, flat);
    }
    const b = new Tris();
    buildingTris(c, this.palette, this.tuning, b);
    const sh = new Tris();
    if (cityFlag(this.tuning.style.castShadow, this.city.id, this.palette.night)) castShadowTris(c, this.palette, this.tuning, sh);
    let shadows: Mesh | null = null;
    if (!sh.empty) {
      shadows = this.world(this.mesh(`shadows-${key}`, sh, this.shadowMat, true), false);
      shadows.alphaIndex = 0;
    }
    return {
      flat: flat.empty ? null : this.world(this.mesh(`ground-${key}`, flat, this.flatMat), false),
      buildings: b.empty ? null : this.world(this.mesh(`buildings-${key}`, b, this.buildingMat), true),
      shadows,
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
    m.shadows?.dispose();
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
          ground: g && !g.ground.empty ? this.world(this.mesh(`roads-${k}`, g.ground, this.roadMat), false) : null,
          bridge: g && !g.bridge.empty ? this.world(this.mesh(`bridges-${k}`, g.bridge, this.roadMat), true) : null,
          tunnel: g && !g.tunnel.empty ? this.world(this.mesh(`tunnels-${k}`, g.tunnel, this.roadMat), false) : null,
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
    this.carAlpha = 1;
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
    const look = this.looks?.driven() ?? null;
    // Sprite (specs/art.md v2): the body, wheels and lights.png come from the sprite meshes; the
    // shadow, cone, glow, underside and reverse lights stay here.
    const sp = this.sprites;
    if (sp && look) sp.requireDecals([[car.spec.id, look.decal ?? 0]]);
    const sprite = (this.carSprite = !!sp && sp.has(car.spec.id, look?.decal ?? 0));
    const top = sprite ? 0.035 : carTris(body, car.spec, hl, hw, car.axleOffset, 0, 0, 0, z - 0.01, night, false, false, undefined, look) - 0.01;
    if (!sprite) this.mesh('car-body', body, this.flatMat, true, false).parent = root;
    const shadow = new Tris();
    carShadowTris(shadow, car.spec, hl, hw, z - 0.01, this.palette.shadow);
    this.mesh('car-shadow', shadow, this.flatMat, true, false).parent = shadowNode;
    // Underglow under the shadow, on the ground during a hop; its strength is set per frame.
    const glowT = new Tris();
    carGlowTris(glowT, look, hl, hw, this.tuning.garage.glowMarginM, 0, 0, 0, z - 0.01 - CAR_PART_DZ, 1);
    const glow = glowT.empty ? null : this.mesh('car-glow', glowT, this.flatMat, true, false);
    if (glow) {
      glow.parent = shadowNode;
      glow.alphaIndex = 1;
    }
    const underTris = new Tris();
    carUndersideTris(underTris, hl, hw, top);
    const under = this.mesh('car-under', underTris, this.flatMat, false, false);
    under.parent = lift;
    under.setEnabled(false);

    const lights = (c: string): Mesh => {
      const t = new Tris();
      // Over the tail lights of the class shape (specs/cars.md: veterans have a narrower body).
      for (const r of carShape(car.spec.class, hl, hw, car.spec.length_m, car.axleOffset)) {
        if (r.part === 'tail') t.rect(0, 0, 0, r.x0, r.y0, r.x1, r.y1, top + 0.01, rgba(c));
      }
      const m = this.mesh('car-lights', t, this.flatMat, false, false);
      m.parent = root;
      m.setEnabled(false);
      return m;
    };
    const brake = lights(tokens.colorCarBrake), reverse = lights(tokens.colorCarReverse);
    // lights.png brakes instead (rear half by day, specs/art.md "Světla").
    const spriteLights = sprite && sp!.hasLights(car.spec.id);

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
    // Wheels by class (specs/cars.md); the single front wheel of a trike or rickshaw sits over the body.
    for (const r of sprite ? [] : wheelRects(hl, hw, car.axleOffset, car.spec.class, car.spec.length_m)) {
      const wz = r.top ? top + 0.02 : z + 0.01;
      const cx = (r.x0 + r.x1) / 2, cy = (r.y0 + r.y1) / 2;
      const tyre = new Tris();
      tyre.rect(0, 0, 0, r.x0 - cx, r.y0 - cy, r.x1 - cx, r.y1 - cy, wz, rgba(tokens.colorCarTyre));
      // Rim of an own car (specs/garage.md "wheels").
      if (look) tyre.rect(0, 0, 0, r.rim[0] - cx, r.rim[1] - cy, r.rim[2] - cx, r.rim[3] - cy, wz + 0.005, rgba(lookRim(look)));
      const w = new TransformNode('wheel', this.scene);
      w.parent = root;
      w.position.set(cx, 0, cy);
      this.mesh('tyre', tyre, this.flatMat, false, false).parent = w;
      if (r.front) wheels.push(w);
    }
    this.carParts = { wheels, brake, reverse, cone: coneMesh, root: holder, lights: !micro, lift, top: root, under, shadow: shadowNode, glow,
      spriteLights };
  }

  setFleet(f: CarFleet): void {
    this.fleet = f;
    this.parkedVersion = -1;
    if (!this.sprites) {
      const sp = (this.sprites = new CarSpriteView(this.scene, this.tuning, this.city.id, f.specs));
      sp.onReady(() => {
        this.buildCar(this.drive.car);
        this.parkedVersion = -1;
      });
    }
  }

  private updateParked(): void {
    const f = this.fleet;
    if (!f || f.version === this.parkedVersion) return;
    this.parkedVersion = f.version;
    this.parkedMesh?.dispose();
    const looks = this.looks;
    const glow = { margin: this.tuning.garage.glowMarginM, strength: glowStrength(this.palette.night, false, this.tuning.garage.glowDay) };
    const sp = this.sprites;
    const lookOf = looks ? (p: ParkedCar): Look | null => looks.parked(p) : null;
    if (sp && lookOf) sp.requireDecals(f.parked.map((p) => [p.carId, lookOf(p)?.decal ?? 0] as [string, number]));
    const t = parkedTris(f.parked, f.specs, this.tuning.carScale, this.tuning.drive.axleOffset, Z.car, this.palette.shadow,
      lookOf, glow, sp ? (p, look) => sp.has(p.carId, look?.decal ?? 0) : null);
    this.parkedMesh = t.empty ? null : this.mesh('parked-cars', t, this.flatMat, true, false);
    if (!sp) return;
    // Parked sprites: straight wheels, no lights (specs/cars.md "bez světlometů").
    sp.begin('parked');
    const scale = this.tuning.carScale, m = this.spriteM;
    for (const p of f.parked) {
      const s = f.specs.get(p.carId), look = lookOf?.(p) ?? null, decal = look?.decal ?? 0;
      if (!s || !sp.has(p.carId, decal)) continue;
      const px = sp.size(p.carId)!;
      Matrix.RotationYToRef(-p.heading, m);
      m.setTranslationFromFloats(p.x, Z.car, p.y);
      const hl = (s.length_m * scale) / 2, hw = (s.width_m * scale) / 2;
      sp.add('parked', {
        id: p.carId, decal, world: m, len: (px.h / 32) * scale, wid: (px.w / 32) * scale, hl, hw, axle: hl * this.tuning.drive.axleOffset,
        paint: rgba(look ? lookPaint(s, look) : paintHex(s.paint)), steer: 0,
        wheelTint: look && (look.wheels ?? 0) > 0 ? rgba(lookRim(look)) : null, lights: LIGHTS_OFF,
      });
    }
  }

  /** Rebuilds the car after a respawn (new body, maybe new size). */
  carChanged(): void {
    this.buildCar(this.drive.car);
  }

  /** Redraws the driven and the parked own cars after a look changed (specs/garage.md). */
  looksChanged(): void {
    this.buildCar(this.drive.car);
    this.parkedVersion = -1;
  }

  private updateCar(car: Car): void {
    const lift = car.layer > 0 ? this.tuning.layers.deckLiftM * car.layer : 0;
    this.carRoot.position.set(car.x, lift + Z.car, car.y);
    // Babylon rotates about +Y clockwise seen from above; world headings are CCW.
    this.carRoot.rotation.y = -car.heading;
    for (const w of this.carParts.wheels) w.rotation.y = -car.wheelAngle;
    // Rescue move (specs/flow.md): the car fades in at its new place over the animation.
    const anim = this.drive.flow.animT;
    // Water fall (specs/nature.md "Voda"): the car shrinks to 0.6 and fades out over sink_s.
    const sink = this.drive.water.progress(this.tuning.nature.waterFall.sinkS);
    const alpha = (anim > 0 ? 1 - anim / RESCUE_ANIM_S : 1) * (1 - sink);
    const sc = 1 - 0.4 * sink;
    this.carRoot.scaling.set(sc, 1, sc);
    if (alpha !== this.carAlpha) {
      this.carAlpha = alpha;
      for (const m of this.carRoot.getChildMeshes(false)) if (m !== this.carParts.glow) m.visibility = alpha;
    }
    const glow = this.carParts.glow;
    if (glow) glow.visibility = glowStrength(this.palette.night, car.layer < 0, this.tuning.garage.glowDay) * alpha;
    this.carParts.brake.setEnabled(this.carParts.lights && !this.carParts.spriteLights && car.braking && !car.reversing);
    this.carParts.reverse.setEnabled(this.carParts.lights && car.reversing);
    this.updateHop();
    this.updateCarSprite(car);
  }

  /** The driven car's sprite instance, following the body node (lift and flip of a hop). */
  private updateCarSprite(car: Car): void {
    const sp = this.sprites;
    if (!sp) return;
    sp.begin('player');
    const top = this.carParts.top;
    if (!this.carSprite || !top.isEnabled(false)) return;
    const look = this.looks?.driven() ?? null;
    const px = sp.size(car.spec.id)!, scale = this.tuning.carScale;
    const night = this.palette.night;
    // Forced up the chain: before scene.render the cached matrices are a frame old.
    for (const n of [this.carRoot, this.carParts.root, this.carParts.lift]) n.computeWorldMatrix(true);
    const braking = this.carParts.lights && car.braking && !car.reversing;
    sp.add('player', {
      id: car.spec.id, decal: look?.decal ?? 0, world: top.computeWorldMatrix(true),
      len: (px.h / 32) * scale, wid: (px.w / 32) * scale, hl: car.halfLength, hw: car.halfWidth, axle: car.axleOffset,
      paint: rgba(lookPaint(car.spec, look)), steer: car.wheelAngle,
      wheelTint: look && (look.wheels ?? 0) > 0 ? rgba(lookRim(look)) : null,
      lights: !this.carParts.lights ? LIGHTS_OFF : night ? LIGHTS_FULL : braking ? LIGHTS_BRAKE : LIGHTS_OFF,
      // Rescue fade-in (specs/flow.md) as for the procedural meshes.
      alpha: this.carAlpha,
    });
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
    if (this.riso) {
      const top = this.topCamera;
      top.position.copyFrom(cam.position);
      top.upVector.copyFrom(cam.upVector);
      top.setTarget(new Vector3(rig.x, 0, rig.y));
      top.fov = cam.fov;
      top.freezeProjectionMatrix(this.proj);
    }
  }

  render(): void {
    const car = this.drive.car;
    const tunnel = car.layer < 0;
    if (tunnel !== this.inTunnel) {
      this.inTunnel = tunnel;
      this.tunnelShade.setEnabled(tunnel);
      for (const r of this.roads.values()) r.tunnel?.setEnabled(tunnel);
      this.buildingMat.alpha = tunnel ? 90 / 255 : 1;
      this.updateTopMask();
    }
    if (tunnel) this.tunnelShade.position.set(this.rig.x, 0, this.rig.y);
    this.updateRoads();
    this.updateCamera();
    this.updateCar(car);
    this.updateProps();
    this.updateBollards();
    this.updateParked();
    this.updateSkids(car.halfWidth * 0.32);
    const now = performance.now();
    this.nature.update(car.x, car.y, this.lastFrame > 0 ? Math.min(0.1, (now - this.lastFrame) / 1000) : 0);
    this.lastFrame = now;
    this.sprites?.flush();
    this.scene.render();
    this.stats.chunks = this.chunks.size;
    this.stats.drawCalls = this.instr.drawCallsCounter.current;
    this.stats.triangles = this.scene.getActiveIndices() / 3;
  }

  dispose(): void {
    this.sprites?.dispose();
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

