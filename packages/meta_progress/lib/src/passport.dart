import 'package:rules_core/rules_core.dart';

/// Stamp kinds in spec order (specs/passport.md); `passport.weights` follow this order.
const stampKinds = ['landmark', 'district', 'minigame', 'photo'];

String stampId(String kind, String id) => '$kind:$id';

/// Stable district id from its display name (specs/passport.md "districtId").
String districtId(String name) => name
    .toLowerCase()
    .replaceAll(RegExp("['’.]"), '')
    .replaceAll(RegExp('[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String? _kindOf(String stamp) {
  final i = stamp.indexOf(':');
  if (i < 0) return null;
  final k = stamp.substring(0, i);
  return stampKinds.contains(k) ? k : null;
}

List<String> _unique(Iterable<String> xs) => [
  ...{...xs},
];

class PassportState {
  const PassportState({
    required this.catalog,
    required this.weights,
    required this.starsForStamp,
    required this.stamps,
    required this.points,
    required this.total,
    required this.last,
  });

  /// Kind → ids, in stampKinds order.
  final Map<String, List<String>> catalog;
  final List<int> weights;
  final int starsForStamp;

  /// "kind:id" in the order collected (Save.stamps).
  final List<String> stamps;
  final int points;
  final int total;

  /// The stamp the last apply added, or "".
  final String last;

  PassportState copyWith({List<String>? stamps, int? points, String? last}) => PassportState(
    catalog: catalog,
    weights: weights,
    starsForStamp: starsForStamp,
    stamps: stamps ?? this.stamps,
    points: points ?? this.points,
    total: total,
    last: last ?? this.last,
  );

  int weightOf(String kind) {
    final i = stampKinds.indexOf(kind);
    return i < weights.length ? weights[i] : 0;
  }

  Map<String, Object?> toJson() => {
    'catalog': {for (final k in stampKinds) k: catalog[k]},
    'weights': weights,
    'starsForStamp': starsForStamp,
    'stamps': stamps,
    'points': points,
    'total': total,
    'last': last,
  };
}

class PassportAction {
  const PassportAction(this.kind, this.id, {this.stars, this.by = 'player', this.op = 'visit'});
  final String by;
  final String op;
  final String kind;
  final String id;
  final int? stars;

  Map<String, Object?> toJson() => {'by': by, 'op': op, 'kind': kind, 'id': id, 'stars': ?stars};
  @override
  String toString() => toJson().toString();
}

class PassportResult {
  const PassportResult({
    required this.percent,
    required this.points,
    required this.total,
    required this.stamps,
    required this.of,
    required this.kinds,
  });
  final int percent;
  final int points;
  final int total;
  final int stamps;
  final int of;

  /// Kind → (got, of).
  final Map<String, (int, int)> kinds;

  Map<String, Object?> toJson() => {
    'percent': percent,
    'points': points,
    'total': total,
    'stamps': stamps,
    'of': of,
    'kinds': {
      for (final e in kinds.entries) e.key: [e.value.$1, e.value.$2],
    },
  };
}

/// Passport rules (specs/passport.md): pure, integer, no opponent.
class PassportRules extends MgRules<PassportState, PassportAction, PassportResult> {
  @override
  String get id => 'passport';
  @override
  int get specVersion => 1;

  @override
  PassportState init(Map<String, Object?> config, int seed) {
    List<String> list(String k) => ((config[k] as List?) ?? const []).cast<String>();
    final catalog = {
      'landmark': _unique(list('landmarks')),
      'district': _unique(list('districts')),
      'minigame': _unique(list('minigames')),
      'photo': _unique(list('photos')),
    };
    final weights = ((config['weights'] as List?) ?? const []).cast<int>().toList();
    int w(String k) {
      final i = stampKinds.indexOf(k);
      return i < weights.length ? weights[i] : 0;
    }

    var total = 0;
    for (final k in stampKinds) {
      total += w(k) * catalog[k]!.length;
    }
    final stamps = <String>[];
    var points = 0;
    for (final s in list('stamps')) {
      final k = _kindOf(s);
      if (k == null || stamps.contains(s) || !catalog[k]!.contains(s.substring(k.length + 1))) continue;
      stamps.add(s);
      points += w(k);
    }
    return PassportState(
      catalog: catalog,
      weights: weights,
      starsForStamp: config['starsForStamp'] as int,
      stamps: stamps,
      points: points,
      total: total,
      last: '',
    );
  }

  @override
  List<PassportAction> legalActions(PassportState s) => [
    for (final k in stampKinds)
      for (final id in s.catalog[k]!)
        if (!s.stamps.contains(stampId(k, id))) PassportAction(k, id, stars: k == 'minigame' ? 3 : null),
  ];

  @override
  PassportState apply(PassportState s, PassportAction a) {
    final k = a.kind;
    if (a.by != 'player' || a.op != 'visit' || !stampKinds.contains(k) || !s.catalog[k]!.contains(a.id)) {
      throw IllegalAction(id, a);
    }
    if (k == 'minigame') {
      final st = a.stars;
      if (st == null || st < 0 || st > 3) throw IllegalAction(id, a);
      if (st < s.starsForStamp) return s.copyWith(last: '');
    }
    final stamp = stampId(k, a.id);
    if (s.stamps.contains(stamp)) return s.copyWith(last: '');
    return s.copyWith(stamps: [...s.stamps, stamp], points: s.points + s.weightOf(k), last: stamp);
  }

  @override
  PassportAction aiAction(PassportState state, int level, Prng ai) => throw StateError('passport: no opponent');

  @override
  PassportResult result(PassportState s) {
    final kinds = <String, (int, int)>{};
    var of = 0;
    for (final k in stampKinds) {
      final got = s.stamps.where((x) => _kindOf(x) == k).length;
      kinds[k] = (got, s.catalog[k]!.length);
      of += s.catalog[k]!.length;
    }
    return PassportResult(
      percent: s.total == 0 ? 0 : (100 * s.points) ~/ s.total,
      points: s.points,
      total: s.total,
      stamps: s.stamps.length,
      of: of,
      kinds: kinds,
    );
  }

  @override
  PassportAction actionFromJson(Map<String, Object?> j) => PassportAction(
    j['kind'] as String,
    j['id'] as String,
    stars: j['stars'] as int?,
    by: j['by'] as String,
    op: j['op'] as String,
  );

  @override
  Map<String, Object?> stateToJson(PassportState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(PassportResult r) => r.toJson();
}
