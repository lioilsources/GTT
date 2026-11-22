import 'dart:io';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/game/paint/car_shape.dart';
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

  test('every car shape stays inside its body outline (shadow aside)', () {
    for (final s in specs.values) {
      final hl = s.lengthM * tuning.carScale / 2, hw = s.widthM * tuning.carScale / 2;
      for (final r in shapeOf(s).where((r) => r.part != CarPart.shadow)) {
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
}
