import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/world_engine.dart';

// specs/models.md v4, client F: roof plans from models.pb replace the pack buildings from above.
// The Prague checks need the built pack (build/packs/prague) and are skipped without it; the
// rendered PNGs land in run/ (not in git) for a look by eye.

class FilePackSource implements PackSource {
  FilePackSource(this.root, {this.missing = const {}});
  final String root;
  final Set<String> missing;
  @override
  Future<Uint8List> read(String path) {
    if (missing.contains(path)) throw FileSystemException('missing', path);
    return File('$root$path').readAsBytes();
  }
}

Uint8List gz(List<int> b) => Uint8List.fromList(const GZipEncoder().encodeBytes(b));

Tuning loadTuning() => Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());

/// A square plan polygon, side [s] m at (x, y) m, CCW, two triangles.
pb.PlanPoly square(double x, double y, double s, {double h = 10, int shade = 0}) {
  int dm(double v) => (v * 10).round();
  return pb.PlanPoly(
    points: [dm(x), dm(y), dm(x + s), dm(y), dm(x + s), dm(y + s), dm(x), dm(y + s)],
    ringEnds: [4],
    triangles: [0, 1, 2, 0, 2, 3],
    heightM: h,
    shade: shade,
    baseZDm: 55,
  );
}

const pragueRoot = '../../build/packs/prague/';
const size = ui.Size(540, 960);

Future<Uint8List> rgba(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

Future<void> savePng(ui.Image img, String name) async {
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('../../run')..createSync(recursive: true);
  File('${dir.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prepareModels: plan by height, shade, replaces per chunk, bounds', () {
    final m = pb.Models(models: [
      pb.Model(
        landmarkId: 'tower',
        roofPlan: [square(0, 0, 20, h: 30, shade: 3), square(-10, -10, 40, h: 12, shade: 1)],
        replaces: [
          pb.BuildingRef(chunkX: 0, chunkY: 0, index: 4),
          pb.BuildingRef(chunkX: 0, chunkY: 0, index: 7),
          pb.BuildingRef(chunkX: -1, chunkY: 0, index: 0),
        ],
        tris: 99,
      ),
      // No roof plan: nothing replaces its footprints, so it is dropped.
      pb.Model(landmarkId: 'empty', replaces: [pb.BuildingRef(chunkX: 3, chunkY: 3, index: 1)]),
    ]);
    final models = prepareModels(m);
    expect(models.map((e) => e.landmarkId), ['tower']);
    final t = models.single;
    expect(t.plan.map((b) => b.height), [12, 30]);
    expect(t.plan.map((b) => b.planShade), [1, 3]);
    expect(t.plan.every((b) => b.landmark == 1 && !b.collide && b.minHeight == 0), isTrue);
    expect(t.plan.first.xy.sublist(0, 2), [-10, -10]);
    expect(t.plan.first.roof, [0, 1, 2, 0, 2, 3]);
    expect(t.replaces[City.chunkKey(0, 0)], {4, 7});
    expect(t.replaces[City.chunkKey(-1, 0)], {0});
    expect(t.cx, closeTo(10, 1e-6));
    expect(t.cy, closeTo(10, 1e-6));
    expect(t.radius, closeTo(28.28, 0.01));
    expect(t.tris, 99);
    expect(replacedBuildings(models).keys, unorderedEquals([City.chunkKey(0, 0), City.chunkKey(-1, 0)]));
  });

  test('loadModels tolerates version 0, a missing file and garbage', () {
    final bytes = gz(pb.Models(models: [pb.Model(landmarkId: 'a', roofPlan: [square(0, 0, 5)])]).writeToBuffer());
    expect(loadModels(2, bytes).single.landmarkId, 'a');
    expect(loadModels(0, bytes), isEmpty);
    expect(loadModels(2, null), isEmpty);
    expect(loadModels(2, Uint8List.fromList([1, 2, 3])), isEmpty);
  });

  test('plan roof light is 0.7 + 0.1 × shade and the palettes take color.model roof', () {
    for (var s = 0; s < 4; s++) {
      expect(planRoofLight(s), closeTo(0.7 + 0.1 * s, 1e-12));
    }
    expect(Palette.forCity('prague').modelRoof, const ui.Color(Tokens.colorModelDayRoof));
    expect(Palette.day.modelRoof, const ui.Color(Tokens.colorModelDayRoof));
    expect(Palette.nightPalette.modelRoof, const ui.Color(Tokens.colorModelNightRoof));
    expect(Palette.forCity('prague').wet(0.3).modelRoof, const ui.Color(Tokens.colorModelDayRoof));
  });

  test('prepareChunk keeps the Chunk.buildings index for replaces', () {
    pb.Building b(int x, {bool degenerate = false}) => pb.Building(
      rings: degenerate ? [x, 0, x + 10, 0] : [x, 0, x + 100, 0, x + 100, 100, x, 100],
      ringEnds: degenerate ? [2] : [4],
      roof: degenerate ? [] : [0, 1, 2, 0, 2, 3],
      heightM: 10,
      collide: true,
    );
    final c = prepareChunk(gz(pb.Chunk(x: 0, y: 0, buildings: [b(0), b(200, degenerate: true), b(400)]).writeToBuffer()));
    expect(c.buildings.map((e) => e.index), [0, 2]);
    expect(c.buildings.every((e) => e.planShade == -1), isTrue);
  });

  test('Prague: models.pb loads, replaced buildings stay for collisions but are hidden', () async {
    if (!File('${pragueRoot}models.pb').existsSync()) return; // pack not built
    final t = loadTuning();
    final city = await City.load(FilePackSource(pragueRoot));
    expect(city.manifest.modelsVersion, greaterThanOrEqualTo(2));
    final ids = city.models.map((m) => m.landmarkId).toSet();
    expect(ids, contains('prague_castle'));
    for (final m in city.models) {
      expect(m.plan.length, lessThanOrEqualTo(t.models.roofPlanMaxPolys));
      for (var k = 1; k < m.plan.length; k++) {
        expect(m.plan[k].height, greaterThanOrEqualTo(m.plan[k - 1].height));
      }
      for (final b in m.plan) {
        expect(b.roof.every((i) => i < b.vertexCount), isTrue);
      }
    }
    // Every replaced building exists in its chunk and is hidden, but ChunkData keeps it.
    final castle = city.models.firstWhere((m) => m.landmarkId == 'prague_castle');
    final streamer = ChunkStreamer(city, FilePackSource(pragueRoot), t);
    await streamer.preload(castle.cx, castle.cy, 0);
    var hidden = 0;
    for (final c in streamer.chunks) {
      final want = city.replaced[c.key] ?? const <int>{};
      final idx = {for (final b in c.data.buildings) b.index};
      expect(idx.containsAll(want), isTrue, reason: 'chunk ${c.data.x},${c.data.y}');
      for (final b in c.data.buildings) {
        expect(c.shows(b), !want.contains(b.index));
        if (!c.shows(b)) hidden++;
      }
    }
    expect(hidden, greaterThan(0));
    // models.enabled off: nothing is hidden.
    t.models.enabled = false;
    expect(streamer.hiddenIn(streamer.chunks.first.key), isEmpty);
    streamer.dispose();
  });

  test('Prague: a pack without models.pb draws footprints', () async {
    if (!File('${pragueRoot}manifest.pb').existsSync()) return; // pack not built
    final city = await City.load(FilePackSource(pragueRoot, missing: {'models.pb'}));
    expect(city.models, isEmpty);
    expect(city.replaced, isEmpty);
  });

  test('Prague Castle from above: the roof plan replaces the footprints', () async {
    if (!File('${pragueRoot}models.pb').existsSync()) return; // pack not built
    final t = loadTuning();
    final city = await City.load(FilePackSource(pragueRoot));
    final castle = city.models.firstWhere((m) => m.landmarkId == 'prague_castle');
    final textures = await FacadeTextures.create();

    Future<ui.Image> frame({required bool models, bool night = false}) async {
      t.models.enabled = models;
      final streamer = ChunkStreamer(city, FilePackSource(pragueRoot), t);
      // The car south of the castle so the plan leans away from the vanishing point.
      final px = castle.cx, py = castle.cy - 120;
      await streamer.preload(px, py, 1.5708);
      final r = WorldRenderer(
        city: city,
        roads: RoadMeshes.build(city.graph, city.chunkM, sidewalkM: t.sidewalkWidthM, laneM: t.laneWidthM),
        streamer: streamer,
        tuning: t,
        textures: textures,
      )..palette = night ? Palette.nightPalette : Palette.forCity('prague');
      final cam = CameraRig()..snap(px, py, 1.5708, t);
      cam.viewWidth = 2.5 * t.viewWidthM.slow;
      final rec = ui.PictureRecorder();
      r.render(ui.Canvas(rec), size, cam, playerLayer: 0, drawDynamic: (_, _) {});
      final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
      streamer.dispose();
      return img;
    }

    final on = await frame(models: true);
    final off = await frame(models: false);
    await savePng(on, 'models_prague_castle_plan.png');
    await savePng(off, 'models_prague_castle_footprints.png');
    await savePng(await frame(models: true, night: true), 'models_prague_castle_plan_night.png');

    // The roof colour × shade appears only with the plan.
    final pal = Palette.forCity('prague');
    final roofs = [
      for (var s = 0; s < 4; s++)
        [for (final ch in [pal.modelRoof.r, pal.modelRoof.g, pal.modelRoof.b]) (ch * 255 * planRoofLight(s)).clamp(0, 255).toInt()],
    ];
    int count(Uint8List px) {
      var n = 0;
      for (var i = 0; i < px.length; i += 4) {
        for (final c in roofs) {
          if ((px[i] - c[0]).abs() <= 2 && (px[i + 1] - c[1]).abs() <= 2 && (px[i + 2] - c[2]).abs() <= 2) {
            n++;
            break;
          }
        }
      }
      return n;
    }

    final withPlan = count(await rgba(on)), without = count(await rgba(off));
    expect(withPlan, greaterThan(2000));
    expect(without, lessThan(withPlan ~/ 10));
  });
}
