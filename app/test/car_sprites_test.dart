import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart' show CarLook;
import 'package:metropole/game/paint/car_painter.dart';
import 'package:mg_api/mg_api.dart' show ArtIndex;
import 'package:metropole/game/paint/car_sprites.dart';
import 'package:shared_gen/shared_gen.dart';

final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
final specs = {
  for (final f in Directory('../content/cars').listSync().whereType<File>())
    for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
};

/// The synced art (`metro sync`); the rendering test is skipped without it.
const _art = 'assets/shared/assets/';

Future<ui.Image> _pixels(int w, int h, List<int> argb) async {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final c = argb[i];
    bytes[4 * i] = (c >> 16) & 0xff;
    bytes[4 * i + 1] = (c >> 8) & 0xff;
    bytes[4 * i + 2] = c & 0xff;
    bytes[4 * i + 3] = (c >> 24) & 0xff;
  }
  final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
  final d = ui.ImageDescriptor.raw(buf, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
  return (await (await d.instantiateCodec()).getNextFrame()).image;
}

Future<List<int>> _argb(ui.Image img) async {
  final b = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return [
    for (var i = 0; i < img.width * img.height; i++)
      b.getUint8(4 * i + 3) << 24 | b.getUint8(4 * i) << 16 | b.getUint8(4 * i + 1) << 8 | b.getUint8(4 * i + 2),
  ];
}

Future<ui.Image> _file(String path) async {
  final codec = await ui.instantiateImageCodec(File('$_art$path').readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

void main() {
  group('sprite selection (specs/art.md v2 "Kdy")', () {
    bool Function(String) index(List<String> files) => files.toSet().contains;

    test('all required layers → sprite, lights optional', () {
      final f = carSpriteFiles(index(['cars/a/body.png', 'cars/a/paint_mask.png', 'cars/a/wheel.png']), 'a')!;
      expect(f.body, 'cars/a/body.png');
      expect(f.mask, 'cars/a/paint_mask.png');
      expect(f.wheel, 'cars/a/wheel.png');
      expect(f.lights, isNull);
      final l = carSpriteFiles(
        index(['cars/a/body.png', 'cars/a/paint_mask.png', 'cars/a/wheel.png', 'cars/a/lights.png']),
        'a',
      )!;
      expect(l.lights, 'cars/a/lights.png');
    });

    test('body without mask or wheel → procedural (never half)', () {
      expect(carSpriteFiles(index(['cars/a/body.png', 'cars/a/wheel.png']), 'a'), isNull);
      expect(carSpriteFiles(index(['cars/a/body.png', 'cars/a/paint_mask.png']), 'a'), isNull);
      expect(carSpriteFiles(index(['cars/a/paint_mask.png', 'cars/a/wheel.png']), 'a'), isNull);
      expect(carSpriteFiles(index([]), 'a'), isNull);
    });

    test('patrol needs no mask, micro no wheel', () {
      final p = carSpriteFiles(index(['cars/police_patrol/body.png', 'cars/police_patrol/wheel.png']), 'police_patrol', tinted: false)!;
      expect(p.mask, isNull);
      final m = carSpriteFiles(index(['cars/kolo/body.png', 'cars/kolo/paint_mask.png']), 'kolo', wheels: false)!;
      expect(m.wheel, isNull);
    });

    test('CarSprites: not in the index → null and nothing loaded; a failed load stays procedural', () async {
      final asked = <String>[];
      final none = CarSprites(has: (_) => false, load: (p) async => throw StateError(p));
      expect(none.sprite('m0_coupe'), isNull);
      final broken = CarSprites(
        has: (_) => true,
        load: (p) async {
          asked.add(p);
          throw StateError(p);
        },
      );
      expect(broken.sprite('m0_coupe'), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(broken.sprite('m0_coupe'), isNull);
      expect(asked, contains('cars/m0_coupe/body.png'));
    });
  });

  group('tint body × mix(1, paint, mask)', () {
    test('formula per channel', () {
      expect(tintChannel(0.8, 0.5, 0), closeTo(0.8, 1e-12));
      expect(tintChannel(0.8, 0.5, 1), closeTo(0.4, 1e-12));
      expect(tintChannel(1, 0.2, 0.5), closeTo(0.6, 1e-12));
      expect(tintArgb(0xffffffff, 0xff336699, 1), 0xff336699);
      expect(tintArgb(0x80ffffff, 0xff336699, 0), 0x80ffffff);
      expect(tintArgb(0xff808080, 0xff000000, 1) & 0xffffff, 0);
    });

    testWidgets('composed image matches the formula (modulate + colour matrix)', (tester) async {
      await tester.runAsync(() async {
        const paint = 0xff2a7fd4;
        final body = [0xffffffff, 0xffc0c0c0, 0xff202020, 0x00000000];
        final mask = [0xffffffff, 0xff808080, 0xffffffff, 0xff000000];
        final b = await _pixels(2, 2, body), m = await _pixels(2, 2, mask);
        final out = await _argb(composeCarBody(b, m, paint, 2, 2));
        // The composed image is flipped upside down (world canvas y north): row 0 ↔ row 1.
        final flipped = [out[2], out[3], out[0], out[1]];
        for (var i = 0; i < 4; i++) {
          final expected = tintArgb(body[i], paint, (mask[i] & 0xff) / 255);
          final a = flipped[i] >> 24;
          expect(a, body[i] >> 24, reason: 'alpha $i');
          if (a == 0) continue;
          for (final sh in [16, 8, 0]) {
            expect(((flipped[i] >> sh) & 0xff) - ((expected >> sh) & 0xff), inInclusiveRange(-2, 2), reason: 'px $i ch $sh');
          }
        }
      });
    });

    testWidgets('LRU keeps 48 tinted bodies, a hit becomes the newest', (tester) async {
      await tester.runAsync(() async {
        final sprites = CarSprites(has: (_) => false, load: (_) async => throw StateError(''), capacity: 3);
        final img = await _pixels(1, 1, [0xffffffff]);
        final s = sprites.put('a', const CarSpriteFiles('cars/a/body.png'), img, mask: img);
        for (final p in [1, 2, 3]) {
          sprites.body(s, p);
        }
        expect(sprites.cachedBodies, 3);
        final first = sprites.body(s, 1); // hit: 1 becomes the newest
        expect(identical(first, sprites.body(s, 1)), isTrue);
        sprites.body(s, 4); // evicts 2
        expect(sprites.cachedKeys.map((k) => k.$2), [3, 1, 4]);
        expect(carSpriteCacheSize, 48);
        // The patrol (no mask) shares one untinted body whatever the paint.
        final p = sprites.put('p', const CarSpriteFiles('cars/p/body.png'), img);
        expect(identical(sprites.body(p, 1), sprites.body(p, 2)), isTrue);
      });
    });
  });

  testWidgets('parked sprite cars, traffic and patrol render (SPRITES_PNG=<path> saves them)', (tester) async {
    if (!File('${_art}index.json').existsSync()) return;
    final index = ArtIndex.fromJson(File('${_art}index.json').readAsStringSync());
    final ids = ['m0_coupe', 'taxi_metro', 'hatch_pip', 'sedan_harbor', 'sedan_crown', 'van_courier', 'mini_pebble', 'pickup_hauler', 'muscle_brute', 'lidovka'];
    final previous = carSprites;
    addTearDown(() => carSprites = previous);
    late ui.Image scene;
    await tester.runAsync(() async {
      final sprites = CarSprites(has: index.has, load: _file);
      carSprites = sprites;
      for (final id in [...ids, 'traffic_sedan']) {
        sprites.sprite(id);
      }
      sprites.sprite('police_patrol', tinted: false);
      // Let the lazy loads finish.
      for (var i = 0; i < 50 && [...ids, 'traffic_sedan', 'police_patrol'].any((id) => sprites.sprite(id) == null); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      for (final id in [...ids, 'traffic_sedan']) {
        expect(sprites.sprite(id), isNotNull, reason: id);
      }
      expect(sprites.sprite('police_patrol', tinted: false), isNotNull);

      const ppm = 6.0, cols = 5, cell = 16.0;
      const w = cols * cell * ppm, h = 4 * cell * ppm;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
      c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(Tokens.colorUiSheet));
      // World canvas like the camera: metres, y north.
      c.save();
      c.translate(0, h);
      c.scale(ppm, -ppm);
      final parked = [
        for (final (i, id) in ids.indexed)
          ParkedCar(
            carId: id,
            owner: i == 1 ? 'player' : 'npc',
            x: cell * (i % cols + 0.5),
            y: cell * (3.5 - i ~/ cols),
            heading: math.pi / 2 + (i.isOdd ? 0.4 : 0),
          ),
      ];
      final look = (
        look: CarLook(paint: Tokens.colorGaragePaints[2], decal: 2, rim: Tokens.colorGarageWheels[2]),
        glowMarginM: tuning.garage.glowMarginM,
        glow: 0.0,
      );
      paintParked(c, parked, specs, tuning, lookOf: (p) => p.owner == 'player' ? look : null);
      // Traffic and patrol bodies (straight wheels, lights at night), as the traffic painter adds them.
      final b = CarSpriteBatch();
      final traffic = sprites.sprite('traffic_sedan')!, police = sprites.sprite('police_patrol', tinted: false)!;
      final k = tuning.carScale / carSpritePxPerM;
      for (var i = 0; i < 4; i++) {
        final x = cell * (i + 0.5), y = cell * 1.5;
        b.addBody(sprites.body(traffic, Tokens.colorTrafficBodies[i]), x, y, math.pi / 2, k);
        b.addLights(traffic.lights!, x, y, math.pi / 2, k, rearOnly: i.isEven);
      }
      b.addBody(sprites.body(police, null), cell * 4.5, cell * 1.5, math.pi / 2, k);
      b.addBody(sprites.body(police, null), cell * 2, cell * 0.5, 0, k);
      b.addLights(police.lights!, cell * 2, cell * 0.5, 0, k, rearOnly: false);
      b.flush(c);
      c.restore();
      // The garage preview draws the sprite too (sideways, with looks), in the player-car path.
      c.save();
      c.translate(3 * cell * ppm, 3 * cell * ppm);
      paintCarPreview(c, const Size(2 * cell * ppm, cell * ppm), specs['muscle_brute']!, tuning, look, sideways: true);
      c.restore();
      scene = await rec.endRecording().toImage(w.toInt(), h.toInt());
      expect(sprites.cachedBodies, lessThanOrEqualTo(carSpriteCacheSize));
      final out = Platform.environment['SPRITES_PNG'];
      if (out != null) {
        final png = await scene.toByteData(format: ui.ImageByteFormat.png);
        File(out)
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }
      // Something car-coloured was drawn at the first parked car (not just the background).
      final px = await _argb(scene);
      final at = (cell * 0.5 * ppm).toInt() + (cell * 0.5 * ppm).toInt() * w.toInt();
      expect(px[at], isNot(px[0]));
    });
  });
}
