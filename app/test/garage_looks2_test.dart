// Garage cosmetics v2 (specs/garage.md v2, specs/art.md v3 "Kosmetika z garáže", "Ikony UI"):
// part counts and labels, procedural decals 4–8, decal and wheel sprites against their fallback,
// UI icon selection. Fixture images stand in for the generated art.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:metropole/game/paint/car_painter.dart';
import 'package:metropole/game/paint/car_shape.dart';
import 'package:metropole/game/paint/car_sprites.dart';
import 'package:metropole/garage/garage_tabs.dart';
import 'package:metropole/l10n/app_localizations_en.dart';
import 'package:metropole/phone/phone_controller.dart' show PhoneAppId;
import 'package:metropole/ui/police_hud.dart' show wantedStarColor;
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
final specs = {
  for (final f in Directory('../content/cars').listSync().whereType<File>())
    for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
};

Future<ui.Image> _solid(int w, int h, int argb, {bool leftHalfOnly = false}) async {
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final c = leftHalfOnly && x >= w / 2 ? 0 : argb;
      bytes[4 * i] = (c >> 16) & 0xff;
      bytes[4 * i + 1] = (c >> 8) & 0xff;
      bytes[4 * i + 2] = c & 0xff;
      bytes[4 * i + 3] = (c >> 24) & 0xff;
    }
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

bool _near(int a, int b, [int tol = 3]) {
  for (final sh in [24, 16, 8, 0]) {
    if ((((a >> sh) & 0xff) - ((b >> sh) & 0xff)).abs() > tol) return false;
  }
  return true;
}

const _ppm = 24.0;

/// One car of [spec] parked at heading 0 (x forward = image right, y left = image down), drawn with
/// [look]: the pixels and the car-space centre offset in metres.
class _Shot {
  _Shot(this.px, this.w, this.h, this.cx, this.cy);
  final List<int> px;
  final int w, h;
  final double cx, cy;

  int at(double x, double y) => px[((cy + y) * _ppm).floor() * w + ((cx + x) * _ppm).floor()];
}

Future<_Shot> _shot(CarSpec spec, CarLook? look) async {
  final hl = spec.lengthM * tuning.carScale / 2, hw = spec.widthM * tuning.carScale / 2;
  final cx = hl + 1, cy = hw + 1;
  final w = (2 * cx * _ppm).ceil(), h = (2 * cy * _ppm).ceil();
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(_ppm, _ppm);
  paintParked(
    c,
    [ParkedCar(carId: spec.id, owner: 'player', x: cx, y: cy, heading: 0)],
    specs,
    tuning,
    shadow: const Color(0x00000000),
    lookOf: look == null ? null : (_) => (look: look, glowMarginM: 0.0, glow: 0.0),
  );
  final img = await rec.endRecording().toImage(w, h);
  return _Shot(await _argb(img), w, h, cx, cy);
}

/// Pixels where [a] and [b] differ, each as its car-space centre.
List<Offset> _diff(_Shot a, _Shot b) => [
  for (var j = 0; j < a.h; j++)
    for (var i = 0; i < a.w; i++)
      if (!_near(a.px[j * a.w + i], b.px[j * a.w + i])) Offset((i + 0.5) / _ppm - a.cx, (j + 0.5) / _ppm - a.cy),
];

bool _inBody(Offset p, List<CarRect> shape) {
  const tol = 1.5 / _ppm;
  return shape.any(
    (r) =>
        r.part == CarPart.body && p.dx >= r.x0 - tol && p.dx <= r.x1 + tol && p.dy >= r.y0 - tol && p.dy <= r.y1 + tol,
  );
}

List<CarRect> _shapeOf(CarSpec s) {
  final hl = s.lengthM * tuning.carScale / 2, hw = s.widthM * tuning.carScale / 2;
  return carShape(s.class_, hl, hw, lengthM: s.lengthM, axle: hl * tuning.drive.axleOffset);
}

/// One catalog car per drawing kind (all classes, the trike and the rickshaw included).
List<CarSpec> _byKind() {
  final seen = <String>{};
  return [
    for (final s in specs.values.toList()..sort((a, b) => a.id.compareTo(b.id)))
      if (seen.add(drawKind(s.class_, s.lengthM))) s,
  ];
}

void main() {
  final previous = carSprites;
  tearDown(() => carSprites = previous);

  group('parts and labels (specs/garage.md v2 "Vzhled")', () {
    test('decal 9, wheels = color.garage.wheels (7), one sprite id per choice ≥ 1', () {
      final cfg = GarageConfig.fromTuning(tuning.garage, const {});
      expect(cfg.parts['decal'], 9);
      expect(cfg.parts['wheels'], Tokens.colorGarageWheels.length);
      expect(cfg.parts['wheels'], 7);
      expect(garageDecalPath(0), isNull);
      expect(garageDecalPath(4), 'garage/decals/stars.png');
      expect(garageDecalPath(8), 'garage/decals/halftone.png');
      expect(garageDecalPath(9), isNull);
      expect(garageWheelPath(0), isNull);
      expect(garageWheelPath(3), 'garage/wheels/five_spoke.png');
      expect(garageWheelPath(6), 'garage/wheels/offroad.png');
      expect(garageWheelPath(7), isNull);
    });

    test('every decal and wheel choice has its own label', () {
      final l = AppLocalizationsEn();
      for (final part in ['decal', 'wheels']) {
        final n = GarageConfig.fromTuning(tuning.garage, const {}).parts[part]!;
        final names = [for (var v = 0; v < n; v++) optionName(l, part, v)];
        expect(names, everyElement(isNotNull), reason: part);
        expect(names.toSet(), hasLength(n), reason: part);
      }
      expect(optionName(l, 'decal', 4), l.garageDecalStars);
      expect(optionName(l, 'decal', 8), l.garageDecalHalftone);
      expect(optionName(l, 'wheels', 3), l.garageWheelsFiveSpoke);
      expect(optionName(l, 'wheels', 6), l.garageWheelsOffroad);
    });
  });

  group('procedural decals 4–8 (specs/garage.md v2 "Kreslení")', () {
    const b = CarRect(CarPart.body, -2.5, -1, 2.5, 1);

    test('stars = three diamonds on the long axis at +0.55, 0, −0.55 hl, 0.5 hw × 0.25 hl', () {
      final stars = decalPolys(4, b);
      expect(stars, hasLength(3));
      final cx = [
        for (final p in stars)
          (p.map((o) => o.dx).reduce((a, c) => a > c ? a : c) + p.map((o) => o.dx).reduce((a, c) => a < c ? a : c)) / 2,
      ]..sort();
      expect(cx[0], closeTo(-0.55 * 2.5, 1e-9));
      expect(cx[1], closeTo(0, 1e-9));
      expect(cx[2], closeTo(0.55 * 2.5, 1e-9));
      for (final p in stars) {
        final xs = p.map((o) => o.dx), ys = p.map((o) => o.dy);
        expect(ys.reduce((a, c) => a > c ? a : c) - ys.reduce((a, c) => a < c ? a : c), closeTo(0.5 * 1, 1e-9));
        expect(xs.reduce((a, c) => a > c ? a : c) - xs.reduce((a, c) => a < c ? a : c), closeTo(0.25 * 2.5, 1e-9));
      }
    });

    test('lightning and waves are drawn as stripes, camo and halftone as checker', () {
      expect(decalPolys(5, b), decalPolys(1, b));
      expect(decalPolys(6, b), decalPolys(1, b));
      expect(decalPolys(7, b), decalPolys(3, b));
      expect(decalPolys(8, b), decalPolys(3, b));
      expect(decalPolys(9, b), isEmpty);
      expect(decalPolys(0, b), isEmpty);
    });

    testWidgets('every decal 1–8 is visible and stays inside the body of every kind (trike too)', (tester) async {
      carSprites = CarSprites.none();
      await tester.runAsync(() async {
        final kinds = _byKind();
        expect(kinds.map((s) => drawKind(s.class_, s.lengthM)), containsAll(['trike', 'rickshaw', 'coupe', 'bus']));
        for (final s in kinds) {
          final plain = await _shot(s, const CarLook());
          final shape = _shapeOf(s);
          for (var d = 1; d < 9; d++) {
            final diff = _diff(await _shot(s, CarLook(decal: d)), plain);
            // The rickshaw's thin frame has no room for the checker band along the sides (as v1).
            final hidden = drawKind(s.class_, s.lengthM) == 'rickshaw' && const {3, 7, 8}.contains(d);
            if (!hidden) expect(diff, isNotEmpty, reason: '${s.id} decal $d');
            final out = diff.where((p) => !_inBody(p, shape)).toList();
            expect(out, isEmpty, reason: '${s.id} decal $d outside the body: ${out.take(3)}');
          }
        }
      });
    });
  });

  group('decal sprites (specs/art.md v3 "Polep")', () {
    test('found through the index only; nothing indexed or not yet decoded = procedural', () async {
      final asked = <String>[];
      final none = CarSprites(has: (_) => false, load: (p) async => throw StateError(p));
      expect(none.decalArt(4), isNull);
      expect(none.wheelArt(3), isNull);
      final img = await _solid(2, 4, 0xffffffff);
      final some = CarSprites(
        has: {'garage/decals/stars.png', 'garage/wheels/mesh.png'}.contains,
        load: (p) async {
          asked.add(p);
          return img;
        },
      );
      var heard = 0;
      some.addListener(() => heard++);
      expect(some.decalArt(4), isNull, reason: 'loading');
      expect(some.decalArt(2), isNull);
      expect(some.wheelArt(4), isNull);
      expect(some.wheelArt(0), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(some.decalArt(4), same(img));
      expect(some.wheelArt(4), same(img));
      expect(some.decalArt(2), isNull);
      expect(asked, ['garage/decals/stars.png', 'garage/wheels/mesh.png']);
      expect(heard, 2);
    });

    testWidgets('procedural car: the sprite replaces the decal, over the body only, under the glass', (tester) async {
      await tester.runAsync(() async {
        carSprites = CarSprites.none();
        final coupe = specs['m0_coupe']!;
        final plain = await _shot(coupe, const CarLook(paint: 0xff202020));
        final proc = await _shot(coupe, const CarLook(paint: 0xff202020, decal: 4));
        final sprites = CarSprites.none();
        sprites.putDecal(4, await _solid(16, 32, 0xffffffff));
        carSprites = sprites;
        final art = await _shot(coupe, const CarLook(paint: 0xff202020, decal: 4));
        final shape = _shapeOf(coupe);
        final diff = _diff(art, plain);
        expect(diff.where((p) => !_inBody(p, shape)), isEmpty);
        // The solid motif covers far more than three procedural diamonds: it replaced them.
        expect(diff.length, greaterThan(3 * _diff(proc, plain).length));
        // Decal colour on the bare body (rear corner), the glass drawn over it unchanged.
        final body = shape.firstWhere((r) => r.part == CarPart.body);
        expect(_near(art.at(body.x0 + 0.3, 0), Tokens.colorGarageDecal, 6), isTrue);
        final glass = shape.firstWhere((r) => r.part == CarPart.glass);
        final gx = (glass.x0 + glass.x1) / 2, gy = (glass.y0 + glass.y1) / 2;
        expect(art.at(gx, gy), plain.at(gx, gy));
        // Other choices without a sprite stay procedural.
        final flames = await _shot(coupe, const CarLook(paint: 0xff202020, decal: 2));
        carSprites = CarSprites.none();
        expect(flames.px, (await _shot(coupe, const CarLook(paint: 0xff202020, decal: 2))).px);
      });
    });

    testWidgets('trike: the sprite decal stays inside its narrow nose and rear body', (tester) async {
      await tester.runAsync(() async {
        final trike = specs.values.firstWhere((s) => drawKind(s.class_, s.lengthM) == 'trike');
        carSprites = CarSprites.none();
        final plain = await _shot(trike, const CarLook(paint: 0xff202020));
        carSprites = CarSprites.none()..putDecal(7, await _solid(16, 32, 0xffffffff));
        final diff = _diff(await _shot(trike, const CarLook(paint: 0xff202020, decal: 7)), plain);
        expect(diff, isNotEmpty);
        expect(diff.where((p) => !_inBody(p, _shapeOf(trike))), isEmpty);
      });
    });

    testWidgets('sprite car: decal composed into the tinted body, masked by paint_mask', (tester) async {
      await tester.runAsync(() async {
        const paint = 0xff2a7fd4;
        final sprites = CarSprites.none();
        final body = await _solid(8, 16, 0xffffffff);
        // Mask: only the top half (the front) is paint.
        final maskBytes = <int>[for (var i = 0; i < 8 * 16; i++) i < 8 * 8 ? 0xffffffff : 0xff000000];
        final mask = await _maskImage(8, 16, maskBytes);
        final s = sprites.put(
          'a',
          const CarSpriteFiles('cars/a/body.png', mask: 'cars/a/paint_mask.png'),
          body,
          mask: mask,
        );
        // Decal: left half of the image opaque.
        final decal = await _solid(8, 16, 0xffffffff, leftHalfOnly: true);
        final plain = await _argb(sprites.body(s, paint));
        final withDecal = await _argb(sprites.body(s, paint, decal: 4, decalImage: decal));
        final procedural = sprites.body(s, paint, decal: 4, paintDecal: (_) {});
        expect(sprites.cachedKeys.map((k) => (k.$3, k.$4)), [(0, false), (4, true), (4, false)]);
        expect(identical(procedural, sprites.body(s, paint, decal: 4, decalImage: decal)), isFalse);
        // The composed image is flipped upside down: rows 8…15 are the front (mask = paint).
        int px(List<int> img, int x, int y) => img[y * 8 + x];
        expect(_near(px(withDecal, 1, 12), Tokens.colorGarageDecal), isTrue, reason: 'front left: decal');
        expect(px(withDecal, 6, 12), px(plain, 6, 12), reason: 'front right: paint');
        expect(_near(px(plain, 1, 12), paint), isTrue);
        expect(px(withDecal, 1, 3), px(plain, 1, 3), reason: 'rear: not paint, no decal');
      });
    });
  });

  group('garage wheel sprites (specs/art.md v3 "Kola")', () {
    testWidgets('procedural car: the sprite fills the tyre rect in the rim colour, else tyre + rim', (tester) async {
      await tester.runAsync(() async {
        final coupe = specs['m0_coupe']!;
        final hl = coupe.lengthM * tuning.carScale / 2, hw = coupe.widthM * tuning.carScale / 2;
        final axle = hl * tuning.drive.axleOffset;
        final (fx, sy) = carWheels(coupe.class_, hl, hw, axle, lengthM: coupe.lengthM).first;
        final ww = hl * 0.36 < hw ? hl * 0.36 : hw, wt = hw * 0.32;
        // A tyre point outside the rim (the rim is the middle half) but under no body part.
        final ex = fx + ww * 0.4, ey = sy.sign * (hw * 0.92 + wt * 0.4);
        final look = CarLook.of(const {'wheels': 3});
        carSprites = CarSprites.none();
        final plain = await _shot(coupe, look);
        expect(_near(plain.at(ex, ey), Tokens.colorCarTyre), isTrue);
        carSprites = CarSprites.none()..putWheel(3, await _solid(16, 16, 0xffffffff));
        final art = await _shot(coupe, look);
        expect(_near(art.at(ex, ey), Tokens.colorGarageWheels[3], 6), isTrue);
        // Stock wheels never use a sprite.
        final stock = await _shot(coupe, CarLook.of(const {'wheels': 0}));
        expect(_near(stock.at(ex, ey), Tokens.colorCarTyre), isTrue);
      });
    });

    testWidgets('sprite car: the garage wheel is scaled to wheel.png and drawn in the atlas, tinted', (tester) async {
      await tester.runAsync(() async {
        final sprites = CarSprites.none();
        final white = await _solid(4, 6, 0xffffffff);
        final s = sprites.put(
          'a',
          const CarSpriteFiles('cars/a/body.png', wheel: 'cars/a/wheel.png'),
          white,
          wheel: white,
        );
        expect(sprites.wheelFor(s, 0), isNull);
        expect(sprites.wheelFor(s, 3), isNull, reason: 'no sprite: wheel.png in the rim colour');
        sprites.putWheel(3, await _solid(128, 128, 0xffffffff));
        final pair = sprites.wheelFor(s, 3)!;
        expect((pair.width, pair.height), (8, 6), reason: 'right | left mirrored at wheel.png size');
        expect(identical(pair, sprites.wheelFor(s, 3)), isTrue);
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        final b = CarSpriteBatch()..addWheel(s, 5, 5, 0, 0, 0, 0, 1, Color(Tokens.colorGarageWheels[3]), garage: pair);
        b.flush(c);
        final out = await _argb(await rec.endRecording().toImage(10, 10));
        expect(_near(out[5 * 10 + 5], Tokens.colorGarageWheels[3]), isTrue);
      });
    });
  });

  testWidgets('contact sheet: decals 1–8 and wheels 1–6, procedural and sprite cars (GARAGE_PNG=<path>)', (
    tester,
  ) async {
    // GARAGE_ART=<dir with garage/decals, garage/wheels> adds cosmetics art not synced yet.
    final out = Platform.environment['GARAGE_PNG'];
    if (out == null) return;
    const synced = 'assets/shared/assets/';
    final extra = Platform.environment['GARAGE_ART'];
    String? fileOf(String path) {
      for (final root in [synced, if (extra != null) '$extra/']) {
        if (File('$root$path').existsSync()) return '$root$path';
      }
      return null;
    }

    Future<ui.Image> load(String path) async {
      final codec = await ui.instantiateImageCodec(File(fileOf(path)!).readAsBytesSync());
      return (await codec.getNextFrame()).image;
    }

    final index = File('${synced}index.json').existsSync()
        ? ArtIndex.fromJson(File('${synced}index.json').readAsStringSync())
        : ArtIndex.empty;
    bool cosmetic(String p) => p.startsWith('garage/') && fileOf(p) != null;
    final procedural = CarSprites(has: cosmetic, load: load);
    final sprites = CarSprites(has: (p) => cosmetic(p) || index.has(p), load: load);
    const ids = ['m0_coupe', 'muscle_brute', 'sedan_crown', 'spec_trike', 'van_courier'];
    await tester.runAsync(() async {
      for (final cs in [procedural, sprites]) {
        for (var i = 1; i < 9; i++) {
          cs.decalArt(i);
          cs.wheelArt(i);
        }
        for (final id in ids) {
          cs.sprite(id);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
      const cell = 15.0, row = 6.5, ppm = 10.0;
      final w = 8 * cell * ppm, h = 2 * ids.length * row * ppm;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(Tokens.colorUiSheet));
      c.scale(ppm, ppm);
      for (final (block, cs) in [procedural, sprites].indexed) {
        carSprites = cs;
        for (final (r, id) in ids.indexed) {
          for (var d = 1; d < 9; d++) {
            final look = CarLook.of({
              'decal': d,
              'wheels': 1 + (d - 1) % 6,
              'paint': 1 + (r + d) % Tokens.colorGaragePaints.length,
            });
            paintParked(
              c,
              [
                ParkedCar(
                  carId: id,
                  owner: 'player',
                  x: cell * (d - 0.5),
                  y: row * (block * ids.length + r + 0.5),
                  heading: 0,
                ),
              ],
              specs,
              tuning,
              lookOf: (_) => (look: look, glowMarginM: 0.0, glow: 0.0),
            );
          }
        }
      }
      final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out)
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  });

  group('UI icons (specs/art.md v3 "Ikony UI")', () {
    tearDown(() => artIndex = ArtIndex.empty);

    test('ui/<id>.png when indexed, else today\'s drawing', () {
      final idx = ArtIndex(const ['ui/feed.png', 'ui/garage.png', 'ui/wanted_star.png', 'ui/weather_rain.png']);
      expect(
        [for (final id in PhoneAppId.values) idx.uiIcon(id.name)],
        [
          for (final id in PhoneAppId.values)
            id == PhoneAppId.feed || id == PhoneAppId.garage ? 'ui/${id.name}.png' : null,
        ],
      );
      expect(idx.uiIcon('wanted_star'), 'ui/wanted_star.png');
      expect(idx.uiIcon('weather_rain'), 'ui/weather_rain.png');
      expect(idx.uiIcon('weather_fog'), isNull);
      expect(ArtIndex.empty.uiIcon('feed'), isNull);
    });

    test('wanted star: one colour, the empty ones at alpha 0.35 (as client W)', () {
      const full = Color(Tokens.colorPoliceStar);
      expect(wantedStarColor(on: true), full);
      final empty = wantedStarColor(on: false);
      expect(empty.a, closeTo(full.a * 0.35, 1e-6));
      expect((empty.r, empty.g, empty.b), (full.r, full.g, full.b));
    });

    testWidgets('ArtIcon: the glyph tinted with modulate when indexed, the fallback otherwise', (tester) async {
      artIndex = ArtIndex(const ['ui/feed.png']);
      const color = Color(0xff123456);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              ArtIcon(
                'feed',
                size: 24,
                color: color,
                fallback: Icon(Icons.dynamic_feed, key: ValueKey('fbFeed')),
              ),
              ArtIcon(
                'map',
                size: 24,
                color: color,
                fallback: Icon(Icons.map, key: ValueKey('fbMap')),
              ),
            ],
          ),
        ),
      );
      final img = tester.widget<Image>(find.byKey(const ValueKey('artIcon:feed')));
      expect(img.color, color);
      expect(img.colorBlendMode, BlendMode.modulate);
      expect((img.width, img.height), (24.0, 24.0));
      expect(find.byKey(const ValueKey('fbFeed')), findsNothing);
      expect(find.byKey(const ValueKey('fbMap')), findsOneWidget);
      expect(find.byKey(const ValueKey('artIcon:map')), findsNothing);
    });
  });
}

Future<ui.Image> _maskImage(int w, int h, List<int> argb) async {
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
