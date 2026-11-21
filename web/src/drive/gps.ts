import type { Graph } from '../gen/pb/citypack_pb';

/**
 * GPS route search (specs/route.md, version 1): integer Dijkstra on kept edges with fixed
 * tie-breaks, so both clients find the same route.
 */
export interface RouteGraph {
  nodeCount: number;
  from: Int32Array;
  to: Int32Array;
  /** Integer cost: length in dm × class multiplier. */
  cost: Float64Array;
  oneway: Int8Array;
  kept: Uint8Array;
  /** Edge indices per node, ascending. */
  nodeEdges: number[][];
}

export interface Route {
  cost: number;
  nodes: number[];
  edges: number[];
}

/** Length of a dm polyline: sum of floor(sqrt(dx² + dy²)) per segment. */
export function polylineDm(points: ArrayLike<number>): number {
  let len = 0;
  for (let i = 2; i + 1 < points.length; i += 2) {
    const dx = points[i]! - points[i - 2]!, dy = points[i + 1]! - points[i - 1]!;
    len += Math.floor(Math.sqrt(dx * dx + dy * dy));
  }
  return len;
}

function build(
  nodeCount: number,
  edges: Array<{ from: number; to: number; cls: number; oneway: number; kept: boolean; points: ArrayLike<number> }>,
  classCost: readonly number[],
): RouteGraph {
  const g: RouteGraph = {
    nodeCount,
    from: new Int32Array(edges.length),
    to: new Int32Array(edges.length),
    cost: new Float64Array(edges.length),
    oneway: new Int8Array(edges.length),
    kept: new Uint8Array(edges.length),
    nodeEdges: Array.from({ length: nodeCount }, () => []),
  };
  edges.forEach((e, i) => {
    g.from[i] = e.from;
    g.to[i] = e.to;
    g.cost[i] = polylineDm(e.points) * (classCost[e.cls] ?? classCost[0] ?? 1);
    g.oneway[i] = e.oneway;
    g.kept[i] = e.kept ? 1 : 0;
    g.nodeEdges[e.from]!.push(i);
    if (e.to !== e.from) g.nodeEdges[e.to]!.push(i);
  });
  for (const l of g.nodeEdges) l.sort((a, b) => a - b);
  return g;
}

export function routeGraphFromPb(pb: Graph, classCost: readonly number[]): RouteGraph {
  return build(
    pb.nodes.length,
    pb.edges.map((e) => ({ from: e.from, to: e.to, cls: e.class, oneway: e.oneway, kept: e.kept, points: e.points })),
    classCost,
  );
}

/** Vector config form: nodes [x, y, …], edges [[from, to, class, oneway, kept(0/1), x0, y0, …]]. */
export function routeGraphFromConfig(cfg: { nodes: number[]; edges: number[][]; classCost: number[] }): RouteGraph {
  return build(
    cfg.nodes.length >> 1,
    cfg.edges.map((e) => ({ from: e[0]!, to: e[1]!, cls: e[2]!, oneway: e[3]!, kept: e[4] === 1, points: e.slice(5) })),
    cfg.classCost,
  );
}

/** Min-heap of (cost, node) pairs ordered by cost, then node id. */
class Heap {
  private c: number[] = [];
  private n: number[] = [];
  get size(): number {
    return this.c.length;
  }
  private less(i: number, j: number): boolean {
    return this.c[i]! < this.c[j]! || (this.c[i] === this.c[j] && this.n[i]! < this.n[j]!);
  }
  private swap(i: number, j: number): void {
    [this.c[i], this.c[j]] = [this.c[j]!, this.c[i]!];
    [this.n[i], this.n[j]] = [this.n[j]!, this.n[i]!];
  }
  push(cost: number, node: number): void {
    this.c.push(cost);
    this.n.push(node);
    let i = this.c.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (!this.less(i, p)) break;
      this.swap(i, p);
      i = p;
    }
  }
  pop(): [number, number] {
    const top: [number, number] = [this.c[0]!, this.n[0]!];
    const lc = this.c.pop()!, ln = this.n.pop()!;
    if (this.c.length > 0) {
      this.c[0] = lc;
      this.n[0] = ln;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i;
        if (l < this.c.length && this.less(l, m)) m = l;
        if (r < this.c.length && this.less(r, m)) m = r;
        if (m === i) break;
        this.swap(i, m);
        i = m;
      }
    }
    return top;
  }
}

export function findRoute(g: RouteGraph, from: number, to: number): Route {
  if (from === to) return { cost: 0, nodes: [from], edges: [] };
  const dist = new Float64Array(g.nodeCount).fill(Infinity);
  const prevEdge = new Int32Array(g.nodeCount).fill(-1);
  const done = new Uint8Array(g.nodeCount);
  const heap = new Heap();
  dist[from] = 0;
  heap.push(0, from);
  while (heap.size > 0) {
    const [d, u] = heap.pop();
    if (done[u] || d > dist[u]!) continue;
    done[u] = 1;
    if (u === to) break;
    for (const e of g.nodeEdges[u]!) {
      if (!g.kept[e]) continue;
      let v: number;
      if (g.from[e] === u && g.oneway[e] !== -1) v = g.to[e]!;
      else if (g.to[e] === u && g.oneway[e] !== 1) v = g.from[e]!;
      else continue;
      const nd = d + g.cost[e]!;
      if (nd < dist[v]!) {
        dist[v] = nd;
        prevEdge[v] = e;
        heap.push(nd, v);
      }
    }
  }
  if (!done[to]) return { cost: -1, nodes: [], edges: [] };
  const nodes = [to], edges: number[] = [];
  for (let v = to; v !== from; ) {
    const e = prevEdge[v]!;
    edges.push(e);
    v = g.from[e] === v ? g.to[e]! : g.from[e]!;
    nodes.push(v);
  }
  return { cost: dist[to]!, nodes: nodes.reverse(), edges: edges.reverse() };
}

/** The route module in rules shape, for vectors (specs/route.md "Vektory"). */
export interface RouteState {
  cost: number;
  nodes: number[];
  edges: number[];
}

export class RouteRules {
  readonly id = 'route';
  readonly specVersion = 1;
  private g: RouteGraph | null = null;

  init(config: { nodes: number[]; edges: number[][]; classCost: number[] }, _seed: number): RouteState {
    this.g = routeGraphFromConfig(config);
    return { cost: -1, nodes: [], edges: [] };
  }

  legalActions(): Array<{ by: 'player'; from: number; to: number }> {
    return [];
  }

  apply(_s: RouteState, a: { by: string; from?: number; to?: number }): RouteState {
    const g = this.g;
    if (!g || a.by !== 'player' || !Number.isInteger(a.from) || !Number.isInteger(a.to)) throw new Error(`route: illegal ${JSON.stringify(a)}`);
    if (a.from! < 0 || a.to! < 0 || a.from! >= g.nodeCount || a.to! >= g.nodeCount) throw new Error(`route: node out of range`);
    return findRoute(g, a.from!, a.to!);
  }

  aiAction(): never {
    throw new Error('route: no AI');
  }

  result(): null {
    return null;
  }
}
