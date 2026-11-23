import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:world_engine/core.dart';

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
CarSpec spec() => parseCarSpec(File('../../content/cars/m0_coupe.json').readAsStringSync());

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  const root = '../../build/packs/nyc/';
  final has = File('${root}manifest.pb').existsSync();
  late City city;
  late PackSource src;
  setUpAll(() async {
    await initializeForge2D();
    if (!has) return;
    src = _FilePack(root);
    city = await City.load(src);
  });

  test('crashes for world minigames: min speed, one per 500 ms, walls, rails and traffic hooks', () {
    final d = DriveWorld(city: city, spec: spec(), tuning: tuning);
    final hits = WorldHits(d, 2.0);
    expect(hits.take(0), false);
    d.onWall!(1.99);
    expect(hits.take(10), false, reason: 'below hit_min_mps');
    d.onWall!(2.0);
    expect(hits.take(100), true);
    d.onRail!(5);
    expect(hits.take(599), false, reason: 'within 500 ms of the last one: dropped');
    expect(hits.take(700), false, reason: 'the dropped one is not kept');
    d.onRail!(5);
    expect(hits.take(600 + 100), true);
    hits.dispose();
    expect([d.onWall, d.onRail], [null, null]);
    d.dispose();
  }, skip: has ? false : 'no pack');

  test('driving into a building wall reports the speed along the normal', () async {
    final d = DriveWorld(city: city, spec: spec(), tuning: tuning);
    final cx = city.startX, cy = city.startY;
    final chunks = <ChunkData>[];
    for (final c in city.manifest.chunks) {
      final m = city.chunkM;
      if (((c.x + 0.5) * m - cx).abs() > 400 || ((c.y + 0.5) * m - cy).abs() > 400) continue;
      final data = prepareChunk(await src.read(chunkPath(c.x, c.y)));
      chunks.add(data);
      d.addChunk(data);
    }
    final walls = <double>[];
    d.onWall = walls.add;
    var tries = 0;
    // Head-on at 10 m/s into the middle of a long wall segment, 4 m out.
    for (final b in [for (final c in chunks) ...c.buildings.where((b) => b.collide)]) {
      if (tries >= 20 || walls.isNotEmpty) break;
      final n = b.ringEnds.first;
      var mx = 0.0, my = 0.0;
      for (var i = 0; i < n; i++) {
        mx += b.xy[2 * i] / n;
        my += b.xy[2 * i + 1] / n;
      }
      final ax = b.xy[0], ay = b.xy[1], bx = b.xy[2], by = b.xy[3];
      final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      if (len < 10) continue;
      final px = (ax + bx) / 2, py = (ay + by) / 2;
      var nx = -(by - ay) / len, ny = (bx - ax) / len;
      if (nx * (px - mx) + ny * (py - my) < 0) (nx, ny) = (-nx, -ny);
      tries++;
      d.spawn(px + nx * 4, py + ny * 4, math.atan2(-ny, -nx));
      d.car.body.linearVelocity = Vector2(-nx * 10, -ny * 10);
      for (var i = 0; i < 30 && walls.isEmpty; i++) {
        d.update(1 / 60);
      }
    }
    expect(walls, isNotEmpty);
    expect(walls.first, inInclusiveRange(5, 12));
    d.dispose();
  }, skip: has ? false : 'no pack');

  test('dispose leaves hooks set by others alone', () {
    final d = DriveWorld(city: city, spec: spec(), tuning: tuning);
    final a = WorldHits(d, 1);
    void other(double _) {}
    d.onWall = other;
    a.dispose();
    expect(d.onWall, other);
    d.dispose();
  }, skip: has ? false : 'no pack');
}
