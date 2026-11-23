import { Body, Chain, Polygon, World, type Vec2Value } from 'planck';

import type { CarSpec } from '../gen/schema';
import type { Tuning, TuningLayers } from '../gen/tuning';
import type { ChunkData } from '../world/chunk';
import { chunkKey, type City, type EdgeHit, type RoadEdge, type RoadGraph } from '../world/model';
import { CAT_BUILDINGS, CAT_CAR, CAT_PARKED, CAT_TRAFFIC, CAT_ZONE, Car, zoneMask } from './car';
import { ControlInput } from './controls';
import { easeHeading, FlowState, roadSpot, SLIDE_SPIN_KEEP, UNSTICK_M, wallResponse, type StuckKind } from './flow';
import { canHop, HopState } from './hop';
import { generateProps, type Prop, type PropSet } from './props';
import { Traffic } from '../traffic/traffic';
import { Trams } from '../trams/trams';
import { ZoneWorld } from './zones';
import { surfaceEffect, TreeContacts, WaterFall } from './nature';
import { NatureMap, type SurfaceName } from '../world/nature';
import { WaterClass } from '../gen/pb/citypack_pb';

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
  /**
   * Client-side grip multiplier of the player's car (specs/weather.md "Přilnavost": rain_grip in
   * rain); an input to the drive, not its rule, so drive vectors and scenarios keep 1.
   */
  gripScale = 1;
  private acc = 0;
  knockedCount = 0;
  /** Bumped when the prop set changes (chunk added or removed). */
  propsVersion = 0;

  /** Skid marks: x0, y0, x1, y1 per segment, newest last. */
  readonly skids: number[] = [];
  private lastSkid: [number, number, number, number] | null = null;
  skidsVersion = 0;
  /** Called when a bridge or tunnel rail stops the car, with the speed into the rail (m/s). */
  onRail: ((outMps: number) => void) | null = null;
  /** Called before every fixed step (the benchmark autopilot sets the input here). */
  beforeStep: ((step: number) => void) | null = null;
  /** AI traffic and lights (specs/traffic.md); null when traffic.enabled is off. */
  readonly traffic: Traffic | null;
  /** Trams (specs/trams.md); null when trams.enabled is off or the city has no tracks. */
  readonly trams: Trams | null;
  /** Pedestrian zones and bollards (specs/zones.md). */
  readonly zones: ZoneWorld;
  /** Air-tank hop (specs/hop.md): charges and flight, per session. */
  readonly hop = new HopState();
  /** Wall response, trail and rescue (specs/flow.md, F-069). */
  readonly flow: FlowState;
  /** An open context menu that does not pause (specs/flow.md: no automatic rescue then); none in W. */
  flowBlocked: () => boolean = () => false;
  /** The GPS route still ahead (interleaved metres) or null; the road move faces along it. */
  routeAhead: () => ArrayLike<number> | null = () => null;
  /** Called after every rescue move (automatic or manual) with its kind. */
  onRescue: ((kind: StuckKind) => void) | null = null;
  /** Water, green and trees of the loaded chunks (specs/nature.md); empty for a pack without nature. */
  readonly nature: NatureMap;
  /** Soft trees (specs/flow.md "Strom jako měkká překážka"). */
  readonly trees = new TreeContacts();
  /** Water fall and tow (specs/nature.md "Voda"). */
  readonly water = new WaterFall();
  /** Surface under the car in the last step (specs/nature.md "Jízda"). */
  surface: SurfaceName = 'asphalt';
  /** Called when the car drives into water (it sinks over nature.water_fall.sink_s). */
  onWater: (() => void) | null = null;
  /** Called after the sunk car was put on the nearest road node (graph node index): charge the tow. */
  onSunk: ((node: number) => void) | null = null;
  /** Static contact in the previous step; a head-on bounce needs a new contact. */
  private wallContact = false;
  /** The head-on bounce (with the 1 m unstick) is armed; see wallStep. */
  private bounceArmed = true;
  private freeT = 0;
  // Velocity before the step (the "v before contact" of specs/flow.md).
  private preVx = 0;
  private preVy = 0;

  constructor(
    readonly city: City,
    public spec: CarSpec,
    readonly tuning: Tuning,
  ) {
    this.world = new World({ gravity: { x: 0, y: 0 } });
    this.zones = new ZoneWorld(this.world, tuning.drive, tuning.flow.wall);
    this.flow = new FlowState(tuning.flow.rescue);
    this.layers = new LayerTracker(city.graph, tuning.layers);
    this.nature = new NatureMap(city.chunkM);
    this.car = this.makeCar(city.startX, city.startY, city.startHeading);
    this.layers.reset(this.car.x, this.car.y);
    this.car.setLayer(this.layers.layer);
    this.traffic = tuning.traffic.enabled ? new Traffic(this.world, city, tuning) : null;
    this.trams = tuning.trams.enabled && !city.trams.isEmpty ? new Trams(this.world, city.trams, tuning, this.traffic) : null;
    if (this.traffic && this.trams) this.traffic.trams = this.trams.items;
    this.hop.fill(spec);
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
    this.flow.reset();
    this.wallContact = false;
    this.bounceArmed = true;
    this.trees.reset();
    this.water.reset();
    // A new body starts on the ground; the tank stays (replaceCar fills it for a hop car).
    this.hop.air = 0;
    this.hop.t = 0;
    this.setPlayerAirborne(false);
  }

  /** Switches to another car (specs/cars.md): a new body with that car's parameters, at rest. */
  replaceCar(spec: CarSpec, x: number, y: number, heading: number): void {
    this.spec = spec;
    this.spawn(x, y, heading);
    this.hop.fill(spec);
  }

  /**
   * Same car, new parameters (tuning, specs/garage.md "Účinek na jízdu"): the body is rebuilt in
   * place at rest from [spec]; the air tank stays.
   */
  rebuildCar(spec: CarSpec): void {
    const c = this.car;
    this.spec = spec;
    this.spawn(c.x, c.y, c.heading);
  }

  /** The driven car can hop now (specs/hop.md canHop). */
  get canHop(): boolean {
    const c = this.car;
    return !this.water.sinking && canHop(this.spec, this.hop.charges, this.hop.air, c.layer, c.speed, this.tuning.hop);
  }

  /** "Skok": takes off when canHop allows it; false otherwise (the HUD shows why). */
  tryHop(): boolean {
    const c = this.car;
    if (this.water.sinking || !this.hop.start(this.spec, c.layer, c.speed, this.tuning.hop)) return false;
    c.setAirborne(true);
    this.setPlayerAirborne(true);
    return true;
  }

  private setPlayerAirborne(on: boolean): void {
    if (this.traffic) this.traffic.playerAirborne = on;
    if (this.trams) this.trams.playerAirborne = on;
  }

  addChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    if (this.colliders.has(key)) return;
    const w = this.tuning.flow.wall;
    const body = this.world.createBody({ type: 'static' });
    // Static contacts use flow.wall friction and restitution (specs/flow.md), not drive.building_*.
    const opt = {
      friction: w.friction,
      restitution: w.restitution,
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
    this.zones.addChunk(c);
    if (c.nature) this.nature.add(c.nature);
    this.props.set(key, generateProps(this.city.graph, c.x, c.y, this.tuning));
    this.propsVersion++;
  }

  removeChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    const body = this.colliders.get(key);
    if (body) this.world.destroyBody(body);
    this.colliders.delete(key);
    this.zones.removeChunk(c);
    this.nature.remove(c.x, c.y);
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
    const air = this.hop.airborne;
    const frozen = this.flow.animT > 0;
    const sinking = this.water.sinking;
    if (sinking) {
      // Sinking (specs/nature.md "Voda"): no control, the entry velocity runs out over sink_s.
      const v = this.water.velocity(this.tuning.nature.waterFall.sinkS);
      this.car.body.setLinearVelocity(v);
      this.car.body.setAngularVelocity(0);
    } else if (frozen) {
      // Rescue animation (specs/flow.md): the car stands where it was put.
      this.car.body.setLinearVelocity({ x: 0, y: 0 });
      this.car.body.setAngularVelocity(0);
    } else if (air) {
      // In the air (specs/hop.md): no input, no tyres, buildings only, the layer stays.
      this.car.fly();
    } else {
      this.updateZoneMask();
      // Surface under the car (specs/nature.md "Jízda", specs/flow.md "Les"); asphalt off the ground layer.
      const car = this.car;
      this.surface = car.layer === 0 && !this.nature.empty ? this.nature.surfaceAt(car.x, car.y) : 'asphalt';
      const eff = surfaceEffect(this.surface, this.tuning);
      car.gripScale = this.gripScale * eff.grip;
      car.brakeScale = eff.grip;
      car.powerScale = eff.speed;
      car.drive(this.input, step, this.tuning.speedMps.cruise * eff.speed, this.tuning.speedMps.topDefault * eff.speed);
    }
    this.traffic?.preStep(step, this.car);
    this.trams?.preStep(step, this.car);
    const pv = this.car.body.getLinearVelocity();
    this.preVx = pv.x;
    this.preVy = pv.y;
    this.world.step(step, d.velocityIterations, d.positionIterations);
    if (air) {
      this.car.body.setAngularVelocity(0);
      if (this.hop.step(step)) this.land();
    } else {
      this.layers.update(this.car.x, this.car.y);
      this.car.setLayer(this.layers.layer);
    }
    this.traffic?.postStep(this.car);
    this.trams?.postStep(this.car);
    const rail = this.car.layer !== 0 ? this.rails() : null;
    if (sinking) {
      this.car.body.setAngularVelocity(0);
      if (this.water.step(step, this.tuning.nature.waterFall.sinkS)) this.sunk();
    } else if (frozen) {
      this.car.body.setLinearVelocity({ x: 0, y: 0 });
      this.car.body.setAngularVelocity(0);
    } else {
      this.wallStep(step, rail);
      this.treeStep(step);
      this.waterStep();
    }
    this.stepProps(step);
    this.skidMarks();
    this.rescueStep(step);
  }

  /**
   * Static contact response (specs/flow.md "Náraz do pevné překážky") after the physics step. The
   * contact normal is the one the pre-step velocity drives into most. A slide applies in every step
   * of contact; the head-on bounce only on a new contact while armed: it disarms itself until the
   * car has been free of static contact for flow.rescue.stuck_time_s or was rescued, so a car
   * pushing into a wall comes to rest there (and is rescued) instead of bouncing forever.
   */
  private wallStep(step: number, rail: { nx: number; ny: number } | null): void {
    const car = this.car, body = car.body;
    const vx = this.preVx, vy = this.preVy;
    let nx = 0, ny = 0, best = Infinity;
    for (let ce = body.getContactList(); ce; ce = ce.next) {
      const c = ce.contact;
      if (!c.isTouching()) continue;
      const fa = c.getFixtureA(), fb = c.getFixtureB();
      const mine = fa.getBody() === body;
      const other = mine ? fb : fa;
      if ((other.getFilterCategoryBits() & (CAT_BUILDINGS | CAT_ZONE)) === 0) continue;
      const wm = c.getWorldManifold(null);
      if (!wm) continue;
      // planck's normal points from A to B; n must point from the wall to the car.
      const sx = mine ? -wm.normal.x : wm.normal.x, sy = mine ? -wm.normal.y : wm.normal.y;
      const vn = vx * sx + vy * sy;
      if (vn < best) {
        best = vn;
        nx = sx;
        ny = sy;
      }
    }
    if (rail) {
      const vn = vx * rail.nx + vy * rail.ny;
      if (vn < best) {
        best = vn;
        nx = rail.nx;
        ny = rail.ny;
      }
    }
    const contact = best !== Infinity;
    const isNew = contact && !this.wallContact;
    this.wallContact = contact;
    if (!contact) {
      this.freeT += step;
      if (this.freeT >= this.tuning.flow.rescue.stuckTimeS) this.bounceArmed = true;
      return;
    }
    this.freeT = 0;
    const r = wallResponse(vx, vy, nx, ny, this.tuning.flow.wall);
    if (r === null) return;
    if (r.slide) {
      body.setLinearVelocity({ x: r.vx, y: r.vy });
      body.setTransform(body.getPosition(), easeHeading(body.getAngle(), r.tx, r.ty, step));
      body.setAngularVelocity(body.getAngularVelocity() * SLIDE_SPIN_KEEP);
    } else if (isNew && this.bounceArmed) {
      this.bounceArmed = false;
      const p = body.getPosition();
      body.setTransform({ x: p.x + nx * UNSTICK_M, y: p.y + ny * UNSTICK_M }, body.getAngle());
      body.setLinearVelocity({ x: r.vx, y: r.vy });
      body.setAngularVelocity(0);
    }
  }

  /**
   * Soft trees (specs/flow.md "Strom jako měkká překážka"): trunks are sensors on the ground layer;
   * the start of an overlap slows the car (and fells a sapling), the overlap pushes it aside.
   */
  private treeStep(step: number): void {
    const car = this.car;
    if (car.layer !== 0 || car.airborne || this.nature.empty) {
      this.trees.clear(step);
      return;
    }
    const v = car.body.getLinearVelocity();
    const r = this.trees.step(step, this.time, this.nature, { x: car.x, y: car.y, vx: v.x, vy: v.y, halfWidth: car.halfWidth }, this.tuning);
    if (r === null) return;
    car.body.setLinearVelocity({ x: r.vx, y: r.vy });
    if (r.yaw !== 0) car.body.setTransform(car.body.getPosition(), car.body.getAngle() + r.yaw);
  }

  /**
   * Water (specs/nature.md "Voda"): the car's centre on the ground layer in water (not `small`) and
   * off the carriageway of its edge starts the sink. No wall at the bank: quays and piers can be left.
   */
  private waterStep(): void {
    const car = this.car;
    if (car.layer !== 0 || car.airborne || this.nature.empty) return;
    const w = this.nature.waterAt(car.x, car.y);
    if (w === null || w.cls === WaterClass.WATER_SMALL) return;
    const h = this.layers.hit;
    if (h !== null && h.edge.isGround && h.dist <= h.edge.width / 2) return;
    const v = car.body.getLinearVelocity();
    this.water.start(v.x, v.y);
    this.trees.clear(0);
    this.onWater?.();
  }

  /** The car has sunk: on the nearest kept ground node, facing along its edge, at rest; then the tow. */
  private sunk(): void {
    const car = this.car;
    this.water.reset();
    const s = roadSpot(this.city.graph, car.x, car.y, null, this.tuning.layers.searchM);
    if (s !== null) this.place(s.x, s.y, s.heading);
    this.flow.reset();
    this.onSunk?.(s?.node ?? -1);
  }

  /** Trail and automatic rescue (specs/flow.md "Vyproštění"); the move itself is place(). */
  private rescueStep(step: number): void {
    const car = this.car, inp = this.input;
    const plan = this.flow.step(step, this.time, {
      x: car.x, y: car.y, heading: car.heading, speed: car.speed,
      braking: inp.brake > 0 || inp.handbrake, airborne: car.airborne,
    }, this.flowBlocked() || this.water.sinking);
    if (plan === null) return;
    if (plan.kind === 'road') this.toRoadSpot();
    else this.place(plan.point.x, plan.point.y, plan.point.heading);
    this.onRescue?.(plan.kind);
  }

  /**
   * "Na silnici" (button or pause menu, specs/flow.md): the road move, free, counted as stuck.
   * Returns false when the city has no kept ground road.
   */
  toRoad(): boolean {
    const car = this.car;
    this.flow.manual(this.time, car.x, car.y);
    const ok = this.toRoadSpot();
    this.onRescue?.('button');
    return ok;
  }

  private toRoadSpot(): boolean {
    const car = this.car;
    const s = roadSpot(this.city.graph, car.x, car.y, this.routeAhead(), this.tuning.layers.searchM);
    if (s === null) return false;
    this.place(s.x, s.y, s.heading);
    return true;
  }

  /** The rescue move: same body, at rest, on the ground at (x, y). */
  private place(x: number, y: number, heading: number): void {
    const car = this.car, body = car.body;
    body.setTransform({ x, y }, heading);
    body.setLinearVelocity({ x: 0, y: 0 });
    body.setAngularVelocity(0);
    car.wheelAngle = 0;
    this.layers.reset(x, y);
    car.setLayer(this.layers.layer);
    this.lastSkid = null;
    this.wallContact = false;
    this.bounceArmed = true;
    this.freeT = 0;
  }

  /**
   * Landing: the layer mask comes back and the zone test runs with the hold-off (a car landing on
   * bollards gets out first, specs/zones.md); overlapping traffic is pushed (traffic step 7).
   */
  private land(): void {
    const car = this.car;
    this.layers.update(car.x, car.y);
    car.setLayer(this.layers.layer);
    const r = Math.hypot(car.halfLength, car.halfWidth) + this.tuning.drive.bodyRoundM;
    this.inZone = car.layer === 0 && this.zones.insideFor(car.x, car.y, r, true);
    car.setZone(zoneMask(car.spec.class, this.inZone));
    car.setAirborne(false);
    this.setPlayerAirborne(false);
  }

  /** CAT_ZONE in the player's mask (specs/zones.md); the inside test only counts on layer 0. */
  private updateZoneMask(): void {
    const car = this.car;
    const r = Math.hypot(car.halfLength, car.halfWidth) + this.tuning.drive.bodyRoundM;
    this.inZone = car.layer === 0 && this.zones.insideFor(car.x, car.y, r, this.inZone);
    car.setZone(zoneMask(car.spec.class, this.inZone));
  }
  /** Last zone test result (the hold-off in specs/zones.md). */
  private inZone = false;

  /**
   * Keeps the car on bridge decks and in tunnels; returns the rail's normal (towards the road) when
   * the car moved into it, a static contact for wallStep (specs/flow.md: bridge rails).
   */
  private rails(): { nx: number; ny: number } | null {
    const h = this.layers.hit;
    if (h === null || h.dist === 0) return null;
    const car = this.car;
    const limit = Math.max(0, h.edge.width / 2 - car.halfWidth * this.tuning.layers.railMargin);
    if (h.dist <= limit) return null;
    const nx = (car.x - h.x) / h.dist, ny = (car.y - h.y) / h.dist;
    const v = car.body.getLinearVelocity();
    const out = v.x * nx + v.y * ny;
    car.body.setTransform({ x: h.x + nx * limit, y: h.y + ny * limit }, car.body.getAngle());
    if (out > 0) {
      this.onRail?.(out);
      const k = out * this.tuning.layers.railBounce;
      car.body.setLinearVelocity({ x: v.x - nx * k, y: v.y - ny * k });
      return { nx: -nx, ny: -ny };
    }
    return null;
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
        if (car.layer !== 0 || car.airborne || speed < t.knockMinMps) continue;
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
