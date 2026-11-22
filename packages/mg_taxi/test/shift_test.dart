import 'dart:io';
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart' show RouteGraph;
import 'package:feed_hub/feed_hub.dart' show NavTarget, edgeLengthsDm;
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_taxi/mg_taxi.dart';
import 'package:rules_core/rules_core.dart';
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
  final tt = tuning.minigames.taxi;
  final pack = Directory('$repoRoot/build/packs/nyc');
  final skip = pack.existsSync() ? false : 'no pack';

  late City city;
  late List<NavTarget> dests;
  setUpAll(() async {
    if (!pack.existsSync()) return;
    city = await City.load(_FilePack('${pack.path}/'));
    dests = taxiDests(city.graph, [
      for (final l in city.landmarks.items) (id: l.id, name: l.name, x: l.x, y: l.y, hero: l.hero),
    ], tt.destSearchM);
  });

  test('destinations are hero landmarks with a road, by their real names', () {
    final heroes = {for (final l in city.landmarks.items.where((l) => l.hero)) l.id: l.name};
    expect(dests.length, greaterThan(10));
    for (final d in dests) {
      expect(heroes[d.id], d.name);
    }
    expect(dests.map((d) => d.name), contains('Empire State Building'));
  }, skip: skip);

  test('teleports the car to passengers and destinations, then the shift ends with the rules result', () {
    final stand = city.spots.items.firstWhere((s) => s.minigame == 'taxi');
    final world = TaxiWorld(
      graph: city.graph,
      route: RouteGraph.fromPb(city.graphPb, tuning.route.classCost),
      lensDm: edgeLengthsDm(city.graphPb),
      straightPct: tuning.feed.straightPct,
      searchM: tuning.nav.searchM,
    );
    final shift = TaxiShift(world, tt, dests, 2024);
    var x = stand.parkX / 10, y = stand.parkY / 10, speed = 0.0;
    final heading = stand.parkHeading.toDouble();
    List<TaxiEvent> step(double s) => shift.update(s, (
      x: x,
      y: y,
      heading: heading,
      speed: speed,
      layer: 0,
    ), city.graph.nearest(x, y, maxDist: 30, where: (e) => e.isGround));

    final cfg = TaxiConfig.fromTuning(tt, const []);
    var paid = 0, rides = 0;
    for (var ride = 0; ride < 3; ride++) {
      speed = 8;
      final ev = step(1);
      final p = shift.passenger;
      expect(p, isNotNull, reason: 'passenger $ride');
      if (ride == 0) expect(ev.single, isA<TaxiSpawn>());
      x = p!.target.parkX / 10;
      y = p.target.parkY / 10;
      speed = 0;
      final pick = step(5).whereType<TaxiPickup>().single;
      expect(dests.map((d) => d.id), contains(pick.dest.id));
      expect(pick.distDm, greaterThan(0));
      if (ride == 0) shift.hit();
      speed = 10;
      step(59);
      x = pick.dest.parkX / 10;
      y = pick.dest.parkY / 10;
      speed = 0;
      final drop = step(1).whereType<TaxiDropoff>().single;
      expect(drop.ride.dest, pick.dest.id);
      expect(drop.ride.rideS, 60);
      expect(drop.ride.fare, taxiFare(cfg, pick.distDm, 60000, ride == 0 ? 1 : 0).fare);
      paid += drop.ride.fare;
      rides++;
    }
    speed = 12;
    TaxiOver? over;
    for (var i = 0; i < 1000 && over == null; i++) {
      over = step(1).whereType<TaxiOver>().firstOrNull;
    }
    expect(over, isNotNull);
    expect(shift.over, isTrue);
    expect((over!.result.score, over.result.rides), (paid, rides));
    expect(over.result.stars, taxiStars(cfg, paid));
    expect(shift.clock, greaterThanOrEqualTo(tt.shiftS));
    // The action log replays to the same state with the pure rules alone.
    final r = TaxiRules();
    var s = r.start(TaxiConfig.fromTuning(tt, [for (final d in dests) d.id]), 2024);
    for (final a in shift.log) {
      s = r.apply(s, a);
    }
    expect(canonical(s.toJson()), canonical(shift.state.toJson()));
  }, skip: skip);
}
