import 'dart:io';

import 'package:game_loop/game_loop.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

// specs/weather.md v1.
void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  const cfg = WeatherConfig(weights: [5, 3, 2], minS: 2, maxS: 4);
  const tick = WeatherAction.tick();

  group('weather vectors', () {
    test(
      'vectors/weather.json',
      () => expect(checkVectors(WeatherRules()), isEmpty),
      skip: !flutterDone('vectors/weather.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('weather rules (specs/weather.md)', () {
    test('init: clear, a gap in [minS, maxS], no changes', () {
      final r = WeatherRules();
      for (var seed = 0; seed < 40; seed++) {
        final s = r.start(cfg, seed);
        expect(s.kind, WeatherKind.clear);
        expect(s.left, inInclusiveRange(cfg.minS, cfg.maxS));
        expect(s.changes, 0);
      }
    });

    test('gap() draws minS + nextInt(maxS - minS + 1) from Prng(seed)', () {
      final r = WeatherRules();
      final p = Prng(7);
      expect(r.start(cfg, 7).left, cfg.minS + p.nextInt(cfg.maxS - cfg.minS + 1));
      expect(r.start(cfg, 7).rng, p.state);
    });

    test('config from tuning', () {
      final w = tuning.weather;
      final c = WeatherConfig.fromTuning(w);
      expect([...c.weights, c.minS, c.maxS], [w.weightClear, w.weightRain, w.weightFog, w.minS, w.maxS]);
    });

    test('a tick before the change only counts down and keeps the PRNG', () {
      final r = WeatherRules();
      final s0 = r.start(const WeatherConfig(weights: [1, 1, 1], minS: 5, maxS: 5), 3);
      final s1 = r.apply(s0, tick);
      expect([s1.kind, s1.left, s1.changes, s1.rng], [WeatherKind.clear, 4, 0, s0.rng]);
    });

    test('changes never repeat the kind', () {
      final r = WeatherRules();
      var s = r.start(const WeatherConfig(weights: [5, 3, 2], minS: 1, maxS: 1), 42);
      for (var i = 0; i < 200; i++) {
        final was = s.kind;
        s = r.apply(s, tick);
        expect(s.kind, isNot(was));
        expect(s.changes, i + 1);
      }
    });

    test('weighted draw over the other kinds in order clear, rain, fog', () {
      final r = WeatherRules();
      const c = WeatherConfig(weights: [5, 3, 2], minS: 1, maxS: 1);
      // From clear the draw is over rain (3) and fog (2): r < 3 = rain.
      for (var seed = 1; seed < 50; seed++) {
        final s0 = r.start(c, seed);
        final p = Prng(s0.rng);
        final x = p.nextInt(5);
        expect(r.apply(s0, tick).kind, x < 3 ? WeatherKind.rain : WeatherKind.fog);
      }
    });

    test('all other weights zero: kind stays, no draw, only a new gap', () {
      final r = WeatherRules();
      final s0 = r.start(const WeatherConfig(weights: [4, 0, 0], minS: 1, maxS: 1), 9);
      final s1 = r.apply(s0, tick);
      final p = Prng(s0.rng)..nextInt(1);
      expect([s1.kind, s1.left, s1.changes, s1.rng], [WeatherKind.clear, 1, 1, p.state]);
    });

    test('set: any kind, the same one too, new gap and one more change', () {
      final r = WeatherRules();
      var s = r.start(cfg, 5);
      s = r.apply(s, const WeatherAction.set(WeatherKind.fog));
      expect([s.kind, s.changes], [WeatherKind.fog, 1]);
      final rng = s.rng;
      s = r.apply(s, const WeatherAction.set(WeatherKind.fog));
      expect([s.kind, s.changes], [WeatherKind.fog, 2]);
      expect(s.rng, isNot(rng));
      expect(s.left, inInclusiveRange(cfg.minS, cfg.maxS));
    });

    test('illegal: unknown op, unknown kind, by != player', () {
      final r = WeatherRules()..start(cfg, 1);
      for (final j in [
        {'by': 'player', 'op': 'jump'},
        {'by': 'player', 'op': 'set', 'kind': 'snow'},
        {'by': 'player', 'op': 'set'},
        {'by': 'ai', 'op': 'tick'},
      ]) {
        expect(() => r.actionFromJson(j), throwsA(isA<IllegalAction>()), reason: '$j');
      }
      expect(
        r.actionFromJson({'by': 'player', 'op': 'set', 'kind': 'rain'}),
        const WeatherAction.set(WeatherKind.rain),
      );
    });

    test('legalActions: tick, then set per kind; result null', () {
      final r = WeatherRules();
      final s = r.start(cfg, 1);
      expect(r.legalActions(s), [
        const WeatherAction.tick(),
        const WeatherAction.set(WeatherKind.clear),
        const WeatherAction.set(WeatherKind.rain),
        const WeatherAction.set(WeatherKind.fog),
      ]);
      expect(r.result(s), isNull);
    });
  });

  group('weather in the world (P1)', () {
    test('rain grip multiplies only in rain', () {
      final w = tuning.weather;
      expect(weatherGrip(WeatherKind.clear, w), 1.0);
      expect(weatherGrip(WeatherKind.fog, w), 1.0);
      expect(weatherGrip(WeatherKind.rain, w), w.rainGrip);
      expect(w.rainGrip, lessThan(1.0));
    });

    test('weatherOn: enabled and per city', () {
      final t = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
      expect(weatherOn(t.weather, 'nyc'), t.weather.cities.nyc && t.weather.enabled);
      expect(weatherOn(t.weather, 'atlantis'), isFalse);
      t.weather.cities.nyc = false;
      expect(weatherOn(t.weather, 'nyc'), isFalse);
      t.weather.cities.nyc = true;
      t.weather.enabled = false;
      expect(weatherOn(t.weather, 'nyc'), isFalse);
    });

    test('fog ramp: centre, edge, smoothstep from fog_inner', () {
      final w = tuning.weather;
      expect(fogAlpha(0, w), closeTo(w.fogCenterAlpha, 1e-9));
      expect(fogAlpha(w.fogInner, w), closeTo(w.fogCenterAlpha, 1e-9));
      expect(fogAlpha(1, w), closeTo(w.fogEdgeAlpha, 1e-9));
      expect(fogAlpha(2, w), closeTo(w.fogEdgeAlpha, 1e-9));
      final mid = (w.fogInner + 1) / 2;
      expect(fogAlpha(mid, w), closeTo((w.fogCenterAlpha + w.fogEdgeAlpha) / 2, 1e-9));
    });

    test('mix: linear cross-fade over blend_s, mid-blend change starts from the mix', () {
      final m = WeatherMix();
      m.step(WeatherKind.rain, 1, 4);
      expect([m.of(WeatherKind.clear), m.rain, m.fog], [0.75, 0.25, 0]);
      m.step(WeatherKind.rain, 1, 4);
      m.step(WeatherKind.fog, 1, 4);
      expect([m.of(WeatherKind.clear), m.rain, m.fog], [0.25, 0.25, 0.25]);
      for (var i = 0; i < 4; i++) {
        m.step(WeatherKind.fog, 1, 4);
      }
      expect([m.of(WeatherKind.clear), m.rain, m.fog], [0, 0, 1]);
      expect(m.blending(WeatherKind.fog), isFalse);
      m.step(WeatherKind.clear, 0.1, 0);
      expect(m.of(WeatherKind.clear), 1);
    });

    test('world: one tick per game second, pause stops the clock, change events', () {
      final t = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
      t.weather
        ..minS = 2
        ..maxS = 2;
      final w = WeatherWorld(t.weather, 1);
      final seen = <WeatherKind>[];
      w.onChange.add(seen.add);
      w.update(0.6);
      w.update(0);
      expect(w.state.left, 2);
      w.update(0.6);
      expect(w.state.left, 1);
      for (var i = 0; i < 100; i++) {
        w.update(0);
      }
      expect(w.state.left, 1, reason: 'paused');
      w.update(1);
      expect(w.state.changes, 1);
      expect(seen, [w.kind]);
      expect(w.grip, weatherGrip(w.kind, t.weather));
      w.set(WeatherKind.rain);
      expect(w.grip, t.weather.rainGrip);
      w.cycle();
      expect(w.kind, WeatherKind.fog);
      w.cycle();
      expect(w.kind, WeatherKind.clear);
    });
  });
}
