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

  test('unknown city falls back to color.world.day', () {
    final p = Palette.forCity('atlantis');
    expect(identical(p, Palette.day), isTrue);
    expect(p.land, const Color(Tokens.colorWorldDayLand));
    expect(p.shadow, const Color(Tokens.colorCarShadow));
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

    test('content: Prague on, NYC off', () {
      final s = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync()).style;
      expect(risographEnabled(s, 'prague', night: false), isTrue);
      expect(risographEnabled(s, 'nyc', night: false), isFalse);
    });
  });
}
