import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/save.md, version 3: save format 4, migration from 1, 2 and 3, normalisation (P0, module `save`).
/// Port of web/src/loop/save.ts. States are the JSON maps of the save.
const saveVersion = 4;

class SaveConfig {
  const SaveConfig({
    required this.cityId,
    required this.startCash,
    required this.startOwned,
    required this.startCar,
    required this.cars,
  });

  factory SaveConfig.fromTuning(Tuning t, String cityId, Iterable<String> cars) => SaveConfig(
    cityId: cityId,
    startCash: t.cars.startCash,
    startOwned: List.unmodifiable(t.cars.startOwned),
    startCar: t.cars.startCar,
    cars: List.unmodifiable(cars),
  );

  factory SaveConfig.fromJson(Map<String, Object?> j) => SaveConfig(
    cityId: j['cityId'] as String,
    startCash: j['startCash'] as int,
    startOwned: (j['startOwned'] as List).cast<String>(),
    startCar: j['startCar'] as String,
    cars: (j['cars'] as List).cast<String>(),
  );

  final String cityId;
  final int startCash;
  final List<String> startOwned;
  final String startCar;

  /// Every car id of the catalog.
  final List<String> cars;
}

/// The live parts a save is composed from.
class SaveParts {
  const SaveParts({
    required this.cash,
    required this.cars,
    required this.car,
    required this.stamps,
    required this.best,
    required this.plays,
    this.feed,
    this.npc,
    this.settings,
    this.stations,
    this.souvenirs,
  });

  final int cash;
  final List<String> cars;
  final String car;
  final List<String> stamps;
  final Map<String, ({int stars, int score})> best;
  final Map<String, int> plays;
  final ({Map<String, int> prefs, Map<String, int> visits, List<String> districts})? feed;
  final ({Map<String, int> vibe, List<String> contacts, List<String> recent})? npc;
  final ({String scheme, bool night})? settings;

  /// Unlocked metro stations in unlock order (specs/travel.md).
  final List<String>? stations;

  /// Bought souvenirs in purchase order (specs/shops.md).
  final List<String>? souvenirs;
}

// JSON number → int like TS Number.isInteger (5.0 counts, 1.5 does not).
int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

bool _isObj(Object? v) => v is Map;
List<String>? _strList(Object? v) => v is List && v.every((x) => x is String) ? [for (final x in v) x as String] : null;
Map<String, int>? _intMap(Object? v) {
  if (v is! Map) return null;
  final out = <String, int>{};
  for (final e in v.entries) {
    final n = _asInt(e.value);
    if (e.key is! String || n == null) return null;
    out[e.key as String] = n;
  }
  return out;
}

Map<String, ({int stars, int score})>? _bestMap(Object? v) {
  if (v is! Map) return null;
  final out = <String, ({int stars, int score})>{};
  for (final e in v.entries) {
    final b = e.value;
    if (b is! Map) return null;
    final stars = _asInt(b['stars']), score = _asInt(b['score']);
    if (stars == null || score == null) return null;
    out[e.key as String] = (stars: stars, score: score);
  }
  return out;
}

List<String> _unique(Iterable<String> xs) {
  final seen = <String>{};
  return [
    for (final x in xs)
      if (seen.add(x)) x,
  ];
}

/// A map with sorted keys (code-unit order, as in TS).
Map<String, T> _sorted<T>(Map<String, T> m, [T Function(T)? f]) => {
  for (final k in m.keys.toList()..sort()) k: f == null ? m[k] as T : f(m[k] as T),
};

int _max0(int n) => n < 0 ? 0 : n;

/// Composes a save from the live parts (same normalisation as load, so a round trip is exact).
Map<String, Object?> composeSave(SaveConfig c, SaveParts p) {
  final known = c.cars.toSet();
  var cars = _unique(p.cars.where(known.contains));
  if (cars.isEmpty) cars = _unique(c.startOwned.where(known.contains));
  final car = cars.contains(p.car) ? p.car : (cars.isNotEmpty ? cars.first : c.startCar);
  final feed = p.feed ?? (prefs: <String, int>{}, visits: <String, int>{}, districts: <String>[]);
  final npc = p.npc ?? (vibe: <String, int>{}, contacts: <String>[], recent: <String>[]);
  final st = p.settings ?? (scheme: 'a', night: false);
  return {
    'version': saveVersion,
    'cityId': c.cityId,
    'cash': _max0(p.cash),
    'cars': cars,
    'car': car,
    'stamps': _unique(p.stamps),
    'best': {
      for (final k in p.best.keys.toList()..sort())
        k: {'stars': p.best[k]!.stars.clamp(0, 3), 'score': p.best[k]!.score},
    },
    'plays': _sorted(p.plays, _max0),
    'feed': {
      'prefs': _sorted(feed.prefs),
      'visits': _sorted(feed.visits, _max0),
      'districts': [...feed.districts],
    },
    'npc': {
      'vibe': _sorted(npc.vibe),
      'contacts': [...npc.contacts],
      'recent': [...npc.recent],
    },
    'settings': {
      'scheme': const ['a', 'b', 'c'].contains(st.scheme) ? st.scheme : 'a',
      'night': st.night,
    },
    'stations': _unique(p.stations ?? const []),
    'souvenirs': _unique(p.souvenirs ?? const []),
  };
}

Map<String, Object?> freshSave(SaveConfig c) => composeSave(
  c,
  SaveParts(cash: c.startCash, cars: const [], car: c.startCar, stamps: const [], best: const {}, plays: const {}),
);

/// Any JSON value → a normalised version-4 save of this city (specs/save.md "load").
Map<String, Object?> normalizeSave(SaveConfig c, Object? raw) {
  if (raw is! Map) return freshSave(c);
  final s = raw;
  final version = s['version'];
  if ((version != 1 && version != 2 && version != 3 && version != 4) || s['cityId'] != c.cityId) return freshSave(c);
  final cash = _asInt(s['cash']);
  final stamps = _strList(s['stamps']);
  final cars = _strList(s['cars']);
  final best = _bestMap(s['best']);
  if (cash == null || stamps == null || cars == null || best == null) return freshSave(c);
  if (version == 1) {
    return composeSave(c, SaveParts(cash: cash, cars: cars, car: '', stamps: stamps, best: best, plays: const {}));
  }
  final feed = s['feed'], npc = s['npc'], st = s['settings'];
  final car = s['car'];
  final plays = _intMap(s['plays']);
  if (car is! String || plays == null || !_isObj(feed) || !_isObj(npc) || !_isObj(st)) return freshSave(c);
  final f = feed as Map, n = npc as Map, t = st as Map;
  final prefs = _intMap(f['prefs']), visits = _intMap(f['visits']), districts = _strList(f['districts']);
  final vibe = _intMap(n['vibe']), contacts = _strList(n['contacts']), recent = _strList(n['recent']);
  final scheme = t['scheme'], night = t['night'];
  if (prefs == null ||
      visits == null ||
      districts == null ||
      vibe == null ||
      contacts == null ||
      recent == null ||
      scheme is! String ||
      night is! bool) {
    return freshSave(c);
  }
  // Version 3: `stations` is optional (missing = []); migration 2 → 3 sets it to [].
  final stations = version >= 3 && s.containsKey('stations') ? _strList(s['stations']) : const <String>[];
  // Version 4: `souvenirs` is optional (missing = []); migration 3 → 4 sets it to [].
  final souvenirs = version == 4 && s.containsKey('souvenirs') ? _strList(s['souvenirs']) : const <String>[];
  if (stations == null || souvenirs == null) return freshSave(c);
  return composeSave(
    c,
    SaveParts(
      cash: cash,
      cars: cars,
      car: car,
      stamps: stamps,
      best: best,
      plays: plays,
      feed: (prefs: prefs, visits: visits, districts: districts),
      npc: (vibe: vibe, contacts: contacts, recent: recent),
      settings: (scheme: scheme, night: night),
      stations: stations,
      souvenirs: souvenirs,
    ),
  );
}

/// A typed view of a normalised save (generated from schema/save.schema.json).
Save saveOf(Map<String, Object?> json) => Save.fromJson(json);

class SaveAction {
  const SaveAction(this.save);
  final Object? save;
  @override
  String toString() => 'save load';
}

class SaveRules extends MgRules<Map<String, Object?>, SaveAction, Map<String, Object?>> {
  @override
  String get id => 'save';
  @override
  int get specVersion => 3;

  SaveConfig? _cfg;

  @override
  Map<String, Object?> init(Map<String, Object?> config, int seed) {
    final c = _cfg = SaveConfig.fromJson(config);
    return freshSave(c);
  }

  @override
  List<SaveAction> legalActions(Map<String, Object?> state) => const [];

  @override
  Map<String, Object?> apply(Map<String, Object?> state, SaveAction action) =>
      normalizeSave(_cfg ?? (throw StateError('save: init first')), action.save);

  @override
  SaveAction aiAction(Map<String, Object?> state, int level, Prng ai) => throw UnsupportedError('save: no opponent');

  @override
  Map<String, Object?>? result(Map<String, Object?> state) => null;

  @override
  SaveAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player' || j['op'] != 'load') throw IllegalAction(id, j);
    return SaveAction(j['save']);
  }

  @override
  Map<String, Object?> stateToJson(Map<String, Object?> s) => s;

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}
