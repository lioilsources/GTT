import { Material } from '@babylonjs/core/Materials/material';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Color3 } from '@babylonjs/core/Maths/math.color';
import { Matrix } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import type { Scene } from '@babylonjs/core/scene';
import '@babylonjs/core/Meshes/thinInstanceMesh';

import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import { LIGHT_AMBER, LIGHT_GREEN } from '../traffic/roadRules';
import type { Traffic } from '../traffic/traffic';
import { Tris, Z } from './geometry';
import { rgba, type Rgba } from './palette';
import { setCount, setShadowColour } from './shadow';
import { LIGHTS_BRAKE, LIGHTS_FULL, LIGHTS_OFF, type CarSpriteView } from './carSprites';
import { stretchedSize, TRAFFIC_SPRITE } from '../cars/sprites';

/**
 * Traffic cars and traffic-light indicators (specs/traffic.md "Kreslení"): thin instances with
 * preallocated buffers, so a frame allocates nothing; five draw calls in total.
 */
export class TrafficView {
  private readonly mat: StandardMaterial;
  private readonly paint: Mesh;
  private readonly details: Mesh;
  private readonly brake: Mesh;
  private readonly housing: Mesh;
  private readonly lamp: Mesh;
  private readonly carM: Float32Array;
  private readonly carC: Float32Array;
  private readonly brakeM: Float32Array;
  private readonly housingM: Float32Array;
  private readonly lampM: Float32Array;
  private readonly lampC: Float32Array;
  private readonly bodies: Rgba[];
  private readonly lightCols: Rgba[];
  private readonly m = Matrix.Identity();
  /** Car sprites (specs/art.md v2): once `traffic_sedan` is in the atlas the cars draw through it. */
  private sprites: CarSpriteView | null = null;
  private spriteOn = false;
  private shadowCol: Rgba = rgba(tokens.colorCarShadow);
  private readonly shadowOnly: Tris;

  constructor(
    scene: Scene,
    readonly traffic: Traffic,
    readonly tuning: Tuning,
  ) {
    const m = (this.mat = new StandardMaterial('traffic', scene));
    m.disableLighting = true;
    m.emissiveColor = Color3.White();
    m.diffuseColor = Color3.Black();
    m.specularColor = Color3.Black();
    m.sideOrientation = Material.ClockWiseSideOrientation;

    const t = tuning.traffic;
    const hl = (t.carLengthM * tuning.carScale) / 2, hw = (t.carWidthM * tuning.carScale) / 2;
    const white: Rgba = [1, 1, 1, 1];
    const paint = new Tris();
    paint.rect(0, 0, 0, -hl, -hw, hl, hw, 0.02, white);
    const det = new Tris();
    det.rect(0, 0, 0, -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6, -0.02, rgba(tokens.colorCarShadow));
    det.rect(0, 0, 0, -hl * 0.42, -hw * 0.78, hl * 0.3, hw * 0.78, 0.03, rgba(tokens.colorCarCabin));
    const head = rgba(tokens.colorCarHeadlightDay), tail = rgba(tokens.colorCarTail);
    det.rect(0, 0, 0, hl * 0.9, hw * 0.5, hl, hw * 0.85, 0.05, head);
    det.rect(0, 0, 0, hl * 0.9, -hw * 0.85, hl, -hw * 0.5, 0.05, head);
    det.rect(0, 0, 0, -hl, hw * 0.5, -hl * 0.92, hw * 0.85, 0.05, tail);
    det.rect(0, 0, 0, -hl, -hw * 0.85, -hl * 0.92, -hw * 0.5, 0.05, tail);
    // Sprite mode: the details mesh keeps only the procedural ground shadow (specs/art.md "Stín").
    this.shadowOnly = new Tris();
    this.shadowOnly.rect(0, 0, 0, -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6, -0.02, rgba(tokens.colorCarShadow));
    const br = new Tris();
    const brakeCol = rgba(tokens.colorCarBrake);
    br.rect(0, 0, 0, -hl, hw * 0.5, -hl * 0.92, hw * 0.85, 0.06, brakeCol);
    br.rect(0, 0, 0, -hl, -hw * 0.85, -hl * 0.92, -hw * 0.5, 0.06, brakeCol);
    const hous = new Tris();
    hous.disc(0, 0, 1.45, 0, rgba(tokens.colorTrafficLightHousing), 12);
    const lamp = new Tris();
    lamp.disc(0, 0, 1, 0.01, white, 12);

    const n = t.maxCars, nl = t.lightDrawMax;
    this.paint = this.mesh(scene, 'traffic-paint', paint, false);
    this.details = this.mesh(scene, 'traffic-details', det, true);
    this.brake = this.mesh(scene, 'traffic-brake', br, false);
    this.housing = this.mesh(scene, 'traffic-light-housing', hous, false);
    this.lamp = this.mesh(scene, 'traffic-light-lamp', lamp, false);
    this.carM = new Float32Array(n * 16);
    this.carC = new Float32Array(n * 4).fill(1);
    this.brakeM = new Float32Array(n * 16);
    this.housingM = new Float32Array(nl * 16);
    this.lampM = new Float32Array(nl * 16);
    this.lampC = new Float32Array(nl * 4).fill(1);
    this.paint.thinInstanceSetBuffer('matrix', this.carM, 16, false);
    this.paint.thinInstanceSetBuffer('color', this.carC, 4, false);
    this.details.thinInstanceSetBuffer('matrix', this.carM, 16, false);
    this.brake.thinInstanceSetBuffer('matrix', this.brakeM, 16, false);
    this.housing.thinInstanceSetBuffer('matrix', this.housingM, 16, false);
    this.lamp.thinInstanceSetBuffer('matrix', this.lampM, 16, false);
    this.lamp.thinInstanceSetBuffer('color', this.lampC, 4, false);
    for (const mesh of [this.paint, this.details, this.brake, this.housing, this.lamp]) setCount(mesh, 0);
    this.bodies = tokens.colorTrafficBodies.map((c) => rgba(c));
    this.lightCols = [rgba(tokens.colorTrafficLightGreen), rgba(tokens.colorTrafficLightAmber), rgba(tokens.colorTrafficLightRed)];
  }

  private mesh(scene: Scene, name: string, t: Tris, alpha: boolean): Mesh {
    const mesh = new Mesh(name, scene);
    const vd = new VertexData();
    vd.positions = new Float32Array(t.pos);
    vd.colors = new Float32Array(t.col);
    vd.indices = new Uint16Array(t.idx);
    vd.applyToMesh(mesh, false);
    mesh.material = this.mat;
    mesh.hasVertexAlpha = alpha;
    mesh.isPickable = false;
    mesh.alwaysSelectAsActiveMesh = true;
    return mesh;
  }

  /** Ground shadow colour (the city skin's `shadow` by day, specs/style.md); the first rect of the details. */
  setShadow(c: Rgba): void {
    this.shadowCol = c;
    setShadowColour(this.details, 4, c);
  }

  setSprites(sp: CarSpriteView): void {
    this.sprites = sp;
  }

  private useSprite(): void {
    this.spriteOn = true;
    const vd = new VertexData();
    vd.positions = new Float32Array(this.shadowOnly.pos);
    vd.colors = new Float32Array(this.shadowOnly.col);
    vd.indices = new Uint16Array(this.shadowOnly.idx);
    vd.applyToMesh(this.details, false);
    setShadowColour(this.details, 4, this.shadowCol);
  }

  /** Writes the instance buffers; call once per frame before scene.render. */
  update(viewX: number, viewY: number, viewRadius: number, playerLayer: number): void {
    const tr = this.traffic, t = this.tuning;
    const lift = t.layers.deckLiftM;
    const inTunnel = playerLayer < 0;
    let n = 0, nb = 0;
    const sp = this.sprites;
    if (!this.spriteOn && sp?.has(TRAFFIC_SPRITE)) this.useSprite();
    const sprite = this.spriteOn && sp !== null;
    const spriteLights = sprite && sp.hasLights(TRAFFIC_SPRITE);
    const size = stretchedSize(t.traffic.carLengthM, t.traffic.carWidthM, t.carScale);
    const hl = (t.traffic.carLengthM * t.carScale) / 2, hw = (t.traffic.carWidthM * t.carScale) / 2;
    if (sprite) sp.begin('traffic');
    for (const c of tr.cars) {
      // Patrols are drawn by police/view.ts.
      if (c.layer < 0 !== inTunnel || c.police) continue;
      const h = (c.layer > 0 ? lift * c.layer : 0) + Z.car;
      // Babylon rotates about +Y clockwise seen from above; world headings are CCW.
      Matrix.RotationYToRef(-c.heading, this.m);
      this.m.setTranslationFromFloats(c.x, h, c.y);
      this.m.copyToArray(this.carM, 16 * n);
      this.carC.set(this.bodies[c.colour % this.bodies.length]!, 4 * n);
      const braking = c.braking || c.hitTimer > 0;
      if (sprite) {
        sp.add('traffic', {
          id: TRAFFIC_SPRITE, decal: 0, world: this.m, len: size.len, wid: size.wid, hl, hw, axle: hl * t.drive.axleOffset,
          paint: this.bodies[c.colour % this.bodies.length]!, steer: 0, wheelTint: null,
          lights: !spriteLights ? LIGHTS_OFF : tr.night ? LIGHTS_FULL : braking ? LIGHTS_BRAKE : LIGHTS_OFF,
        });
      }
      if (braking && !spriteLights) this.m.copyToArray(this.brakeM, 16 * nb++);
      n++;
    }
    setCount(this.paint, sprite ? 0 : n);
    setCount(this.details, n);
    setCount(this.brake, nb);
    this.paint.thinInstanceBufferUpdated('matrix');
    this.paint.thinInstanceBufferUpdated('color');
    this.details.thinInstanceBufferUpdated('matrix');
    this.brake.thinInstanceBufferUpdated('matrix');

    let nl = 0;
    if (!inTunnel) {
      const ap = tr.signals.approaches;
      const r2 = viewRadius * viewRadius, max = t.traffic.lightDrawMax, s = t.traffic.lightRadiusM;
      for (let a = 0; a < ap.length && nl < max; a++) {
        const p = ap[a]!;
        const dx = p.x - viewX, dy = p.y - viewY;
        if (dx * dx + dy * dy > r2) continue;
        writeScaled(this.housingM, 16 * nl, s, p.x, Z.props + 0.02, p.y);
        writeScaled(this.lampM, 16 * nl, s * 0.7, p.x, Z.props + 0.03, p.y);
        const state = tr.light(a);
        this.lampC.set(this.lightCols[state === LIGHT_GREEN ? 0 : state === LIGHT_AMBER ? 1 : 2]!, 4 * nl);
        nl++;
      }
    }
    setCount(this.housing, nl);
    setCount(this.lamp, nl);
    this.housing.thinInstanceBufferUpdated('matrix');
    this.lamp.thinInstanceBufferUpdated('matrix');
    this.lamp.thinInstanceBufferUpdated('color');
  }

  dispose(): void {
    for (const mesh of [this.paint, this.details, this.brake, this.housing, this.lamp]) mesh.dispose();
    this.mat.dispose();
  }
}

/** Uniform XZ scale and translation into a column of a matrix buffer. */
function writeScaled(buf: Float32Array, o: number, s: number, x: number, h: number, y: number): void {
  buf.fill(0, o, o + 16);
  buf[o] = s;
  buf[o + 5] = 1;
  buf[o + 10] = s;
  buf[o + 12] = x;
  buf[o + 13] = h;
  buf[o + 14] = y;
  buf[o + 15] = 1;
}
