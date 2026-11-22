import 'dart:io';
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart' show CarLook;
import 'package:metropole/game/paint/car_shape.dart';
import 'package:metropole/garage/garage_tabs.dart';
import 'package:shared_gen/shared_gen.dart';

final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
final specs = {
  for (final f in Directory('../content/cars').listSync().whereType<File>())
    for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
};

void main() {
  List<CarRect> shapeOf(CarSpec s) {
    final hl = s.lengthM * tuning.carScale / 2, hw = s.widthM * tuning.carScale / 2;
    return carShape(s.class_, hl, hw, lengthM: s.lengthM);
  }

  test('every car shape stays inside its body outline (shadow and the off-road spare aside)', () {
    for (final s in specs.values) {
      final hl = s.lengthM * tuning.carScale / 2, hw = s.widthM * tuning.carScale / 2;
      for (final r in shapeOf(s).where((r) => r.part != CarPart.shadow && r.part != CarPart.spare)) {
        expect(r.x0, greaterThanOrEqualTo(-hl - 1e-9), reason: '${s.id} ${r.part}');
        expect(r.x1, lessThanOrEqualTo(hl + 1e-9), reason: '${s.id} ${r.part}');
        expect(r.y0, greaterThanOrEqualTo(-hw - 1e-9), reason: '${s.id} ${r.part}');
        expect(r.y1, lessThanOrEqualTo(hw + 1e-9), reason: '${s.id} ${r.part}');
        expect(r.x0, lessThan(r.x1), reason: '${s.id} ${r.part}');
        expect(r.y0, lessThan(r.y1), reason: '${s.id} ${r.part}');
      }
    }
  });

  test('micro: scooter under 1.5 m, bicycle otherwise; two wheels, a rider, no lights', () {
    final scooter = shapeOf(specs['kolobezka']!), bike = shapeOf(specs['kolo']!);
    expect(specs['kolobezka']!.lengthM, lessThan(scooterMaxLengthM));
    expect(specs['kolo']!.lengthM, greaterThanOrEqualTo(scooterMaxLengthM));
    for (final shape in [scooter, bike]) {
      expect(shape.where((r) => r.part == CarPart.wheel).length, 2);
      expect(shape.where((r) => r.part == CarPart.rider).length, 1);
      expect(shape.any((r) => r.part == CarPart.body), isTrue);
      expect(shape.any((r) => r.part == CarPart.head || r.part == CarPart.tail), isFalse);
      // One wheel at the front, one at the back, both on the centre line.
      final wheels = shape.where((r) => r.part == CarPart.wheel).toList();
      expect(wheels.map((r) => (r.x0 + r.x1).sign).toSet(), {-1.0, 1.0});
      for (final w in wheels) {
        expect(w.y0 + w.y1, closeTo(0, 1e-9));
      }
    }
    // The bicycle frame is narrower than the scooter deck (relative to the width).
    double deck(List<CarRect> s, CarSpec c) =>
        s.firstWhere((r) => r.part == CarPart.body).y1 / (c.widthM * tuning.carScale / 2);
    expect(deck(bike, specs['kolo']!), lessThan(deck(scooter, specs['kolobezka']!)));
    // Same class, same scale: only length_m picks the shape.
    expect(carShape('micro', 1, 0.5, lengthM: 1.2).length, isNot(carShape('micro', 1, 0.5, lengthM: 1.8).length));
  });

  test('other classes keep their headlights and tail lights', () {
    for (final s in specs.values.where((s) => s.class_ != 'micro')) {
      final shape = shapeOf(s);
      expect(shape.where((r) => r.part == CarPart.head).length, 2, reason: s.id);
      expect(shape.where((r) => r.part == CarPart.tail).length, 2, reason: s.id);
    }
  });

  test('supersport (Vega Roadster) draws with its own low cabin, not the coupe fallback', () {
    final s = specs['vega_roadster']!;
    expect(s.class_, 'supersport');
    final cabin = shapeOf(s).firstWhere((r) => r.part == CarPart.cabin);
    final hl = s.lengthM * tuning.carScale / 2, hw = s.widthM * tuning.carScale / 2;
    final coupe = carShape('coupe', hl, hw).firstWhere((r) => r.part == CarPart.cabin);
    expect(cabin.x0, isNot(coupe.x0));
    expect(cabin.x1, lessThan(coupe.x1));
  });

  group('v2: one shape per class (specs/cars.md "Kreslení", F-045)', () {
    const hl = 6.0, hw = 2.4;
    String sig(List<CarRect> s) => [
      for (final r in s)
        '${r.part.name}:${r.x0.toStringAsFixed(3)},${r.y0.toStringAsFixed(3)},'
            '${r.x1.toStringAsFixed(3)},${r.y1.toStringAsFixed(3)}:${r.color}',
    ].join(' ');
    final kinds = {
      for (final c in carClassOrder.where((c) => c != 'special' && c != 'micro')) c: carShape(c, hl, hw),
      'foodTruck': carShape('special', hl, hw, lengthM: 7),
      'trike': carShape('special', hl, hw, lengthM: 3.2),
      'rickshaw': carShape('special', hl, hw, lengthM: 2.6),
    };

    test('the class order mirrors the schema enum', () {
      final schema = File('../schema/car.schema.json').readAsStringSync();
      final m = RegExp(r'"class": \{"enum": \[([^\]]*)\]').firstMatch(schema)!;
      expect(carClassOrder, [for (final s in m.group(1)!.split(',')) s.trim().replaceAll('"', '')]);
    });

    test('every class (and each special variant) has its own shape', () {
      final seen = <String, String>{};
      for (final MapEntry(:key, :value) in kinds.entries) {
        final s = sig(value);
        expect(seen[s], isNull, reason: '$key draws like ${seen[s]}');
        seen[s] = key;
      }
    });

    test('special splits by length_m: food truck ≥ 5 m, trike 2.8–5 m, rickshaw below', () {
      expect(drawKind('special', 7.0), 'foodTruck');
      expect(drawKind('special', 5.0), 'foodTruck');
      expect(drawKind('special', 4.99), 'trike');
      expect(drawKind('special', 2.8), 'trike');
      expect(drawKind('special', 2.79), 'rickshaw');
      expect(drawKind('sedan', 2.0), 'sedan');
      final byId = {
        for (final id in ['spec_grill', 'spec_trike', 'spec_rickshaw']) id: drawKind('special', specs[id]!.lengthM),
      };
      expect(byId, {'spec_grill': 'foodTruck', 'spec_trike': 'trike', 'spec_rickshaw': 'rickshaw'});
    });

    test('class details use the carDetail tokens', () {
      Set<int?> colors(String k) => {for (final r in kinds[k]!) r.color};
      expect(colors('kombi'), contains(Tokens.colorCarDetailRoofRail));
      expect(colors('supersport'), contains(Tokens.colorCarDetailSpoiler));
      expect(colors('veteran'), contains(Tokens.colorCarDetailFender));
      expect(colors('offroad'), contains(Tokens.colorCarDetailSpare));
      expect(colors('van'), contains(Tokens.colorCarDetailCargoRoof));
      expect(colors('limo'), contains(Tokens.colorCarDetailLimoPillar));
      expect(colors('bus'), contains(Tokens.colorCarDetailBusRoofUnit));
      expect(colors('foodTruck'), containsAll([Tokens.colorCarDetailAwningA, Tokens.colorCarDetailAwningB]));
      expect(colors('rickshaw'), contains(Tokens.colorCarDetailCanopy));
      // The food truck's awning hangs on the right side (y < 0).
      for (final r in kinds['foodTruck']!.where((r) => r.color == Tokens.colorCarDetailAwningB)) {
        expect(r.y1, lessThan(0));
      }
    });

    test('van and bus have no cabin; the rest of the four-wheelers do', () {
      for (final k in ['van', 'bus', 'foodTruck', 'rickshaw']) {
        expect(kinds[k]!.any((r) => r.part == CarPart.cabin), isFalse, reason: k);
      }
      for (final k in ['mini', 'sedan', 'kombi', 'supersport', 'veteran', 'offroad', 'limo', 'trike']) {
        expect(kinds[k]!.where((r) => r.part == CarPart.cabin).length, 1, reason: k);
      }
      final sport = kinds['supersport']!.firstWhere((r) => r.part == CarPart.cabin);
      expect([sport.x0 / hl, sport.x1 / hl, sport.y1 / hw], pairwiseCompare([-0.3, 0.15, 0.7], _near, 'close to'));
    });

    test('wheels: four at the axles, the bus at 0.60 / −0.70 hl, trike and rickshaw three', () {
      const axle = hl * 0.62;
      expect(carWheels('sedan', hl, hw, axle).map((w) => w.$1).toSet(), {axle, -axle});
      expect(carWheels('bus', hl, hw, axle).map((w) => w.$1).toSet(), {hl * 0.6, -hl * 0.7});
      expect(carWheels('micro', hl, hw, axle), isEmpty);
      for (final len in [3.2, 2.6]) {
        final painted = carWheels('special', hl, hw, axle, lengthM: len);
        expect(painted.map((w) => w.$1).toSet(), {-axle});
        final front = carShape('special', hl, hw, lengthM: len).where((r) => r.part == CarPart.wheel).single;
        expect((front.x0 + front.x1) / 2, closeTo(hl * 0.75, 1e-9));
        expect(front.y0 + front.y1, closeTo(0, 1e-9));
      }
      expect(carWheels('special', hl, hw, axle, lengthM: 7).length, 4);
    });

    test('veteran: narrow body, a fender over each wheel', () {
      const axle = hl * 0.5;
      final v = carShape('veteran', hl, hw, axle: axle);
      expect(v.firstWhere((r) => r.part == CarPart.body).y1, closeTo(hw * 0.8, 1e-9));
      final fenders = v.where((r) => r.color == Tokens.colorCarDetailFender).toList();
      expect(fenders.length, 4);
      expect({for (final f in fenders) ((f.x0 + f.x1) / 2).abs()}.map((x) => x.toStringAsFixed(6)).toSet(), {
        axle.toStringAsFixed(6),
      });
    });
  });

  group('the garage sale list order (specs/cars.md v2 "Garáž")', () {
    test('city cars first, then by class, price, id', () {
      final prague = saleOrder(specs.values, const ['m0_coupe'], 'prague');
      final firstOther = prague.indexWhere((s) => !s.tags.contains('prague'));
      expect(prague.take(firstOther).every((s) => s.tags.contains('prague')), isTrue);
      expect(prague.skip(firstOther).any((s) => s.tags.contains('prague')), isFalse);
      expect(prague.map((s) => s.id), isNot(contains('m0_coupe')));
      expect(prague.take(firstOther).map((s) => s.id), ['hatch_pip', 'lidovka', 'vega_roadster', 'kolobezka', 'kolo']);
      for (final (city, list) in [('prague', prague), ('nyc', saleOrder(specs.values, const [], 'nyc'))]) {
        expect(list.length, specs.length - (city == 'prague' ? 1 : 0));
        for (var i = 1; i < list.length; i++) {
          final a = list[i - 1], b = list[i];
          final ga = a.tags.contains(city) ? 0 : 1, gb = b.tags.contains(city) ? 0 : 1;
          final ka = carClassOrder.indexOf(a.class_), kb = carClassOrder.indexOf(b.class_);
          if (ga != gb) {
            expect(ga, lessThan(gb), reason: '${a.id} before ${b.id}');
          } else if (ka != kb) {
            expect(ka, lessThan(kb), reason: '${a.id} before ${b.id}');
          } else if (a.price != b.price) {
            expect(a.price, lessThan(b.price), reason: '${a.id} before ${b.id}');
          } else {
            expect(a.id.compareTo(b.id), lessThan(0));
          }
        }
      }
    });
  });

  testWidgets('contact sheet: every car with the real painter, catalog and with looks', (tester) async {
    if (_png) await tester.runAsync(_loadFonts);
    final cars = saleOrder(specs.values, const [], 'nyc');
    // Looks cycle through decals, rims, paints and underglow so each shape shows them all.
    CarLook lookFor(int i) => CarLook(
      paint: Tokens.colorGaragePaints[i % Tokens.colorGaragePaints.length],
      decal: 1 + i % 3,
      rim: Tokens.colorGarageWheels[1 + i % (Tokens.colorGarageWheels.length - 1)],
      glow: Tokens.colorGarageGlow[i % Tokens.colorGarageGlow.length],
    );
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    const text = TextStyle(
      color: Color(Tokens.colorUiText),
      fontSize: 11,
      fontFamily: 'Roboto',
      decoration: TextDecoration.none,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(Tokens.colorUiSheet),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (i, s) in cars.indexed)
                      SizedBox(
                        width: 140,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: CarPreview(spec: s, look: const CarLook(), tuning: tuning, height: 150),
                                ),
                                Expanded(
                                  child: CarPreview(spec: s, look: lookFor(i), tuning: tuning, height: 150),
                                ),
                              ],
                            ),
                            Text('${s.class_} · ${drawKind(s.class_, s.lengthM)}', style: text),
                            Text(s.id, style: text),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CarPreview), findsNWidgets(cars.length * 2));
    expect(tester.takeException(), isNull);
    if (_png) {
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('../run/car_classes.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}

/// `CARS_PNG=1 flutter test test/car_shape_test.dart` writes the contact sheet to
/// ../run/car_classes.png (not in git).
final _png = Platform.environment['CARS_PNG'] != null;

Future<void> _loadFonts() async {
  const dir = '/bin/cache/artifacts/material_fonts/';
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final l = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
    final file = File('$root$dir$f');
    if (file.existsSync()) l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await l.load();
}

bool _near(num a, num b) => (a - b).abs() < 1e-9;
