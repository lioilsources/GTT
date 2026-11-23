import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart' show RouteGraph;
import 'package:feed_hub/feed_hub.dart' show NavTarget, edgeLengthsDm;
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_sprint/mg_sprint.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:world_engine/core.dart';

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  final ts = tuning.minigames.sprint;
  final pack = Directory('$repoRoot/build/packs/nyc');
  final skip = pack.existsSync() ? false : 'no pack';

  late City city;
  late SprintWorld world;
  late List<NavTarget> dests;
  setUpAll(() async {
    if (!pack.existsSync()) return;
    city = await City.load(_FilePack('${pack.path}/'));
    world = SprintWorld(
      graph: city.graph,
      route: RouteGraph.fromPb(city.graphPb, tuning.route.classCost),
      lensDm: edgeLengthsDm(city.graphPb),
      searchM: tuning.nav.searchM,
    );
    // The Taxi destinations (mg_taxi taxiDests): hero landmarks with a kept road in reach.
    dests = [
      for (final l in city.landmarks.items)
        if (l.hero)
          if (city.graph.nearest(l.x / 10, l.y / 10, maxDist: ts.destSearchM, where: (e) => e.kept && e.isGround)
              case final h?)
            NavTarget(id: l.id, name: l.name, edge: h.edge.index, parkX: (h.x * 10).round(), parkY: (h.y * 10).round()),
    ];
  });

  test('checkpoints follow the cum rules; the race runs gate by gate to the finish', () {
    final spot = city.spots.items.where((s) => s.minigame == 'sprint').firstOrNull ?? city.spots.items.first;
    final x0 = spot.parkX / 10, y0 = spot.parkY / 10, h0 = spot.parkHeading.toDouble();
    final hit = city.graph.nearest(x0, y0, maxDist: tuning.layers.spawnSearchM, where: (e) => e.isGround);
    final race = SprintRace(world, ts, dests, 3, 2024);
    final ev = race.begin((hit: hit, x: x0, y: y0, heading: h0));
    expect(ev.single, isA<SprintPicked>());
    final allow = race.log.first.allow;
    for (final id in allow) {
      final d = dests.firstWhere((d) => d.id == id);
      final s = math.sqrt(math.pow(d.parkX / 10 - x0, 2) + math.pow(d.parkY / 10 - y0, 2));
      expect(s, inInclusiveRange(ts.destMinM, ts.destMaxM));
    }
    if (allow.isNotEmpty) expect(allow, contains(race.state.dest));
    final p = race.plan!;
    // distDm = whole route edges; gates by cum[i] ≥ k × every and 2 × (distDm − cum[i]) > every.
    final every = (ts.cpEveryM * 10).round();
    var cum = 0, k = 1;
    final want = <int>[], widths = <double>[];
    final total = p.route.edges.fold(0, (a, e) => a + world.lensDm[e]);
    for (var i = 0; i < p.route.edges.length; i++) {
      cum += world.lensDm[p.route.edges[i]];
      if (cum >= k * every && 2 * (total - cum) > every) {
        want.add(cum);
        widths.add(city.graph.edges[p.route.edges[i]].width / 2);
        k++;
      }
    }
    expect(p.distDm, total);
    expect(p.gates.map((g) => g.atDm), want);
    expect(p.gates.map((g) => g.halfWidth), widths);
    expect(p.gates.length, greaterThan(1));

    SprintPose at(double x, double y, {int layer = 0}) => (x: x, y: y, heading: h0, layer: layer);
    // Countdown: go on the first frame with clock ≥ countdown_s, atMs = floor(clock × 1000).
    var t = 0.0;
    while (race.state.phase == 'ready') {
      race.update(0.4, at(x0, y0));
      t += 0.4;
    }
    expect(race.state.goMs, (t * 1000).floor());
    expect(race.clock, greaterThanOrEqualTo(ts.countdownS));
    expect(race.clock - 0.4, lessThan(ts.countdownS));
    // A crash goes before the gate at the same atMs; one gate per frame even when two are in reach.
    final events = <SprintEvent>[];
    for (var i = 0; i < p.gates.length; i++) {
      final g = p.gates[i];
      events.addAll(race.update(0.5, at(g.x, g.y), (_) => i == 0));
      expect(race.state.passed, i + 1);
    }
    expect(race.log.where((a) => a.op == 'hit').length, 1);
    final hi = race.log.indexWhere((a) => a.op == 'hit');
    expect([race.log[hi + 1].op, race.log[hi + 1].atMs], ['cp', race.log[hi].atMs]);
    // Not on layer 0: no finish.
    race.update(0.5, at(p.finish.x, p.finish.y, layer: 1));
    expect(race.over, false);
    events.addAll(race.update(0.5, at(p.finish.x, p.finish.y)));
    final over = events.last as SprintOver;
    expect(over.result.dest, p.dest.id);
    expect(race.state.timeMs, race.state.clockMs - race.state.goMs + ts.hitPenaltyMs);
    final cps = events.whereType<SprintCp>().toList();
    for (final c in cps) {
      expect(c.parAtMs, race.state.parMs * p.gates[c.index].atDm ~/ p.distDm);
    }
  }, skip: skip);

  test('time cap from go ends the race unfinished', () {
    final spot = city.spots.items.where((s) => s.minigame == 'sprint').firstOrNull ?? city.spots.items.first;
    final x0 = spot.parkX / 10, y0 = spot.parkY / 10;
    final race = SprintRace(world, ts, dests, 1, 5);
    race.begin((hit: null, x: x0, y: y0, heading: 0));
    if (race.over) return;
    SprintPose far() => (x: x0 + 10000, y: y0, heading: 0, layer: 0);
    race.update(ts.countdownS.toDouble(), far());
    expect(race.state.phase, 'run');
    race.update(ts.timeCapS - 0.01, far());
    expect(race.over, false);
    final ev = race.update(0.02, far());
    expect((ev.single as SprintOver).result.stars, 0);
    expect(race.state.finished, false);
  }, skip: skip);

  test('empty destination list: over at pick', () {
    final race = SprintRace(world, ts, const [], 3, 1);
    expect(race.begin((hit: null, x: 0, y: 0, heading: 0)).single, isA<SprintOver>());
    expect(race.over, true);
  }, skip: skip);
}
