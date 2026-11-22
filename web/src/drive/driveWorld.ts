import { Body, Chain, Polygon, World, type Vec2Value } from 'planck';

import type { CarSpec } from '../gen/schema';
import type { Tuning, TuningLayers } from '../gen/tuning';
import type { ChunkData } from '../world/chunk';
import { chunkKey, type City, type EdgeHit, type RoadEdge, type RoadGraph } from '../world/model';
import { CAT_BUILDINGS, CAT_CAR, CAT_PARKED, CAT_TRAFFIC, Car } from './car';
import { ControlInput } from './controls';
import { generateProps, type Prop, type PropSet } from './props';
import { Traffic } from '../traffic/traffic';

/**
 * Tracks which road edge the car is on, and with it the layer (−1 tunnel, 0, +1 bridge).
 * The car only changes to an edge that shares a node with its current edge (specs/drive.md 6).
 */
export class LayerTracker {
  edge: RoadEdge | null = null;
  hit: EdgeHit | null = null;

  constructor(
    readonly graph: RoadGraph,
    readonly t: TuningLayers,
  ) {}

  get layer(): number {
    return this.hit === null ? 0 : this.hit.edge.layerAt(this.hit.t);
  }

  reset(x: number, y: number): void {
    this.hit = this.graph.nearest(x, y, this.t.spawnSearchM, (e) => e.isGround);
    this.edge = this.hit?.edge ?? null;
  }

  update(x: number, y: number): void {
    const cur = this.edge;
    const cands = this.graph.near(x, y, this.t.searchM);
    const onIt = (h: EdgeHit): boolean => h.dist <= h.edge.width / 2 + this.t.switchMarginM;
    let best: EdgeHit | null = null;
    if (cur !== null) {
      const adj = new Set(this.graph.neighbours(cur.index));
      for (const h of cands) {
        if (!adj.has(h.edge.index) || !onIt(h)) continue;
        if (best === null || h.dist < best.dist) best = h;
      }
    }
    if (best === null) {
      // Off our edge's neighbourhood: re-acquire, staying on the current layer.
      const l = this.layer;
      for (const h of cands) {
        if (h.edge.layerAt(h.t) !== l || !onIt(h)) continue;
        if (best === null || h.dist < best.dist) best = h;
      }
    }
    if (best !== null) {
      this.edge = best.edge;
      this.hit = best;
    } else if (cur !== null) {
      // Off-road (plaza, sidewalk): keep the edge, refresh the projection.
      let h: EdgeHit | null = null;
      for (let s = 0; s + 1 < cur.pointCount; s++) {
        const p = this.graph.project(cur, s, x, y);
        if (h === null || p.dist < h.dist) h = p;
      }
      this.hit = h;
    }
  }
}

/** Physics for M0: one car, building colliders, layers, knockable street furniture. No UI. */
export class DriveWorld {
  readonly world: World;
  car: Car;
  readonly layers: LayerTracker;
  readonly input = new ControlInput();
  readonly props = new Map<number, PropSet>();
  private readonly colliders = new Map<number, Body>();
  time = 0;
  private acc = 0;
  knockedCount = 0;
  /** Bumped when the prop set changes (chunk added or removed). */
  propsVersion = 0;

  /** Skid marks: x0, y0, x1, y1 per segment, newest last. */
  readonly skids: number[] = [];
  private lastSkid: [number, number, number, number] | null = null;
  skidsVersion = 0;
  /** Called before every fixed step (the benchmark autopilot sets the input here). */
  beforeStep: ((step: number) => void) | null = null;
  /** AI traffic and lights (specs/traffic.md); null when traffic.enabled is off. */
  readonly traffic: Traffic | null;

  constructor(
    readonly city: City,
    public spec: CarSpec,
    readonly tuning: Tuning,
  ) {
    this.world = new World({ gravity: { x: 0, y: 0 } });
    this.layers = new LayerTracker(city.graph, tuning.layers);
    this.car = this.makeCar(city.startX, city.startY, city.startHeading);
    this.layers.reset(this.car.x, this.car.y);
    this.car.setLayer(this.layers.layer);
    this.traffic = tuning.traffic.enabled ? new Traffic(this.world, city, tuning) : null;
  }

  private makeCar(x: number, y: number, h: number): Car {
    return new Car(this.world, this.spec, this.tuning.drive, x, y, h, this.tuning.carScale);
  }

  spawn(x: number, y: number, heading: number): void {
    this.car.destroy();
    this.car = this.makeCar(x, y, heading);
    this.layers.reset(x, y);
    this.car.setLayer(this.layers.layer);
    this.lastSkid = null;
  }

  /** Switches to another car (specs/cars.md): a new body with that car's parameters, at rest. */
  replaceCar(spec: CarSpec, x: number, y: number, heading: number): void {
    this.spec = spec;
    this.spawn(x, y, heading);
  }

  addChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    if (this.colliders.has(key)) return;
    const d = this.tuning.drive;
    const body = this.world.createBody({ type: 'static' });
    const opt = {
      friction: d.buildingFriction,
      restitution: d.buildingRestitution,
      filterCategoryBits: CAT_BUILDINGS,
      filterMaskBits: CAT_CAR | CAT_PARKED | CAT_TRAFFIC, // pushed parked and loose traffic cars stop at walls
    };
    for (const b of c.buildings) {
      if (!b.collide) continue;
      let start = 0;
      for (const end of b.ringEnds) {
        const pts: Vec2Value[] = [];
        for (let i = start; i < end; i++) {
          const p = { x: b.xy[2 * i]!, y: b.xy[2 * i + 1]! };
          const q = pts[pts.length - 1];
          // planck rejects nearly coincident chain vertices.
          if (q === undefined || Math.hypot(p.x - q.x, p.y - q.y) > 0.01) pts.push(p);
        }
        const first = pts[0], last = pts[pts.length - 1];
        if (first && last && pts.length > 1 && Math.hypot(first.x - last.x, first.y - last.y) <= 0.01) pts.pop();
        start = end;
        try {
          if (pts.length >= 4) body.createFixture({ shape: new Chain(pts, true), ...opt });
          else if (pts.length === 3) body.createFixture({ shape: new Polygon(pts), ...opt });
        } catch {
          // Degenerate ring (collinear points); skip it like client F.
        }
      }
    }
    this.colliders.set(key, body);
    this.props.set(key, generateProps(this.city.graph, c.x, c.y, this.tuning));
    this.propsVersion++;
  }

  removeChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    const body = this.colliders.get(key);
    if (body) this.world.destroyBody(body);
    this.colliders.delete(key);
    if (this.props.delete(key)) this.propsVersion++;
  }

  /** Advances with a fixed step (drive.step_hz). */
  update(dt: number): void {
    const step = 1 / this.tuning.drive.stepHz;
    this.acc = Math.min(this.acc + dt, step * 6);
    while (this.acc >= step) {
      this.acc -= step;
      this.fixedStep(step);
    }
  }

  private fixedStep(step: number): void {
    const d = this.tuning.drive;
    this.time += step;
    this.beforeStep?.(step);
    this.car.drive(this.input, step, this.tuning.speedMps.cruise, this.tuning.speedMps.topDefault);
    this.traffic?.preStep(step, this.car);
    this.world.step(step, d.velocityIterations, d.positionIterations);
    this.layers.update(this.car.x, this.car.y);
    this.car.setLayer(this.layers.layer);
    this.traffic?.postStep(this.car);
    if (this.car.layer !== 0) this.rails();
    this.stepProps(step);
    this.skidMarks();
  }

  /** Keeps the car on bridge decks and in tunnels. */
  private rails(): void {
    const h = this.layers.hit;
    if (h === null || h.dist === 0) return;
    const car = this.car;
    const limit = Math.max(0, h.edge.width / 2 - car.halfWidth * this.tuning.layers.railMargin);
    if (h.dist <= limit) return;
    const nx = (car.x - h.x) / h.dist, ny = (car.y - h.y) / h.dist;
    const v = car.body.getLinearVelocity();
    const out = v.x * nx + v.y * ny;
    car.body.setTransform({ x: h.x + nx * limit, y: h.y + ny * limit }, car.body.getAngle());
    if (out > 0) {
      const k = out * this.tuning.layers.railBounce;
      car.body.setLinearVelocity({ x: v.x - nx * k, y: v.y - ny * k });
    }
  }

  /** True while some knocked prop is still flying (its render transform changes). */
  propsMoving = false;

  private stepProps(step: number): void {
    const t = this.tuning.props;
    const car = this.car;
    const ang = car.heading, cos = Math.cos(ang), sin = Math.sin(ang);
    const cx = car.x, cy = car.y;
    const v = car.body.getLinearVelocity();
    const speed = Math.sqrt(v.x * v.x + v.y * v.y);
    const damp = t.flyDamping ** step;
    let moving = false;
    for (const set of this.props.values()) {
      for (const p of set.props) {
        if (p.knocked) {
          const age = this.time - p.knockedAt;
          if (age < t.flyS) {
            p.ox += p.vx * step;
            p.oy += p.vy * step;
            p.rot += p.spin * step;
            p.vx *= damp;
            p.vy *= damp;
            p.spin *= damp;
            moving = true;
          } else if (age > t.respawnS) {
            p.knocked = false;
            p.ox = p.oy = p.rot = 0;
            moving = true;
          }
          continue;
        }
        if (car.layer !== 0 || speed < t.knockMinMps) continue;
        const dx = p.x - cx, dy = p.y - cy;
        const reachX = car.halfLength + p.radius, reachY = car.halfWidth + p.radius;
        if (Math.abs(dx) > reachX + reachY || Math.abs(dy) > reachX + reachY) continue;
        const lx = dx * cos + dy * sin, ly = -dx * sin + dy * cos;
        if (Math.abs(lx) > reachX || Math.abs(ly) > reachY) continue;
        const side = ly >= 0 ? 1 : -1;
        p.knocked = true;
        p.knockedAt = this.time;
        p.vx = v.x * t.knockCarry - side * sin * speed * t.knockSide;
        p.vy = v.y * t.knockCarry + side * cos * speed * t.knockSide;
        p.spin = side * (t.knockSpin + speed * t.knockSpinPerMps);
        this.knockedCount++;
        moving = true;
        car.body.setLinearVelocity({ x: v.x * t.knockSlowdown, y: v.y * t.knockSlowdown });
      }
    }
    this.propsMoving = moving;
  }

  private skidMarks(): void {
    const s = this.tuning.skids;
    const car = this.car;
    if (car.rearSlip < s.minSlipMps && !(car.braking && car.speed > s.brakeMinMps)) {
      this.lastSkid = null;
      return;
    }
    const ang = car.heading, cos = Math.cos(ang), sin = Math.sin(ang);
    const off = -car.axleOffset, side = car.halfWidth;
    const rx = car.x + cos * off, ry = car.y + sin * off;
    const lx = rx - sin * side, ly = ry + cos * side, qx = rx + sin * side, qy = ry - cos * side;
    const last = this.lastSkid;
    if (last !== null) {
      this.skids.push(last[0], last[1], lx, ly, last[2], last[3], qx, qy);
      const max = s.maxSegments * 4;
      if (this.skids.length > max) this.skids.splice(0, this.skids.length - max);
      this.skidsVersion++;
    }
    this.lastSkid = [lx, ly, qx, qy];
  }

  /** Props within radius of (x, y). */
  *propsNear(x: number, y: number, radius: number): Generator<Prop> {
    for (const set of this.props.values()) {
      for (const p of set.props) if (Math.abs(p.x - x) < radius && Math.abs(p.y - y) < radius) yield p;
    }
  }

  /** Distance from the car to the nearest roadblock on its edge's neighbourhood, or null. */
  borderDistance(): number | null {
    const g = this.city.graph;
    const e = this.layers.edge;
    if (e === null) return null;
    let best: number | null = null;
    for (const ei of g.neighbours(e.index)) {
      const n = g.edges[ei]!;
      for (const node of [n.from, n.to]) {
        if (!g.border[node]) continue;
        const d = Math.hypot(g.nodeXY[2 * node]! - this.car.x, g.nodeXY[2 * node + 1]! - this.car.y);
        if (best === null || d < best) best = d;
      }
    }
    return best;
  }
}
