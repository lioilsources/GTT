import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/minigames/registry.dart';
import 'package:metropole/taxi/taxi_hud.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  test('Taxi is enabled in the Gallery as a world minigame', () {
    expect(minigames[MinigameId.taxi], isA<TaxiGame>());
    expect(minigames[MinigameId.taxi]!.meta.engine, 'drive');
  });

  test('shift clock text rounds up to whole seconds', () {
    expect([240.0, 59.2, 0.0, 61.0].map(TaxiHud.clock), ['4:00', '1:00', '0:00', '1:01']);
  });
}
