import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:world_engine/world_engine.dart';

// specs/style.md v1: city day palettes and the risograph switch.
void main() {
  test('nyc maps color.city.nyc with the shared light.day', () {
    final p = Palette.forCity('nyc');
    expect(p.land, const Color(Tokens.colorCityNycLand));
    expect(p.water, const Color(Tokens.colorCityNycWater));
    expect(p.asphalt, const Color(Tokens.colorCityNycAsphalt));
    expect(p.centerLine, const Color(Tokens.colorCityNycCenterLine));
    expect(p.landmark, const Color(Tokens.colorCityNycLandmark));
    expect(p.facades, [for (final c in Tokens.colorCityNycFacades) Color(c)]);
    expect(p.shadow, const Color(Tokens.colorCityNycShadow));
    expect(p.roofLight, Tokens.lightDayRoofLight);
    expect(p.sunX, Tokens.lightDaySunX);
    expect(p.ambient, Tokens.lightDayAmbient);
    expect(p.night, isFalse);
    expect(p.inks, isEmpty);
  });

  test('prague maps color.city.prague including inks', () {
    final p = Palette.forCity('prague');
    expect(p.land, const Color(Tokens.colorCityPragueLand));
    expect(p.plaza, const Color(Tokens.colorCityPraguePlaza));
    expect(p.rail, const Color(Tokens.colorCityPragueRail));
    expect(p.bridgeEdge, const Color(Tokens.colorCityPragueBridgeEdge));
    expect(p.facades, [for (final c in Tokens.colorCityPragueFacades) Color(c)]);
    expect(p.shadow, const Color(Tokens.colorCityPragueShadow));
    expect(p.inks, [for (final c in Tokens.colorCityPragueInks) Color(c)]);
    expect(p.roofLight, Tokens.lightDayRoofLight);
  });

  test('tokyo maps color.city.tokyo with flat roofs and cast shadows, no inks', () {
    final p = Palette.forCity('tokyo');
    expect(p.land, const Color(Tokens.colorCityTokyoLand));
    expect(p.asphalt, const Color(Tokens.colorCityTokyoAsphalt));
    expect(p.landmark, const Color(Tokens.colorCityTokyoLandmark));
    expect(p.facades, [for (final c in Tokens.colorCityTokyoFacades) Color(c)]);
    expect(p.shadow, const Color(Tokens.colorCityTokyoShadow));
    expect(p.roof, const Color(Tokens.colorCityTokyoRoof));
    expect(p.castShadow, const Color(Tokens.colorCityTokyoCastShadow));
    expect(p.flatRoofs, isTrue);
    expect(p.inks, isEmpty);
  });

  test('moscow (style E) maps color.city.moscow: black roof edges, cast shadows, no inks', () {
    final p = Palette.forCity('moscow');
    expect(p.land, const Color(Tokens.colorCityMoscowLand));
    expect(p.asphalt, const Color(Tokens.colorCityMoscowAsphalt));
    expect(p.landmark, const Color(Tokens.colorCityMoscowLandmark));
    expect(p.facades, [for (final c in Tokens.colorCityMoscowFacades) Color(c)]);
    expect(p.shadow, const Color(Tokens.colorCityMoscowShadow));
    expect(p.roof, const Color(Tokens.colorCityMoscowRoof));
    expect(p.roofEdge, const Color(Tokens.colorCityMoscowRoofEdge));
    expect(p.castShadow, const Color(Tokens.colorCityMoscowCastShadow));
    expect(p.flatRoofs, isTrue);
    expect(p.inks, isEmpty);
  });

  test('unknown city falls back to color.world.day', () {
    final p = Palette.forCity('atlantis');
    expect(identical(p, Palette.day), isTrue);
    expect(p.land, const Color(Tokens.colorWorldDayLand));
    expect(p.shadow, const Color(Tokens.colorCarShadow));
  });

  test('v2: nyc has flat roofs and cast shadows, the others stay v1', () {
    final nyc = Palette.forCity('nyc');
    expect(nyc.roof, const Color(Tokens.colorCityNycRoof));
    expect(nyc.roofEdge, const Color(Tokens.colorCityNycRoofEdge));
    expect(nyc.castShadow, const Color(Tokens.colorCityNycCastShadow));
    expect(nyc.flatRoofs, isTrue);
    for (final p in [Palette.forCity('prague'), Palette.forCity('atlantis'), Palette.nightPalette]) {
      expect(p.flatRoofs, isFalse);
      expect(p.roofEdge, isNull);
      expect(p.castShadow, isNull);
    }
  });

  test('night keeps the shared palette and the old shadow', () {
    expect(Palette.nightPalette.night, isTrue);
    expect(Palette.nightPalette.shadow, const Color(Tokens.colorCarShadow));
  });

  group('risographEnabled', () {
    final style = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync()).style;

    test('follows style.risograph.<city> by day', () {
      style.risograph
        ..prague = true
        ..nyc = false;
      expect(risographEnabled(style, 'prague', night: false), isTrue);
      expect(risographEnabled(style, 'nyc', night: false), isFalse);
    });

    test('never at night', () {
      style.risograph.prague = true;
      expect(risographEnabled(style, 'prague', night: true), isFalse);
    });

    test('never for an unknown city or a city without inks', () {
      style.risograph.nyc = true;
      expect(risographEnabled(style, 'atlantis', night: false), isFalse);
      expect(risographEnabled(style, 'nyc', night: false), isFalse);
    });

    test('content: Prague on, NYC, Tokyo and Moscow off', () {
      final s = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync()).style;
      expect(risographEnabled(s, 'prague', night: false), isTrue);
      expect(risographEnabled(s, 'nyc', night: false), isFalse);
      expect(risographEnabled(s, 'tokyo', night: false), isFalse);
      expect(risographEnabled(s, 'moscow', night: false), isFalse);
    });
  });

  test('wet (specs/weather.md): road, sidewalk and alley × (1 − k), the rest unchanged', () {
    final p = Palette.forCity('nyc');
    expect(identical(p.wet(0), p), isTrue);
    final w = p.wet(0.25);
    for (final (a, b) in [(p.asphalt, w.asphalt), (p.sidewalk, w.sidewalk), (p.alley, w.alley)]) {
      expect(b.r, closeTo(a.r * 0.75, 1e-6));
      expect(b.g, closeTo(a.g * 0.75, 1e-6));
      expect(b.b, closeTo(a.b * 0.75, 1e-6));
      expect(b.a, a.a);
    }
    expect(
      [w.land, w.water, w.marking, w.bridgeDeck, w.roof, w.shadow, w.night],
      [p.land, p.water, p.marking, p.bridgeDeck, p.roof, p.shadow, p.night],
    );
    expect(Palette.forCity('prague').wet(0.2).inks, Palette.forCity('prague').inks);
  });
}
