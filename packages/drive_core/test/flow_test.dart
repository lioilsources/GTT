import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

/// specs/flow.md v1 (F-069): wall slide and bounce, trail and rescue, and the synthetic track
/// scenarios of scenarios/flow (the same track, start poses and metrics as web/test/flow.test.ts).

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
final sedan = parseCarSpec(File('../../content/cars/sedan_regent.json').readAsStringSync());
TuningFlowWall get wall => tuning.flow.wall;
TuningFlowRescue get rescue => tuning.flow.rescue;

FlowCar fc({double x = 0, double y = 0, double speed = 10, bool braking = false, bool airborne = false}) =>
    FlowCar(x: x, y: y, heading: 0, speed: speed, braking: braking, airborne: airborne);

// ---------- synthetic track (specs/flow.md "Scénáře"), shared with web/test/flow.test.ts

Uint8List _gz(List<int> b) => Uint8List.fromList(gzip.encode(b));

class _MemPack implements PackSource {
  _MemPack(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('no $path in the pack'));
}

/// 0 (−200,0) ──e0── 1 (0,0) ──e1── 2 (200,0): primary, 2 lanes, kept, 20 m wide.
Future<City> flowCity() {
  pb.Node n(int x, int y) => pb.Node(x: x * 10, y: y * 10);
  pb.Edge e(int from, int to, List<int> pts) => pb.Edge(
    from: from,
    to: to,
    points: [for (final v in pts) v * 10],
    class_4: pb.RoadClass.PRIMARY,
    lanes: 2,
    oneway: 0,
    kept: true,
    widthM: 20,
  );
  return City.load(
    _MemPack({
      'manifest.pb': _gz(
        pb.Manifest(
          formatVersion: 1,
          cityId: 'test',
          chunkM: 256,
          driveSide: 'right',
          units: 'metric',
          start: pb.Spawn(x: -1500, y: 0, headingRad: 0),
        ).writeToBuffer(),
      ),
      'graph.pb': _gz(
        pb.Graph(
          names: [''],
          nodes: [n(-200, 0), n(0, 0), n(200, 0)],
          edges: [
            e(0, 1, [-200, 0, 0, 0]),
            e(1, 2, [0, 0, 200, 0]),
          ],
        ).writeToBuffer(),
      ),
      'landmarks.pb': _gz(pb.Landmarks().writeToBuffer()),
      'spots.pb': _gz(pb.Spots().writeToBuffer()),
    }),
  );
}

BuildingData box(double x0, double y0, double x1, double y1) {
  final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  return BuildingData(
    xy: Float32List.fromList([x0, y0, x1, y0, x1, y1, x0, y1]),
    ringEnds: Int32List.fromList([4]),
    roof: Uint16List(0),
    height: 10,
    minHeight: 0,
    landmark: 0,
    collide: true,
    seed: 0,
    cx: cx,
    cy: cy,
    radius: math.sqrt((x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy)),
    wallU: Float32List(4),
  );
}

/// Wall W (face y = 40, x −100..60) and block B (face x = 60, y 15..40): a concave corner at (60, 40).
final buildings = [box(-100, 40, 60, 60), box(60, 15, 80, 60)];

/// Start pose and speed of each scenario (specs/flow.md "Scénáře").
const starts = <String, ({double x, double y, double deg, double v, double s})>{
  'wall_30': (x: 0, y: 33.8, deg: 30, v: 20, s: 2),
  'wall_head_on': (x: 0, y: 5, deg: 90, v: 0, s: 8),
  'corner_3x': (x: 20, y: 0, deg: 47, v: 0, s: 20),
};

const kindNo = {StuckKind.auto1: 1, StuckKind.auto2: 2, StuckKind.road: 3, StuckKind.button: 4};

double round3(double v) => (v * 1000).round() / 1000;

/// Runs one scenario on the synthetic track; returns its metrics.
Future<Map<String, double>> runScenario(String name, List<Map<String, Object?>> inputs) async {
  final city = await flowCity();
  final d = DriveWorld(city: city, spec: sedan, tuning: tuning);
  d.addChunk(ChunkData(0, 0, buildings, const []));
  d.props.clear(); // the track has no street furniture
  d.traffic?.solid = false;
  final st = starts[name]!;
  final h = st.deg * math.pi / 180;
  d.spawn(st.x, st.y, h);
  d.car.body.linearVelocity = Vector2(st.v * math.cos(h), st.v * math.sin(h));
  final rescues = <({double t, StuckKind kind, double fromX, double fromY, double x, double y})>[];
  var preX = 0.0, preY = 0.0;
  d.onRescue = (kind) =>
      rescues.add((t: d.time, kind: kind, fromX: preX, fromY: preY, x: d.car.x, y: d.car.y));
  final dt = 1 / tuning.drive.stepHz;
  var firstContact = -1.0, alongFirst = 0.0, alongMin = double.infinity;
  final steps = (st.s / dt).round();
  var k = 0;
  double inNum(Map<String, Object?> m, String key) => ((m[key] ?? 0) as num).toDouble();
  for (var i = 0; i < steps; i++) {
    while (k + 1 < inputs.length && inNum(inputs[k + 1], 't') <= d.time + 1e-9) {
      k++;
    }
    final inp = inputs[k];
    d.input
      ..reset()
      ..throttle = inNum(inp, 'throttle')
      ..steer = inNum(inp, 'steer')
      ..brake = inNum(inp, 'brake');
    preX = d.car.x;
    preY = d.car.y;
    d.update(dt);
    final v = d.car.velocity;
    if (firstContact < 0 && d.wallContact) {
      firstContact = d.time;
      alongFirst = v.x;
    }
    if (firstContact >= 0 && d.time <= firstContact + 1 + 1e-9) alongMin = math.min(alongMin, v.x);
    if (Platform.environment['FLOW_TRACE'] == name && i % 3 == 0) {
      // ignore: avoid_print
      print('${d.time.toStringAsFixed(3)} ${d.car.x.toStringAsFixed(2)} ${d.car.y.toStringAsFixed(2)} '
          '${v.x.toStringAsFixed(2)} ${v.y.toStringAsFixed(2)} ${d.flow.stuckT.toStringAsFixed(2)}');
    }
  }
  final m = <String, double>{'first_contact_s': round3(firstContact)};
  if (name == 'wall_30') {
    m['along_wall_mps'] = round3(alongFirst);
    m['along_wall_min_1s_mps'] = round3(alongMin);
    m['rescues'] = rescues.length.toDouble();
  } else if (name == 'wall_head_on') {
    final r = rescues.firstOrNull;
    m['rescue_after_contact_s'] = r == null ? -1 : round3(r.t - firstContact);
    m['rescue_kind'] = r == null ? 0 : kindNo[r.kind]!.toDouble();
    m['rewind_m'] = r == null ? -1 : round3(math.sqrt(math.pow(r.x - r.fromX, 2) + math.pow(r.y - r.fromY, 2)));
    m['trail_offset_m'] = r == null ? -1 : round3((r.x - st.x).abs());
  } else {
    for (var i = 0; i < math.min(3, rescues.length); i++) {
      m['rescue${i + 1}_kind'] = kindNo[rescues[i].kind]!.toDouble();
      m['rescue${i + 1}_t_s'] = round3(rescues[i].t);
    }
    if (rescues.length >= 3) {
      final r3 = rescues[2];
      final g = city.graph;
      final hit = g.nearest(r3.x, r3.y, maxDist: 1);
      m['rescue3_on_road'] = hit != null && hit.edge.kept ? 1 : 0;
    }
  }
  d.dispose();
  return m;
}

void main() {
  setUpAll(initializeForge2D);

  group('wall response (specs/flow.md "Náraz do pevné překážky")', () {
    test('30° at 20 m/s slides along the wall with at least 14.72 m/s', () {
      final a = 30 * math.pi / 180;
      final r = wallResponse(20 * math.cos(a), 20 * math.sin(a), 0, -1, wall)!;
      expect(r.slide, isTrue);
      expect(r.vy, closeTo(0, 1e-9));
      expect(r.vx, greaterThanOrEqualTo(20 * wall.slideSpeedKeep * math.cos(a)));
      expect(r.vx, greaterThanOrEqualTo(14.7));
      expect(r.tx, closeTo(1, 1e-9));
    });

    test('head-on bounces with restitution, keeps the tangential part', () {
      final a = 80 * math.pi / 180;
      final r = wallResponse(10 * math.cos(a), 10 * math.sin(a), 0, -1, wall)!;
      expect(r.slide, isFalse);
      expect(r.vy, closeTo(-10 * math.sin(a) * wall.restitution, 1e-9));
      expect(r.vx, closeTo(10 * math.cos(a), 1e-9));
    });

    test('no response when moving away or standing', () {
      expect(wallResponse(0, 5, 0, 1, wall), isNull);
      expect(wallResponse(0, 0, 0, 1, wall), isNull);
    });

    test('heading eases to the nearer wall direction at 6 rad/s', () {
      expect(easeHeading(0.5, 1, 0, 1 / 60), closeTo(0.5 * math.exp(-6 / 60), 1e-9));
      // Nose pointing backwards along the wall: eases to π, not 0.
      expect(easeHeading(3, 1, 0, 1), greaterThan(3));
    });
  });

  group('trail and rescue rules (specs/flow.md "Vyproštění")', () {
    List<TrailPoint> line(int n, double step) => [for (var i = 0; i < n; i++) TrailPoint(i * step, 0, 0, 0)];

    test('rewind picks the point closest to the distance along the trail, else the oldest', () {
      final tr = line(10, 5); // 0..45
      expect(rewindIndex(tr, 47, 0, 8), 8); // 47→45 (2), →40 (7), →35 (12): 7 is closest to 8
      expect(rewindIndex(tr, 47, 0, 20), 5); // 17 vs 22: 22 − 20 = 2 < 3
      expect(rewindIndex(tr, 47, 0, 100), 0);
      expect(rewindIndex(const [], 0, 0, 8), -1);
    });

    test('samples every 0.25 s above 3 m/s on the ground, keeps the last 5 s (20 points)', () {
      final f = FlowState(rescue);
      const dt = 1 / 60;
      for (var i = 0; i < 60; i++) {
        f.step(dt, i * dt, fc(x: i.toDouble()), false);
      }
      expect(f.trail.length, 4);
      for (var i = 0; i < 60; i++) {
        f.step(dt, 1 + i * dt, fc(speed: 3), false);
      }
      for (var i = 0; i < 60; i++) {
        f.step(dt, 2 + i * dt, fc(airborne: true), false);
      }
      expect(f.trail.length, 4);
      expect(f.trail.map((p) => p.t).every((t) => t < 1), isTrue);
      for (var i = 0; i < 600; i++) {
        f.step(dt, 3 + i * dt, fc(), false);
      }
      expect(f.trail.length, trailMax);
      // Slow for 5 s: every sample ages out.
      for (var i = 0; i < 6 * 60; i++) {
        f.step(dt, 13 + i * dt, fc(speed: 2, braking: true), false);
      }
      expect(f.trail, isEmpty);
    });

    test('stuck without brake: rewind 8 m, then 20 m, then the road; brake and blocking hold it off', () {
      final f = FlowState(rescue);
      const dt = 1 / 60;
      var t = 0.0;
      for (var i = 0; i < 120; i++, t += dt) {
        f.step(dt, t, fc(x: i * 0.5), false);
      }
      StuckKind? run({double x = 60, bool braking = false, bool blocked = false, double s = 3}) {
        for (var i = 0; i < s * 60; i++, t += dt) {
          final p = f.step(dt, t, fc(x: x, speed: 0.2, braking: braking), blocked);
          if (p != null) return p.kind;
        }
        return null;
      }

      expect(run(blocked: true, s: 2), isNull);
      expect(run(), StuckKind.auto1);
      expect(f.graceT, closeTo(rescueGraceS, 1e-6));
      expect(f.animT, closeTo(rescueAnimS, 1e-6));
      // Between attempts the car drives back towards the trap (new trail points).
      void back() {
        for (var i = 0; i < 60; i++, t += dt) {
          f.step(dt, t, fc(x: 50 + i * 0.16), false);
        }
      }

      back();
      expect(run(), StuckKind.auto2);
      back();
      expect(run(), StuckKind.road);
      expect(f.trail, isEmpty);
      expect(f.events.map((e) => e.kind), [StuckKind.auto1, StuckKind.auto2, StuckKind.road]);
      expect(f.count10(t), 3);
      expect(f.count10(t + 601), 0);
      // Later than 5 s after the last rescue: a first attempt again.
      for (var i = 0; i < 6 * 60; i++, t += dt) {
        f.step(dt, t, fc(x: 200), false);
      }
      expect(run(x: 200), StuckKind.auto1);
      for (var i = 0; i < 2 * 60; i++, t += dt) {
        f.step(dt, t, fc(x: 300), false);
      }
      expect(run(x: 300, braking: true, s: 3.5), isNull);
      expect(f.buttonShown, isTrue);
      // The manual move is logged as a button and does not join the automatic series.
      f.manual(t, 300, 0);
      expect(f.events.last.kind, StuckKind.button);
      expect(f.buttonShown, isFalse);
      expect(f.rescues.length, 1);
    });

    test('the cut trail: the rewind point is the newest point afterwards', () {
      final f = FlowState(rescue);
      const dt = 1 / 60;
      var t = 0.0;
      for (var i = 0; i < 120; i++, t += dt) {
        f.step(dt, t, fc(x: i * 0.2), false);
      }
      RescuePlan? p;
      for (var i = 0; i < 200 && p == null; i++, t += dt) {
        p = f.step(dt, t, fc(x: 24, speed: 0), false);
      }
      expect(p!.kind, StuckKind.auto1);
      expect(f.trail.last, same(p.point));
      expect(24 - p.point!.x, closeTo(8, 1.5)); // samples 3 m apart
    });

    test('stuck.log line', () {
      expect(
        stuckLine(1700000000.7, 'nyc', const StuckEvent(3, StuckKind.road, 1.234, -5.06)),
        '{"t":1700000000,"city":"nyc","x":1.2,"y":-5.1,"kind":"road"}',
      );
      final j = jsonDecode(stuckLine(1, 'nyc', const StuckEvent(3, StuckKind.button, 2, 0))) as Map;
      expect(j, {'t': 1, 'city': 'nyc', 'x': 2, 'y': 0, 'kind': 'button'});
    });
  });

  group('road move (specs/flow.md "Přesun na silnici")', () {
    test('nearest kept ground node, facing the GPS route or the first edge', () async {
      final g = (await flowCity()).graph;
      final a = roadSpot(g, 60, 40, null, tuning.layers.searchM)!;
      expect([a.node, a.x, a.y, a.heading], [1, 0, 0, math.pi]);
      final b = roadSpot(g, 60, 40, [-50, 0, 150, 0], tuning.layers.searchM)!;
      expect(b.heading, 0);
      // A route farther than layers.search_m: the first edge again.
      final c = roadSpot(g, 60, 40, [-50, 500, 150, 500], tuning.layers.searchM)!;
      expect(c.heading, math.pi);
    });
  });

  group('flow scenarios on the synthetic track (scenarios/flow, ±5 %)', () {
    for (final name in starts.keys) {
      test(name, () async {
        final sc = jsonDecode(File('../../scenarios/flow/$name.json').readAsStringSync()) as Map<String, Object?>;
        final inputs = (sc['inputs']! as List).cast<Map<String, Object?>>();
        final m = await runScenario(name, inputs);
        // ignore: avoid_print
        if (Platform.environment['FLOW_RECORD'] != null) print('$name ${jsonEncode(m)}');
        // The plan's acceptance (Prompts/04-METROPOLE_FLOW_PLAN.md 6).
        if (name == 'wall_30') {
          expect(m['along_wall_min_1s_mps'], greaterThanOrEqualTo(14.7));
          expect(m['rescues'], 0);
        } else if (name == 'wall_head_on') {
          expect(m['rescue_kind'], 1);
          expect(m['rescue_after_contact_s'], lessThanOrEqualTo(2.5));
          expect(m['trail_offset_m'], lessThan(0.5));
        } else {
          expect([m['rescue1_kind'], m['rescue2_kind'], m['rescue3_kind']], [1, 2, 3]);
          expect(m['rescue3_on_road'], 1);
        }
        // Recorded values (client W): within the scenario's tolerance (relative, P1 ±5 %).
        for (final MapEntry(:key, :value) in (sc['expect']! as Map<String, Object?>).entries) {
          final e = value! as Map<String, Object?>;
          final want = e['value'] as num?;
          if (want == null) continue;
          final tol = (e['tol']! as num).toDouble();
          expect(m[key], isNotNull, reason: key);
          expect((m[key]! - want).abs(), lessThanOrEqualTo(want.abs() * tol + 1e-9), reason: '$key ${m[key]} vs $want');
        }
      });
    }
  });
}
