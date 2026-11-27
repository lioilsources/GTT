import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { TargetCamera } from '@babylonjs/core/Cameras/targetCamera';
import { Material } from '@babylonjs/core/Materials/material';
import { Constants } from '@babylonjs/core/Engines/constants';
import { ShaderStore } from '@babylonjs/core/Engines/shaderStore';
import { PostProcess } from '@babylonjs/core/PostProcesses/postProcess';
import type { SubMesh } from '@babylonjs/core/Meshes/subMesh';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Texture } from '@babylonjs/core/Materials/Textures/texture';
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
import {
  baseHeight, bollardPoints, bollardTris, buildingShadow, buildRoads, buildingTris, castShadowTris, DRAPE_LIFT, GROUND_ORDER, groundTris, shadowLength, Tris, VEHICLE_LIFT, Z, type RoadChunk,
} from './geometry';
import { drapedGreenTris, drapedGroundTris, meshHeight, renderHeights, shadeFactor, terrainTris } from './terrainMesh';
import { shadowScale, TERRAIN_SPEC } from '../drive/slope';
import { TERRAIN_N } from '../world/chunk';
import { cityInks, cityPalette, dayPalette, nightPalette, rgba, type Palette, type Rgba } from './palette';
import {
  DEPTH_LAYER, DYNAMIC_LAYERS, RISOGRAPH_FRAGMENT, RISOGRAPH_UNIFORMS, WORLD_LAYER, cityFlag, mainCameraMask, risographOn, risographUniforms,
} from './risograph';
import { facadeTexture, modelRoofTexture, modelStoneTexture } from './textures';
import { CAR_PART_DZ, carGlowTris, carShadowTris, carTris, carUndersideTris, parkedTris, polyTris, wheelPrims, wheelRects } from '../cars/carTris';
import { carShape } from '../cars/shape';
import type { ParkedCar } from '../cars/parked';
import { glowStrength, lookRim } from '../garage/looks';
import type { Look } from '../garage/rules';
import { RESCUE_ANIM_S } from '../drive/flow';
import { hopArc, hopFlip, hopRoll } from '../drive/hop';
import type { CarFleet } from '../cars/fleet';
import { CarSpriteView, LIGHTS_BRAKE, LIGHTS_FULL, LIGHTS_OFF } from './carSprites';
import { lookPaint } from '../garage/looks';
import { paintHex } from '../cars/shape';
import { NatureView } from './natureView';
import { bankTris, greenTris } from './natureGeometry';
import { CHASE_BODY_M, CHASE_NEAR_M, chaseFov, chasePose, FOG_END_M, FOG_START_M, type CameraMode, type ChasePose } from './chase';
import { FarRing, SKY_R } from './farRing';
import { OccluderFadePlugin, type FadeState } from './occluderFade';
import type { PackSource } from '../world/citypack';
import { fullModels, modelDistance } from '../world/models';
import { loadPhotoTrial, photoTrialVariant, type PhotoTrial } from '../world/photoTrial';
import { modelTris, newModelTris, planBuildings, planTris } from './modelGeometry';

/** Rotating follow camera state (port of world_engine camera.dart). */
export class CameraRig {
  x = 0;
  y = 0;
  /** z_ref (specs/terrain.md): the smoothed ground height under the car; 0 in a flat pack. */
  z = 0;
  /** Short zoom-out factor (edge, hard landing) and camera shake offset (m), set by WorldView. */
  zoom = 1;
  shakeX = 0;
  shakeY = 0;
  /** Ground height for overlay points (labels, icons); null = flat. */
  zAt: ((x: number, y: number) => number) | null = null;
  /** World heading that points up on screen (radians, 0 = east, CCW). */
  heading = Math.PI / 2;
  viewWidth = 1;
  /**
   * Chase view (specs/terrain.md "Šikmý pohled"): world point (x, y, z) → CSS pixels through the
   * 3D camera, set by WorldView while it is on; null = the top-down projection below.
   */
  project: ((x: number, y: number, z: number, w: number, h: number) => { x: number; y: number }) | null = null;

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

  /**
   * World point → CSS pixels; the ground plane is what fovX frames (DUALSTACK 6.2). A point at
   * height wz (default: the ground under it) is scaled about the camera by H / (H − (z − z_ref)).
   */
  toScreen(wx: number, wy: number, w: number, h: number, t: Tuning, wz?: number): { x: number; y: number } {
    if (this.project) return this.project(wx, wy, wz ?? this.zAt?.(wx, wy) ?? this.z, w, h);
    const ppm = w / (this.viewWidth * this.zoom);
    const a = Math.PI / 2 - this.heading;
    let dx = wx - this.x - this.shakeX, dy = wy - this.y - this.shakeY;
    const z = wz ?? this.zAt?.(wx, wy);
    if (z !== undefined) {
      const H = t.camera.topdown.heightM;
      const k = H / (H - Math.min(Math.max(z - this.z, -2 * H), 0.8 * H));
      dx *= k;
      dy *= k;
    }
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
    // Chase view: traffic, pedestrians and roads around the car out to the near world's reach.
    if (this.project) return CHASE_NEAR_M;
    const vw = this.viewWidth * this.zoom, vh = (vw * h) / w;
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
  /** Terrain mesh (specs/terrain.md), null in a flat pack. */
  terrain: Mesh | null;
  flat: Mesh | null;
  buildings: Mesh | null;
  /** Building cast shadows (style A, specs/style.md v2), day only. */
  shadows: Mesh | null;
  /** Buildings a landmark model replaces (specs/models.md), per model index: hidden while it is drawn. */
  replaced: Map<number, { buildings: Mesh | null; shadows: Mesh | null }>;
}

/** Meshes of one landmark model (specs/models.md), built with its home chunk. */
interface ModelMeshes {
  /** The full model: window walls, stone walls, roofs (specs/models.md v2 "Fasáda"). */
  full: Mesh[];
  plan: Mesh | null;
  /** Cast shadows of the roof-plan prisms (style A), null without. */
  shadows: Mesh | null;
}

interface ChunkEntry {
  data: ChunkData;
  meshes: ChunkMeshes;
  /** Bollard positions (x, y interleaved), fixed for the chunk's lifetime. */
  bollards: Float32Array;
  /** Drawn in detail (always from above; in the chase view only near the car, the far ring beyond). */
  near: boolean;
}

interface RoadMeshes {
  /** The ground roads carry the hillshade of a loaded terrain grid (relief only). */
  shaded: boolean;
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
  /** Terrain mesh: pushed back in depth so draped ground and roads always win (zOffset). */
  private readonly terrainMat: StandardMaterial;
  private readonly tunnelShadeMat: StandardMaterial;
  /** Relief (specs/terrain.md): the pack has heights. */
  private readonly relief: boolean;
  private terrainVersion = -1;
  private reliefFrame = 0;
  private lastCarX = 0;
  private lastCarY = 0;
  /** Roads, sidewalks and alleys (with their markings): own material for the wet look (specs/weather.md). */
  private readonly roadMat: StandardMaterial;
  private readonly bridgeMat: StandardMaterial;
  private wet = 1;
  private readonly buildingMat: StandardMaterial;
  private readonly shadowMat: StandardMaterial;
  private readonly textures: { day: Texture; night: Texture };
  /** Landmark model stone walls and roofs (specs/models.md v2 "Fasáda"); window walls use buildingMat. */
  private readonly modelStoneMat: StandardMaterial;
  private readonly modelRoofMat: StandardMaterial;
  /** Photo texture trial (?photo=…): the baked atlas, null until loaded. */
  private readonly modelPhotoMat: StandardMaterial;
  private photo: PhotoTrial | null = null;
  private readonly modelTextures: { stone: { day: Texture; night: Texture }; roof: { day: Texture; night: Texture } };
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
    /** Height of the body's top (the underside plate is drawn there). */
    topH: number;
    /** Box sides of the chase view and the mode the parts are set up for (null = not yet). */
    sides: Mesh;
    chase: boolean | null;
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
  /**
   * Camera mode (specs/terrain.md "Šikmý pohled", K1 = A: top-down by default). The chase view is
   * suspended while something needs the map from above (the Camera's framing view).
   */
  private mode: CameraMode = 'topdown';
  chaseSuspended = false;
  private chaseOn = false;
  /** Far ring, sky and fog of the chase view; idle from above. */
  readonly ring: FarRing;
  private readonly fade: FadeState = { on: false, eye: [0, 0, 0], car: [0, 0, 0] };
  /** Landmark models (specs/models.md): meshes per model index, and the ones drawn in full. */
  private readonly modelMeshes = new Map<number, ModelMeshes>();
  private modelsFull = new Set<number>();
  /** A model is drawn (full or plan): its replaced buildings are hidden. */
  private readonly modelActive: boolean[] = [];
  private pose: ChasePose | null = null;
  private readonly viewProj = Matrix.Identity();

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
    // Relief: the projection clamp of client F reaches 2H below z_ref (specs/terrain.md).
    cam.maxZ = this.H * 3;
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
    this.relief = city.terrain.enabled;
    this.terrainMat = this.unlit('terrain');
    this.terrainMat.zOffset = 1;
    this.terrainMat.zOffsetUnits = 4;
    // Tunnel (specs/terrain.md: the roof is hidden from above): the shade darkens all of the world
    // drawn so far, then rendering group 1 clears depth and draws the tunnel and the car.
    this.tunnelShadeMat = this.unlit('tunnel-shade');
    this.tunnelShadeMat.depthFunction = Constants.ALWAYS;
    this.tunnelShadeMat.disableDepthWrite = true;
    this.rig.zAt = this.relief ? (x, y) => city.terrain.terrainAt(x, y) ?? this.rig.z : null;
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
    this.modelStoneMat = this.unlit('model-stone');
    this.modelRoofMat = this.unlit('model-roofs');
    this.modelPhotoMat = this.unlit('model-photo');
    this.modelTextures = {
      stone: { day: modelStoneTexture(scene, false), night: modelStoneTexture(scene, true) },
      roof: { day: modelRoofTexture(scene, false), night: modelRoofTexture(scene, true) },
    };
    this.applyModelTextures(false);
    this.depthMat = this.unlit('world-depth');
    this.depthMat.disableColorWrite = true;
    // Bridge decks: the road look, own material for the occluder fade of the chase view.
    this.bridgeMat = this.unlit('bridges');
    // Occluding buildings and decks fade in the chase view, also in the risograph's depth pass (the car shows through).
    for (const m of [this.buildingMat, this.modelStoneMat, this.modelRoofMat, this.modelPhotoMat, this.bridgeMat, this.depthMat]) new OccluderFadePlugin(m, this.fade);
    const photoVariant = photoTrialVariant();
    if (photoVariant !== null) {
      void loadPhotoTrial(city.id, photoVariant).then((p) => {
        if (!p) return;
        const tex = new Texture(p.atlasUrl, scene, false, true, Texture.TRILINEAR_SAMPLINGMODE, () => {
          this.photo = p;
          this.disposeModels(null);
          for (const k of this.chunks.keys()) this.buildModels(k);
        });
        tex.wrapU = tex.wrapV = Texture.CLAMP_ADDRESSMODE;
        tex.anisotropicFilteringLevel = 4;
        this.modelPhotoMat.diffuseTexture = this.modelPhotoMat.emissiveTexture = tex;
      });
    }
    this.roadGeo = buildRoads(city, tuning, this.palette);

    this.tunnelShade = this.world(this.mesh('tunnel-shade', quadTris(4000, 0, rgba(tokens.colorWorldTunnelShade)), this.tunnelShadeMat, true, false), false);
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
    for (const m of this.nature.occluderMaterials) new OccluderFadePlugin(m, this.fade);
    this.ring = new FarRing({ scene, city, tuning, H: this.H, world: (m) => this.world(m, false) }, this.palette);
    this.applyClearColor();
    this.applyRisograph();
    this.instr = new SceneInstrumentation(scene);
  }

  /** Where the far ring reads `lod/` from (the pack source of the drive). */
  setPackSource(s: PackSource): void {
    this.ring.setSource(s);
  }

  get cameraMode(): CameraMode {
    return this.mode;
  }

  /** Switches the camera (specs/terrain.md "Upřesnění T2"): takes effect on the next frame, no rebuild. */
  setCameraMode(m: CameraMode): void {
    this.mode = m;
  }

  /** The chase view is drawn this frame. */
  get chase(): boolean {
    return this.chaseOn;
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

  private applyModelTextures(night: boolean): void {
    const pick = (t: { day: Texture; night: Texture }): Texture => (night ? t.night : t.day);
    this.modelStoneMat.diffuseTexture = this.modelStoneMat.emissiveTexture = pick(this.modelTextures.stone);
    this.modelRoofMat.diffuseTexture = this.modelRoofMat.emissiveTexture = pick(this.modelTextures.roof);
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
    if (mat === this.buildingMat || mat === this.modelStoneMat || mat === this.modelRoofMat || mat === this.modelPhotoMat) vd.uvs = new Float32Array(t.uv);
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
    this.bridgeMat.emissiveColor.set(f, f, f);
  }

  setNight(night: boolean): void {
    this.palette = night ? nightPalette : this.dayPalette;
    this.applyClearColor();
    this.applyRisograph();
    const tex = night ? this.textures.night : this.textures.day;
    this.buildingMat.diffuseTexture = tex;
    this.buildingMat.emissiveTexture = tex;
    this.applyModelTextures(night);
    for (const c of this.chunks.values()) this.disposeChunk(c.meshes);
    this.disposeModels(null);
    for (const [k, c] of this.chunks) {
      c.meshes = this.chunkMeshes(c.data, k);
      c.near = true;
      this.buildModels(k);
    }
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
    this.ring.setPalette(this.palette);
    if (this.chaseOn) this.nature.setFog(FOG_START_M, FOG_END_M, this.ring.fogColor);
  }

  // ---------- chunks

  private chunkMeshes(c: ChunkData, key: number): ChunkMeshes {
    const relief = this.relief && !!c.terrain;
    const flat = new Tris();
    const ter = new Tris();
    if (relief) {
      const hs = renderHeights(c, this.city.chunkM, this.tuning.terrain.pipeline.underwaterM);
      terrainTris(c, this.city.chunkM, this.palette.land, ter, hs);
      drapedGroundTris(c, this.palette, this.city.chunkM, flat, GROUND_ORDER, hs);
      // Green fills on the terrain, the bank line at the water level (specs/nature.md, specs/terrain.md).
      if (c.nature) {
        drapedGreenTris(c, c.nature, this.palette, this.city.chunkM, flat, hs);
        bankTris(c.nature, this.city.chunkM, this.palette, flat, true);
      }
    } else {
      groundTris(c, this.palette, flat);
      // Green fills and the bank line share the chunk's flat mesh (no extra draw call, specs/nature.md).
      if (c.nature) {
        greenTris(c.nature, this.palette, flat);
        bankTris(c.nature, this.city.chunkM, this.palette, flat);
      }
    }
    // Buildings a landmark model replaces go to their own meshes (specs/models.md).
    const replacedSets: [number, Set<number>][] = [];
    if (this.tuning.models.enabled) {
      this.city.models.forEach((m, i) => {
        const set = m.replaces.get(key);
        if (set && set.size > 0) replacedSets.push([i, set]);
      });
    }
    const kept = replacedSets.length === 0 ? c : { ...c, buildings: c.buildings.filter((_, j) => !replacedSets.some(([, set]) => set.has(j))) };
    const b = new Tris();
    buildingTris(kept, this.palette, this.tuning, b, this.relief);
    const sh = new Tris();
    // Cast shadows lie on the terrain: its height (own grid as fallback at the chunk's edge).
    const step = this.city.chunkM / (TERRAIN_N - 1);
    const own = c.terrain;
    const zAt = relief && own
      ? (x: number, y: number): number => this.city.terrain.terrainAt(x, y) ?? meshHeight(own, (x - c.x * this.city.chunkM) / step, (y - c.y * this.city.chunkM) / step)
      : null;
    const castShadows = cityFlag(this.tuning.style.castShadow, this.city.id, this.palette.night);
    if (castShadows) castShadowTris(kept, this.palette, this.tuning, sh, zAt);
    const replaced = new Map<number, { buildings: Mesh | null; shadows: Mesh | null }>();
    for (const [i, set] of replacedSets) {
      const part = { ...c, buildings: c.buildings.filter((_, j) => set.has(j)) };
      const rb = new Tris();
      buildingTris(part, this.palette, this.tuning, rb, this.relief);
      const rs = new Tris();
      if (castShadows) castShadowTris(part, this.palette, this.tuning, rs, zAt);
      let rsm: Mesh | null = null;
      if (!rs.empty) {
        rsm = this.world(this.mesh(`replaced-shadows-${key}-${i}`, rs, this.shadowMat, true), false);
        rsm.alphaIndex = 0;
      }
      replaced.set(i, { buildings: rb.empty ? null : this.world(this.mesh(`replaced-${key}-${i}`, rb, this.buildingMat), true), shadows: rsm });
    }
    let shadows: Mesh | null = null;
    if (!sh.empty) {
      shadows = this.world(this.mesh(`shadows-${key}`, sh, this.shadowMat, true), false);
      shadows.alphaIndex = 0;
    }
    return {
      terrain: ter.empty ? null : this.world(this.mesh(`terrain-${key}`, ter, this.terrainMat), false),
      flat: flat.empty ? null : this.world(this.mesh(`ground-${key}`, flat, this.flatMat), false),
      buildings: b.empty ? null : this.world(this.mesh(`buildings-${key}`, b, this.buildingMat), true),
      shadows,
      replaced,
    };
  }

  // ---------- landmark models (specs/models.md)

  /** Builds the meshes of the models whose home chunk is [key]. */
  private buildModels(key: number): void {
    if (!this.tuning.models.enabled) return;
    this.city.models.forEach((m, i) => {
      if (m.homeChunk !== key || this.modelMeshes.has(i)) return;
      const full = newModelTris();
      modelTris(m, this.palette, this.city.id, this.tuning, full, this.relief, this.photo?.model === m.landmarkId ? this.photo.parts : undefined);
      const plan = new Tris();
      planTris(m, this.palette, this.city.id, this.tuning, plan, this.relief);
      const sh = new Tris();
      const pal = this.palette;
      const sl = Math.hypot(pal.sunX, pal.sunY);
      if (pal.castShadow && sl > 1e-6 && cityFlag(this.tuning.style.castShadow, this.city.id, pal.night)) {
        const zAt = this.relief ? (x: number, y: number): number => this.city.terrain.terrainAt(x, y) ?? 0 : null;
        for (const b of planBuildings(m, this.relief)) {
          buildingShadow(b, shadowLength(b.height, this.tuning), -pal.sunX / sl, -pal.sunY / sl, Z.castShadow + (zAt ? DRAPE_LIFT + 0.3 : 0), pal.castShadow, sh, zAt);
        }
      }
      let shadows: Mesh | null = null;
      if (!sh.empty) {
        shadows = this.world(this.mesh(`model-shadows-${i}`, sh, this.shadowMat, true), false);
        shadows.alphaIndex = 0;
      }
      const mm: ModelMeshes = {
        full: ([[full.walls, this.buildingMat], [full.stone, this.modelStoneMat], [full.roofs, this.modelRoofMat], [full.photo, this.modelPhotoMat]] as const)
          .filter(([t]) => !t.empty)
          .map(([t, mat], j) => this.world(this.mesh(`model-${i}-${j}`, t, mat), true)),
        plan: plan.empty ? null : this.world(this.mesh(`model-plan-${i}`, plan, this.buildingMat), true),
        shadows,
      };
      for (const x of [...mm.full, mm.plan, mm.shadows]) x?.setEnabled(false);
      this.modelMeshes.set(i, mm);
    });
  }

  private disposeModels(key: number | null): void {
    for (const [i, mm] of this.modelMeshes) {
      if (key !== null && this.city.models[i]!.homeChunk !== key) continue;
      for (const x of [...mm.full, mm.plan, mm.shadows]) x?.dispose();
      this.modelMeshes.delete(i);
      this.modelsFull.delete(i);
    }
  }

  /**
   * Model or footprints (specs/models.md): in the chase view the nearest models within near_m (with
   * hysteresis) in full, from above the roof plan; the replaced buildings hide while a model is drawn.
   */
  private updateModels(): void {
    const models = this.city.models;
    if (models.length === 0) return;
    const t = this.tuning.models, car = this.drive.car;
    if (this.chaseOn && t.enabled) {
      const dists = models.map((m) => modelDistance(m, car.x, car.y));
      this.modelsFull = fullModels(dists, this.modelsFull, t.nearM, t.hysteresisM, t.maxFull);
    } else {
      this.modelsFull.clear();
    }
    for (let i = 0; i < models.length; i++) {
      const mm = this.modelMeshes.get(i);
      const full = !!mm && this.chaseOn && this.modelsFull.has(i);
      const plan = !!mm && !this.chaseOn;
      if (mm) {
        for (const x of mm.full) x.setEnabled(full);
        mm.plan?.setEnabled(plan);
        mm.shadows?.setEnabled(full || plan);
      }
      this.modelActive[i] = full || plan;
    }
    for (const e of this.chunks.values()) {
      for (const [i, r] of e.meshes.replaced) {
        const show = e.near && !this.modelActive[i];
        r.buildings?.setEnabled(show);
        r.shadows?.setEnabled(show);
      }
    }
  }

  addChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    if (this.chunks.has(key)) return;
    const bollards = bollardPoints(c, this.tuning.zones.bollardSpacingM);
    this.chunks.set(key, { data: c, meshes: this.chunkMeshes(c, key), bollards, near: true });
    this.buildModels(key);
    this.ring.setChunk(c.x, c.y, true);
    if (bollards.length > 0) this.bollardsDirty = true;
  }

  removeChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    const e = this.chunks.get(key);
    if (!e) return;
    this.disposeChunk(e.meshes);
    this.disposeModels(key);
    this.chunks.delete(key);
    this.ring.setChunk(c.x, c.y, false);
    if (e.bollards.length > 0) this.bollardsDirty = true;
  }

  private disposeChunk(m: ChunkMeshes): void {
    m.terrain?.dispose();
    m.flat?.dispose();
    m.buildings?.dispose();
    m.shadows?.dispose();
    for (const r of m.replaced.values()) {
      r.buildings?.dispose();
      r.shadows?.dispose();
    }
  }

  private disposeRoads(r: RoadMeshes): void {
    r.ground?.dispose();
    r.bridge?.dispose();
    r.tunnel?.dispose();
  }

  /**
   * Chase view (specs/terrain.md "Upřesnění T2"): a loaded chunk is drawn in detail only within
   * CHASE_NEAR_M of the car; beyond, its meshes and roads are off and the far ring draws it. From
   * above every loaded chunk is drawn.
   */
  private updateNear(): void {
    const cm = this.city.chunkM, car = this.drive.car;
    for (const [k, e] of this.chunks) {
      const c = e.data;
      const dx = Math.max(c.x * cm - car.x, 0, car.x - (c.x + 1) * cm), dy = Math.max(c.y * cm - car.y, 0, car.y - (c.y + 1) * cm);
      const near = !this.chaseOn || Math.hypot(dx, dy) <= CHASE_NEAR_M;
      if (near === e.near) continue;
      e.near = near;
      for (const m of [e.meshes.terrain, e.meshes.flat, e.meshes.buildings, e.meshes.shadows]) m?.setEnabled(near);
      const r = this.roads.get(k);
      if (r) for (const m of [r.ground, r.bridge]) m?.setEnabled(near);
      this.ring.setChunk(c.x, c.y, near);
    }
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
        // Chase view: roads only where the chunk is drawn in detail (the far ring draws the rest).
        if (this.chaseOn && !this.chunks.get(k)?.near && this.city.hasChunk(cx, cy)) continue;
        const have = this.roads.get(k);
        // Relief: ground roads get the hillshade once the chunk's terrain grid is there.
        if (have && (have.shaded || !this.relief || !this.city.terrain.hasGrid(cx, cy))) continue;
        const g = this.roadGeo.get(k);
        if (have) {
          have.ground?.dispose();
          have.ground = this.roadGround(k, g);
          have.shaded = true;
          continue;
        }
        const m: RoadMeshes = {
          shaded: this.relief && this.city.terrain.hasGrid(cx, cy),
          ground: this.roadGround(k, g),
          bridge: g && !g.bridge.empty ? this.world(this.mesh(`bridges-${k}`, g.bridge, this.bridgeMat), true) : null,
          tunnel: g && !g.tunnel.empty ? this.world(this.mesh(`tunnels-${k}`, g.tunnel, this.roadMat), false) : null,
        };
        if (m.tunnel) m.tunnel.renderingGroupId = 1;
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

  /** Ground roads of one chunk key; on relief their colours × the terrain's hillshade. */
  private roadGround(k: number, g: RoadChunk | undefined): Mesh | null {
    if (!g || g.ground.empty) return null;
    const m = this.world(this.mesh(`roads-${k}`, g.ground, this.roadMat), false);
    if (!this.relief) return m;
    const pos = g.ground.pos, col = new Float32Array(g.ground.col);
    const ter = this.city.terrain;
    for (let i = 0, v = 0; i < pos.length; i += 3, v += 4) {
      const f = shadeFactor(ter.shadeAt(pos[i]!, pos[i + 2]!));
      col[v] = Math.min(1, col[v]! * f);
      col[v + 1] = Math.min(1, col[v + 1]! * f);
      col[v + 2] = Math.min(1, col[v + 2]! * f);
    }
    m.setVerticesData(VertexBuffer.ColorKind, col, false);
    return m;
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
    // Chase view: the body is a box CHASE_BODY_M tall (the flat top drawing on its roof), so the hop's
    // roll reads in 3D; the sides in the paint, darkened. Off from above.
    const sideT = new Tris();
    const paint = rgba(lookPaint(car.spec, look));
    const sideC: Rgba = [paint[0] * 0.55, paint[1] * 0.55, paint[2] * 0.55, 1];
    const corners = [[-hl, -hw], [hl, -hw], [hl, hw], [-hl, hw]] as const;
    for (let i = 0; i < 4; i++) {
      const [ax, ay] = corners[i]!, [bx, by] = corners[(i + 1) % 4]!;
      const v0 = sideT.vertex(ax, ay, 0, sideC), v1 = sideT.vertex(bx, by, 0, sideC);
      const v2 = sideT.vertex(bx, by, CHASE_BODY_M, sideC), v3 = sideT.vertex(ax, ay, CHASE_BODY_M, sideC);
      sideT.idx.push(v0, v2, v1, v0, v3, v2);
    }
    const sides = this.mesh('car-sides', sideT, this.flatMat, false, false);
    sides.parent = lift;
    sides.setEnabled(false);

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
      // Tyre and rim of an own car, or its garage wheel sprite (specs/garage.md v2 "wheels").
      wheelPrims(r, look, cx, cy).forEach((p, i) => polyTris(tyre, 0, 0, 0, p.poly, wz + (i > 0 ? 0.005 : 0), p.color));
      const w = new TransformNode('wheel', this.scene);
      w.parent = root;
      w.position.set(cx, 0, cy);
      this.mesh('tyre', tyre, this.flatMat, false, false).parent = w;
      if (r.front) wheels.push(w);
    }
    this.carParts = { wheels, brake, reverse, cone: coneMesh, root: holder, lights: !micro, lift, top: root, under, shadow: shadowNode, glow,
      spriteLights, topH: top, sides, chase: null };
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
    // Parked cars stand on the ground layer; on relief each mesh piece is moved to its car's height.
    const t = parkedTris(f.parked, f.specs, this.tuning.carScale, this.tuning.drive.axleOffset, Z.car, this.palette.shadow,
      lookOf, glow, sp ? (p, look) => sp.has(p.carId, look?.decal ?? 0) : null,
      this.relief ? (p) => baseHeight(this.city.terrain, p.x, p.y, 0, 0) : null);
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
      m.setTranslationFromFloats(p.x, baseHeight(this.city.terrain, p.x, p.y, 0, 0) + Z.car, p.y);
      const hl = (s.length_m * scale) / 2, hw = (s.width_m * scale) / 2;
      sp.add('parked', {
        id: p.carId, decal, world: m, len: (px.h / 32) * scale, wid: (px.w / 32) * scale, hl, hw, axle: hl * this.tuning.drive.axleOffset,
        paint: rgba(look ? lookPaint(s, look) : paintHex(s.paint)), steer: 0,
        wheelTint: look && (look.wheels ?? 0) > 0 ? rgba(lookRim(look)) : null, wheel: look?.wheels ?? 0, lights: LIGHTS_OFF,
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
    // Relief: the body at z (specs/terrain.md "Skok"); flat pack: bridges at deck_lift_m.
    const j = this.drive.jump;
    const lift = this.relief ? j.z + VEHICLE_LIFT : car.layer > 0 ? this.tuning.layers.deckLiftM * car.layer : 0;
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
      wheelTint: look && (look.wheels ?? 0) > 0 ? rgba(lookRim(look)) : null, wheel: look?.wheels ?? 0,
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
    if (p.chase !== this.chaseOn) {
      // Chase view: the top drawing on the box's roof, the underside plate turned to face down at its
      // floor, the roll about the box's middle. From above: flat as before.
      const c = (p.chase = this.chaseOn);
      p.top.position.y = c ? CHASE_BODY_M : 0;
      p.under.rotation.x = c ? Math.PI : 0;
      p.under.position.y = c ? p.topH : 0;
      p.sides.setEnabled(c);
      p.lift.setPivotPoint(new Vector3(0, c ? (CHASE_BODY_M + p.topH) / 2 : p.topH / 2, 0));
    }
    if (this.chaseOn) {
      // Chase view (specs/terrain.md "Upřesnění T2"): a real 3D arc hopArc(t) metres over the ride
      // surface and a real roll about the long axis, no scale tricks.
      p.lift.position.y = arc;
      p.lift.scaling.z = 1;
      p.lift.rotation.x = hop.airborne ? hopRoll(hop.t, ht.airS, ht.flips) : 0;
    } else {
      p.lift.position.y = displayHeight(s, this.H);
      p.lift.scaling.z = Math.abs(flip);
      p.lift.rotation.x = 0;
    }
    // Terrain jump (specs/terrain.md): the shadow stays on the ground under the body, shrinks by
    // 1 / (1 + gap / 4) and slides away from the sun with the gap.
    const gap = this.relief ? this.drive.jump.gap : 0;
    // Chase view: the hop height counts like a terrain gap (shrink 1 / (1 + h / 4), slide from the sun).
    const air = this.chaseOn ? gap + arc : gap;
    const k = shadowScale(air);
    p.shadow.scaling.x = p.shadow.scaling.z = this.chaseOn ? k : k / s;
    const sl = Math.hypot(this.palette.sunX, this.palette.sunY);
    const ox = sl > 1e-6 ? (-this.palette.sunX / sl) * air : 0, oy = sl > 1e-6 ? (-this.palette.sunY / sl) * air : 0;
    const hd = this.drive.car.heading, c = Math.cos(hd), sn = Math.sin(hd);
    // Local frame of the car (Babylon x = forward, z = left as world y rotated by −heading).
    p.shadow.position.set(ox * c + oy * sn, -gap, -ox * sn + oy * c);
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
        const zb = this.relief ? baseHeight(this.city.terrain, p.x, p.y, 0, 0) : 0;
        Matrix.ComposeToRef(new Vector3(s, 1, s), rotY(-(p.angle + p.rot)), new Vector3(x, zb + Z.props, y), m);
        list.push(...m.m);
        if (p.kind === 'lamp' && !p.knocked) {
          Matrix.ComposeToRef(new Vector3(s, 1, s), rotY(0), new Vector3(x, zb + Z.props - 0.01, y), m);
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
          buf[o + 13] = this.relief ? baseHeight(this.city.terrain, p[i]!, p[i + 1]!, 0, 0) : 0;
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
      const z = Z.skids + (this.relief ? (d.skidZ[i] ?? 0) + VEHICLE_LIFT - 0.1 : 0);
      out.set([x0 + nx, z, y0 + ny, x1 + nx, z, y1 + ny, x1 - nx, z, y1 - ny, x0 - nx, z, y0 - ny], 12 * i);
    }
    this.skidMesh.updateVerticesData(VertexBuffer.PositionKind, out, false, false);
  }

  // ---------- frame

  /** Off-axis projection: the car sits at car_anchor without moving the camera (DUALSTACK 6.2). */
  private updateCamera(): void {
    const chase = this.mode === 'chase' && !this.chaseSuspended;
    if (chase !== this.chaseOn) this.switchCamera(chase);
    if (chase) {
      this.updateChase();
      return;
    }
    const cam = this.camera, rig = this.rig, t = this.tuning;
    // Straight above the car at z_ref + H (specs/terrain.md), with the shake offset.
    const cx = rig.x + rig.shakeX, cy = rig.y + rig.shakeY;
    cam.position.set(cx, rig.z + this.H, cy);
    cam.upVector.set(Math.cos(rig.heading), 0, Math.sin(rig.heading));
    cam.setTarget(new Vector3(cx, rig.z, cy));
    cam.fov = fovX(rig.viewWidth * rig.zoom, this.H);
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
      top.setTarget(new Vector3(cx, rig.z, cy));
      top.fov = cam.fov;
      top.freezeProjectionMatrix(this.proj);
    }
  }

  /** Near and far planes, fog, fade and the overlay projection of the active mode. */
  private switchCamera(chase: boolean): void {
    this.chaseOn = chase;
    const cams = [this.camera, this.topCamera];
    for (const c of cams) {
      c.minZ = chase ? 2 : this.H * 0.25;
      c.maxZ = chase ? SKY_R * 1.2 : this.H * 3;
      c.upVector.set(0, 1, 0);
      c.fovMode = TargetCamera.FOVMODE_HORIZONTAL_FIXED;
      c.unfreezeProjectionMatrix();
    }
    // Fog only on the far ring and the water plane: the near world ends before the fog starts.
    this.fade.on = chase;
    this.nature.setChase(chase);
    this.nature.setFog(chase ? FOG_START_M : 1e6, chase ? FOG_END_M : 2e6, this.ring.fogColor);
    this.rig.project = chase ? (x, y, z, w, h) => this.projectChase(x, y, z, w, h) : null;
    if (!chase) this.pose = null;
  }

  /**
   * Chase camera (specs/terrain.md "Upřesnění T2"): behind the car along the rig's smoothed heading,
   * the relief zoom-out stretches it, the landing shake moves eye and target.
   */
  private updateChase(): void {
    const cam = this.camera, rig = this.rig, t = this.tuning, car = this.drive.car;
    const ground = this.relief ? (x: number, y: number): number | null => this.city.terrain.terrainAt(x, y) : null;
    const p = (this.pose = chasePose(car.x + rig.shakeX, car.y + rig.shakeY, rig.z, rig.heading, t.camera.chase, rig.zoom, ground));
    const w = this.engine.getRenderWidth(), h = this.engine.getRenderHeight();
    const f = chaseFov(t.camera.chase, w, h);
    const target = new Vector3(p.target.x, p.target.z, p.target.y);
    for (const c of this.riso ? [cam, this.topCamera] : [cam]) {
      c.fovMode = f.horizontal ? TargetCamera.FOVMODE_HORIZONTAL_FIXED : TargetCamera.FOVMODE_VERTICAL_FIXED;
      c.fov = f.fov;
      c.position.set(p.eye.x, p.eye.z, p.eye.y);
      c.setTarget(target);
    }
    const lift = this.carRoot.position.y;
    this.fade.eye = [p.eye.x, p.eye.z, p.eye.y];
    this.fade.car = [car.x, lift + 1, car.y];
    cam.getViewMatrix(true).multiplyToRef(cam.getProjectionMatrix(true), this.viewProj);
  }

  /**
   * World point → CSS pixels through the chase camera. Overlay icons and labels sit on the near
   * world only: a point further than CHASE_NEAR_M from the car gives NaN, which the 2D canvas skips
   * (no icon, the route line ends there). Behind the eye → below the screen, left or right.
   */
  private projectChase(x: number, y: number, z: number, w: number, h: number): { x: number; y: number } {
    const car = this.drive.car;
    if (Math.hypot(x - car.x, y - car.y) > CHASE_NEAR_M) return { x: NaN, y: NaN };
    const m = this.viewProj.m;
    const cx = x * m[0]! + z * m[4]! + y * m[8]! + m[12]!;
    const cy = x * m[1]! + z * m[5]! + y * m[9]! + m[13]!;
    const cw = x * m[3]! + z * m[7]! + y * m[11]! + m[15]!;
    if (cw < 0.5) return { x: cx < 0 ? -w : 2 * w, y: 4 * h };
    return { x: ((cx / cw + 1) / 2) * w, y: ((1 - cy / cw) / 2) * h };
  }

  /**
   * Relief camera (specs/terrain.md): z_ref follows the ground under the car at rate 2/s; a short
   * zoom-out (× 1.15 for 0.4 s) at the start of a jump and on a hard landing, which also shakes.
   */
  private updateRelief(): void {
    const now = performance.now();
    const dt = this.reliefFrame > 0 ? Math.min((now - this.reliefFrame) / 1000, 0.1) : 0;
    this.reliefFrame = now;
    const rig = this.rig, d = this.drive;
    if (!this.relief) return;
    const g = d.jump.z - d.jump.gap;
    // A teleport (respawn, rescue, metro) snaps z_ref instead of gliding.
    const moved = Math.hypot(d.car.x - this.lastCarX, d.car.y - this.lastCarY) > 60;
    this.lastCarX = d.car.x;
    this.lastCarY = d.car.y;
    rig.z = dt === 0 || moved ? g : rig.z + (g - rig.z) * (1 - Math.exp(-TERRAIN_SPEC.zRefRate * dt));
    const pulse = (t0: number): number => {
      const a = (d.time - t0) / TERRAIN_SPEC.zoomOutS;
      return a >= 0 && a < 1 ? Math.sin(Math.PI * a) : 0;
    };
    rig.zoom = 1 + (TERRAIN_SPEC.zoomOut - 1) * Math.max(pulse(d.takeoffAt), pulse(d.hardLandingAt));
    const sh = d.time - d.hardLandingAt;
    if (sh >= 0 && sh < TERRAIN_SPEC.shakeS) {
      const amp = 0.8 * (1 - sh / TERRAIN_SPEC.shakeS);
      rig.shakeX = amp * Math.sin(now * 0.09);
      rig.shakeY = amp * Math.cos(now * 0.11);
    } else {
      rig.shakeX = rig.shakeY = 0;
    }
  }

  /** Snaps z_ref to the ground under the car (teleports). */
  snapRelief(): void {
    this.rig.z = this.drive.jump.z - this.drive.jump.gap;
  }

  /** In a tunnel, everything but the world layer draws in group 1 (after the depth clear). */
  private tunnelGroups(tunnel: boolean): void {
    for (const m of this.scene.meshes) {
      if ((m.layerMask & WORLD_LAYER) !== 0 && (m.layerMask & ~(WORLD_LAYER | DEPTH_LAYER)) === 0) continue;
      if (tunnel ? m.renderingGroupId === 0 : m.renderingGroupId === 1) m.renderingGroupId = tunnel ? 1 : 0;
    }
  }

  render(): void {
    const car = this.drive.car;
    const tunnel = car.layer < 0;
    this.updateRelief();
    if (tunnel !== this.inTunnel) {
      this.inTunnel = tunnel;
      this.tunnelShade.setEnabled(tunnel);
      for (const r of this.roads.values()) r.tunnel?.setEnabled(tunnel);
      for (const m of [this.buildingMat, this.modelStoneMat, this.modelRoofMat, this.modelPhotoMat]) m.alpha = tunnel ? 90 / 255 : 1;
      this.updateTopMask();
      if (!tunnel) this.tunnelGroups(false);
    }
    if (tunnel) {
      // Above everything around (sorted last among the alpha meshes), drawn with depth ALWAYS.
      // From above half way up to the camera; in the chase view just under the eye.
      const zs = this.chaseOn && this.pose ? this.pose.eye.z - 2 : this.rig.z + this.H * 0.5;
      this.tunnelShade.position.set(this.rig.x, zs, this.rig.y);
      this.tunnelGroups(true);
    }
    this.updateCar(car);
    this.updateCamera();
    this.updateNear();
    this.updateModels();
    this.updateRoads();
    this.updateProps();
    this.updateBollards();
    this.updateParked();
    this.updateSkids(car.halfWidth * 0.32);
    const now = performance.now();
    this.nature.update(car.x, car.y, this.lastFrame > 0 ? Math.min(0.1, (now - this.lastFrame) / 1000) : 0);
    this.lastFrame = now;
    const e = this.pose?.eye;
    this.ring.update(this.chaseOn, car.x, car.y, e?.x ?? 0, e?.y ?? 0, e?.z ?? 0, (t) => this.mesh('far-ring', t, this.flatMat));
    if (e) this.nature.setEye(e.x, e.y, e.z);
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

