import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:world_engine/world_engine.dart';

// specs/style.md v2: renders the NYC start by day with WorldRenderer and checks that the cast
// shadows, flat roofs and zebras change the picture. Needs the built pack (build/packs/nyc), so it
// is skipped in a checkout without packs. The PNGs land in run/ (not in git) for a look by eye.

class FilePackSource implements PackSource {
  FilePackSource(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) => File('$root$path').readAsBytes();
}

const root = '../../build/packs/nyc/';
const size = ui.Size(540, 960);

Future<ui.Image> render(WorldRenderer r, CameraRig cam) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  r.render(c, size, cam, playerLayer: 0, drawDynamic: (_, _) {});
  return rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
}

Future<Uint8List> rgba(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

Future<void> savePng(ui.Image img, String name) async {
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('../../run')..createSync(recursive: true);
  File('${dir.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NYC by day: shadows, flat roofs and zebras', () async {
    if (!File('${root}manifest.pb').existsSync()) return; // pack not built
    final t = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final city = await City.load(FilePackSource(root));
    final streamer = ChunkStreamer(city, FilePackSource(root), t);
    await streamer.preload(city.startX, city.startY, city.startHeading);
    final textures = await FacadeTextures.create();
    WorldRenderer renderer({required bool v2}) => WorldRenderer(
      city: city,
      roads: RoadMeshes.build(
        city.graph,
        city.chunkM,
        sidewalkM: t.sidewalkWidthM,
        laneM: t.laneWidthM,
        crosswalks: v2 ? CrosswalkParams.fromTuning(t) : null,
      ),
      streamer: streamer,
      tuning: t,
      textures: textures,
    );

    final cam = CameraRig()..snap(city.startX, city.startY, city.startHeading, t);
    final v2 = renderer(v2: true)..palette = Palette.forCity('nyc');
    final day = await render(v2, cam);
    await savePng(day, 'style_v2_nyc_day.png');
    cam.viewWidth = 3 * t.viewWidthM.slow;
    await savePng(await render(v2, cam), 'style_v2_nyc_day_wide.png');
    v2.palette = Palette.nightPalette;
    await savePng(await render(v2, cam), 'style_v2_nyc_night_wide.png');
    cam.viewWidth = t.viewWidthM.slow;

    // The same frame without zebras and cast shadows must differ visibly.
    t.style.castShadow.nyc = false;
    final v1 = renderer(v2: false)..palette = Palette.forCity('nyc');
    final plain = await rgba(await render(v1, cam));
    final shaded = await rgba(day);
    var diff = 0;
    for (var i = 0; i < plain.length; i += 4) {
      if (plain[i] != shaded[i] || plain[i + 1] != shaded[i + 1] || plain[i + 2] != shaded[i + 2]) diff++;
    }
    expect(diff, greaterThan(plain.length ~/ 4 ~/ 50), reason: 'v2 should change at least 2 % of the pixels');
    streamer.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
