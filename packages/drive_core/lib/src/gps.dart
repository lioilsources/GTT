import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/citypack_pb.dart' as pb show Graph;

/// GPS route search (specs/route.md, version 1): integer Dijkstra on kept edges with fixed
/// tie-breaks, so both clients find the same route.
class RouteGraph {
  RouteGraph._(this.nodeCount, int edgeCount)
    : from = Int32List(edgeCount),
      to = Int32List(edgeCount),
      cost = Float64List(edgeCount),
      oneway = Int8List(edgeCount),
      kept = Uint8List(edgeCount),
      nodeEdges = List.generate(nodeCount, (_) => <int>[]);

  final int nodeCount;
  final Int32List from, to;

  /// Integer cost: length in dm × class multiplier (stored as double, exact below 2^53).
  final Float64List cost;
  final Int8List oneway;
  final Uint8List kept;

  /// Edge indices per node, ascending.
  final List<List<int>> nodeEdges;

  static RouteGraph _build(int nodeCount, List<_E> edges, List<int> classCost) {
    final g = RouteGraph._(nodeCount, edges.length);
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      g.from[i] = e.from;
      g.to[i] = e.to;
      final mult = e.cls < classCost.length ? classCost[e.cls] : classCost.first;
      g.cost[i] = (polylineDm(e.points) * mult).toDouble();
      g.oneway[i] = e.oneway;
      g.kept[i] = e.kept ? 1 : 0;
      g.nodeEdges[e.from].add(i);
      if (e.to != e.from) g.nodeEdges[e.to].add(i);
    }
    for (final l in g.nodeEdges) {
      l.sort();
    }
    return g;
  }

  factory RouteGraph.fromPb(pb.Graph g, List<int> classCost) => _build(g.nodes.length, [
    for (final e in g.edges) _E(e.from, e.to, e.class_4.value, e.oneway, e.kept, e.points),
  ], classCost);

  /// Vector config form: nodes [x, y, …], edges [[from, to, class, oneway, kept(0/1), x0, y0, …]].
  factory RouteGraph.fromConfig(Map<String, Object?> c) {
    final nodes = (c['nodes'] as List).length ~/ 2;
    final edges = [
      for (final e in (c['edges'] as List).cast<List<Object?>>())
        _E(e[0] as int, e[1] as int, e[2] as int, e[3] as int, e[4] == 1, e.sublist(5).cast<int>()),
    ];
    return _build(nodes, edges, (c['classCost'] as List).cast<int>());
  }
}

class _E {
  _E(this.from, this.to, this.cls, this.oneway, this.kept, this.points);
  final int from, to, cls, oneway;
  final bool kept;
  final List<int> points;
}

/// Length of a dm polyline: sum of floor(sqrt(dx² + dy²)) per segment.
int polylineDm(List<int> p) {
  var len = 0;
  for (var i = 2; i + 1 < p.length; i += 2) {
    final dx = p[i] - p[i - 2], dy = p[i + 1] - p[i - 1];
    len += math.sqrt((dx * dx + dy * dy).toDouble()).floor();
  }
  return len;
}

class GpsRoute {
  const GpsRoute(this.cost, this.nodes, this.edges);
  final int cost;
  final List<int> nodes, edges;

  Map<String, Object?> toJson() => {'cost': cost, 'nodes': nodes, 'edges': edges};
}

GpsRoute findRoute(RouteGraph g, int from, int to) {
  if (from == to) return GpsRoute(0, [from], const []);
  final dist = Float64List(g.nodeCount)..fillRange(0, g.nodeCount, double.infinity);
  final prev = Int32List(g.nodeCount)..fillRange(0, g.nodeCount, -1);
  final done = Uint8List(g.nodeCount);
  final heap = _Heap();
  dist[from] = 0;
  heap.push(0, from);
  while (heap.isNotEmpty) {
    final (d, u) = heap.pop();
    if (done[u] == 1 || d > dist[u]) continue;
    done[u] = 1;
    if (u == to) break;
    for (final e in g.nodeEdges[u]) {
      if (g.kept[e] == 0) continue;
      int v;
      if (g.from[e] == u && g.oneway[e] != -1) {
        v = g.to[e];
      } else if (g.to[e] == u && g.oneway[e] != 1) {
        v = g.from[e];
      } else {
        continue;
      }
      final nd = d + g.cost[e];
      if (nd < dist[v]) {
        dist[v] = nd;
        prev[v] = e;
        heap.push(nd, v);
      }
    }
  }
  if (done[to] == 0) return const GpsRoute(-1, [], []);
  final nodes = [to], edges = <int>[];
  for (var v = to; v != from;) {
    final e = prev[v];
    edges.add(e);
    v = g.from[e] == v ? g.to[e] : g.from[e];
    nodes.add(v);
  }
  return GpsRoute(dist[to].toInt(), nodes.reversed.toList(), edges.reversed.toList());
}

/// Min-heap of (cost, node) ordered by cost, then node id.
class _Heap {
  final List<double> _c = [];
  final List<int> _n = [];
  bool get isNotEmpty => _c.isNotEmpty;
  bool _less(int i, int j) => _c[i] < _c[j] || (_c[i] == _c[j] && _n[i] < _n[j]);
  void _swap(int i, int j) {
    final c = _c[i], n = _n[i];
    _c[i] = _c[j];
    _n[i] = _n[j];
    _c[j] = c;
    _n[j] = n;
  }

  void push(double c, int n) {
    _c.add(c);
    _n.add(n);
    var i = _c.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!_less(i, p)) break;
      _swap(i, p);
      i = p;
    }
  }

  (double, int) pop() {
    final top = (_c[0], _n[0]);
    final lc = _c.removeLast(), ln = _n.removeLast();
    if (_c.isNotEmpty) {
      _c[0] = lc;
      _n[0] = ln;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _c.length && _less(l, m)) m = l;
        if (r < _c.length && _less(r, m)) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }
}

/// The route module in rules shape, for vectors (specs/route.md "Vektory").
class RouteRules extends MgRules<GpsRoute, ({int from, int to}), Never> {
  RouteGraph? _g;

  @override
  String get id => 'route';

  @override
  int get specVersion => 1;

  @override
  GpsRoute init(Map<String, Object?> config, int seed) {
    _g = RouteGraph.fromConfig(config);
    return const GpsRoute(-1, [], []);
  }

  @override
  List<({int from, int to})> legalActions(GpsRoute state) => const [];

  @override
  GpsRoute apply(GpsRoute state, ({int from, int to}) a) {
    final g = _g ?? (throw StateError('route: init first'));
    if (a.from < 0 || a.to < 0 || a.from >= g.nodeCount || a.to >= g.nodeCount) throw IllegalAction(id, a);
    return findRoute(g, a.from, a.to);
  }

  @override
  ({int from, int to}) aiAction(GpsRoute state, int level, Prng ai) => throw UnsupportedError('route: no AI');

  @override
  Never? result(GpsRoute state) => null;

  @override
  ({int from, int to}) actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    return (from: j['from'] as int, to: j['to'] as int);
  }

  @override
  Map<String, Object?> stateToJson(GpsRoute s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Never r) => const {};
}
