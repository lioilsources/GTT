import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// Feed deck selection, specs/feed.md version 2 (P0, integers only). Mirrors web/src/phone/feed.ts.
class FeedCandidate {
  const FeedCandidate({
    required this.spot,
    required this.game,
    required this.engine,
    required this.local,
    required this.district,
    required this.distDm,
    required this.visits,
    required this.landmark,
  });

  factory FeedCandidate.fromJson(Map<String, Object?> j) => FeedCandidate(
    spot: j['spot'] as String,
    game: j['game'] as String,
    engine: j['engine'] as String,
    local: j['local'] as bool,
    district: j['district'] as String,
    distDm: j['distDm'] as int,
    visits: j['visits'] as int,
    landmark: j['landmark'] as bool,
  );

  final String spot, game, engine, district;
  final bool local, landmark;
  final int distDm, visits;
}

class FeedConfig {
  FeedConfig(this.n, this.candidates, this.prefs, this.visitedDistricts);

  /// The integer parameters by their camelCase name (deckSize, novelty, …).
  final Map<String, int> n;
  final List<FeedCandidate> candidates;
  final Map<String, int> prefs;
  final List<String> visitedDistricts;

  static const keys = [
    'deckSize', 'novelty', 'prefStep', 'prefMin', 'prefMax', 'driveDmPerS', 'bandMinS', 'bandMaxS', //
    'bandPoints', 'nearPoints', 'bandFalloffS', 'districtBonus', 'landmarkBonus', 'jitter', 'hostLines',
    'rewardBase', 'rewardPerMin', 'difficultyBase', 'difficultyMax',
  ];

  factory FeedConfig.fromTuning(
    TuningFeed t,
    List<FeedCandidate> candidates,
    Map<String, int> prefs,
    List<String> visitedDistricts,
  ) => FeedConfig(
    {
      'deckSize': t.deckSize, 'novelty': t.novelty, 'prefStep': t.prefStep, 'prefMin': t.prefMin, //
      'prefMax': t.prefMax, 'driveDmPerS': t.driveDmPerS, 'bandMinS': t.bandMinS, 'bandMaxS': t.bandMaxS,
      'bandPoints': t.bandPoints, 'nearPoints': t.nearPoints, 'bandFalloffS': t.bandFalloffS,
      'districtBonus': t.districtBonus, 'landmarkBonus': t.landmarkBonus, 'jitter': t.jitter,
      'hostLines': t.hostLines, 'rewardBase': t.rewardBase, 'rewardPerMin': t.rewardPerMin,
      'difficultyBase': t.difficultyBase, 'difficultyMax': t.difficultyMax,
    },
    candidates,
    Map.of(prefs),
    List.of(visitedDistricts),
  );

  factory FeedConfig.fromJson(Map<String, Object?> j) => FeedConfig(
    {for (final k in keys) k: j[k] as int},
    [for (final c in (j['candidates'] as List).cast<Map<String, Object?>>()) FeedCandidate.fromJson(c)],
    (j['prefs'] as Map).cast<String, int>(),
    (j['visitedDistricts'] as List).cast<String>(),
  );

  int operator [](String k) => n[k]!;
}

class FeedCard {
  const FeedCard({
    required this.spot,
    required this.game,
    required this.engine,
    required this.district,
    required this.local,
    required this.driveS,
    required this.distDm,
    required this.score,
    required this.host,
    required this.reward,
    required this.difficulty,
  });

  final String spot, game, engine, district;
  final bool local;
  final int driveS, distDm, score, host, reward, difficulty;

  Map<String, Object?> toJson() => {
    'spot': spot,
    'game': game,
    'engine': engine,
    'district': district,
    'local': local,
    'driveS': driveS,
    'distDm': distDm,
    'score': score,
    'host': host,
    'reward': reward,
    'difficulty': difficulty,
  };
}

class FeedState {
  const FeedState({
    required this.deck,
    required this.at,
    required this.prefs,
    required this.liked,
    required this.accepted,
    required this.over,
  });

  final List<FeedCard> deck;
  final int at;
  final Map<String, int> prefs;
  final List<String> liked;
  final String accepted;
  final bool over;

  FeedCard? get card => at < deck.length ? deck[at] : null;

  FeedState copyWith({int? at, Map<String, int>? prefs, List<String>? liked, String? accepted, bool? over}) =>
      FeedState(
        deck: deck,
        at: at ?? this.at,
        prefs: prefs ?? this.prefs,
        liked: liked ?? this.liked,
        accepted: accepted ?? this.accepted,
        over: over ?? this.over,
      );

  Map<String, Object?> toJson() => {
    'deck': [for (final c in deck) c.toJson()],
    'at': at,
    'prefs': prefs,
    'liked': liked,
    'accepted': accepted,
    'over': over,
  };
}

enum FeedOp { next, prev, like, less, accept }

int _band(FeedConfig c, int driveS) {
  if (driveS < c['bandMinS']) return c['nearPoints'];
  if (driveS <= c['bandMaxS']) return c['bandPoints'];
  return math.max(0, c['bandPoints'] - (driveS - c['bandMaxS']) * c['bandPoints'] ~/ c['bandFalloffS']);
}

/// Distance band points for a drive time (specs/feed.md init step 2).
int bandScore(FeedConfig c, int driveS) => _band(c, driveS);

class FeedRules extends MgRules<FeedState, FeedOp, Never> {
  FeedConfig? _cfg;

  @override
  String get id => 'feed';
  @override
  int get specVersion => 2;

  FeedConfig get _c => _cfg ?? (throw StateError('feed: init first'));

  /// Typed entry point; [init] takes the JSON form for vectors.
  FeedState deal(FeedConfig c, int seed) {
    _cfg = c;
    final rng = Prng(seed);
    final prefs = {for (final e in c.prefs.entries) e.key: e.value.clamp(c['prefMin'], c['prefMax'])};
    final visited = c.visitedDistricts.toSet();
    final scored = <({FeedCandidate k, int i, int driveS, int score})>[];
    for (var i = 0; i < c.candidates.length; i++) {
      final k = c.candidates[i];
      final driveS = k.distDm ~/ c['driveDmPerS'];
      final score =
          (k.visits == 0 ? c['novelty'] : 0) +
          (prefs[k.engine] ?? 0) * c['prefStep'] +
          _band(c, driveS) +
          (k.district != '' && !visited.contains(k.district) ? c['districtBonus'] : 0) +
          (k.landmark ? c['landmarkBonus'] : 0) +
          rng.nextInt(c['jitter'] + 1);
      scored.add((k: k, i: i, driveS: driveS, score: score));
    }
    final ranked = [...scored]..sort((a, b) => a.score != b.score ? b.score - a.score : a.i - b.i);
    final picked = <({FeedCandidate k, int i, int driveS, int score})>[];
    final local = ranked.where((x) => x.k.local).firstOrNull;
    final drive = ranked.where((x) => x.k.engine == 'drive').firstOrNull;
    for (final r in [local, drive]) {
      if (r != null && !picked.contains(r) && picked.length < c['deckSize']) picked.add(r);
    }
    for (final r in ranked) {
      if (picked.length >= c['deckSize']) break;
      if (!picked.contains(r)) picked.add(r);
    }
    picked.sort((a, b) => ranked.indexOf(a) - ranked.indexOf(b));
    final deck = [
      for (final p in picked)
        FeedCard(
          spot: p.k.spot,
          game: p.k.game,
          engine: p.k.engine,
          district: p.k.district,
          local: p.k.local,
          driveS: p.driveS,
          distDm: p.k.distDm,
          score: p.score,
          host: rng.nextInt(c['hostLines']),
          reward: c['rewardBase'] + p.driveS * c['rewardPerMin'] ~/ 60,
          difficulty: math.min(c['difficultyMax'], c['difficultyBase'] + p.k.visits),
        ),
    ];
    return FeedState(deck: deck, at: 0, prefs: prefs, liked: const [], accepted: '', over: deck.isEmpty);
  }

  @override
  FeedState init(Map<String, Object?> config, int seed) => deal(FeedConfig.fromJson(config), seed);

  @override
  List<FeedOp> legalActions(FeedState s) {
    if (s.over) return const [];
    final liked = s.liked.contains(s.deck[s.at].spot);
    return [FeedOp.next, if (s.at > 0) FeedOp.prev, if (!liked) FeedOp.like, FeedOp.less, FeedOp.accept];
  }

  @override
  FeedState apply(FeedState s, FeedOp a) {
    if (!legalActions(s).contains(a)) throw IllegalAction(id, a.name);
    final card = s.deck[s.at];
    FeedState step(FeedState n) => n.copyWith(at: n.at + 1, over: n.at + 1 >= n.deck.length);
    final prefs = Map.of(s.prefs);
    switch (a) {
      case FeedOp.next:
        return step(s);
      case FeedOp.prev:
        return s.copyWith(at: s.at - 1);
      case FeedOp.like:
        prefs[card.engine] = math.min(_c['prefMax'], (prefs[card.engine] ?? 0) + 1);
        return s.copyWith(prefs: prefs, liked: [...s.liked, card.spot]);
      case FeedOp.less:
        prefs[card.engine] = math.max(_c['prefMin'], (prefs[card.engine] ?? 0) - 1);
        return step(s.copyWith(prefs: prefs));
      case FeedOp.accept:
        return s.copyWith(accepted: card.spot, over: true);
    }
  }

  @override
  FeedOp aiAction(FeedState state, int level, Prng ai) => throw UnsupportedError('feed: no AI');

  @override
  Never? result(FeedState state) => null;

  @override
  FeedOp actionFromJson(Map<String, Object?> json) {
    if (json['by'] != 'player') throw IllegalAction(id, json);
    return FeedOp.values.firstWhere((o) => o.name == json['op'], orElse: () => throw IllegalAction(id, json));
  }

  @override
  Map<String, Object?> stateToJson(FeedState state) => state.toJson();

  @override
  Map<String, Object?> resultToJson(Never result) => const {};
}

/// Client-side candidate inputs (specs/feed.md "Kandidáti"); positions in dm.
class CandidateSpot {
  const CandidateSpot(this.id, this.minigame, this.x, this.y);
  final String id, minigame;
  final int x, y;
}

List<FeedCandidate> buildCandidates({
  required String cityId,
  required List<CandidateSpot> spots,
  required Map<String, MinigameMeta> catalog,
  required String Function(int xDm, int yDm) districtAt,
  required List<({String id, int x, int y})> landmarks,
  required Set<String> discovered,
  required Map<String, int> visits,
  required int landmarkRadiusDm,
  required int Function(String spotId) distDm,
}) {
  final r2 = landmarkRadiusDm * landmarkRadiusDm;
  FeedCandidate make(CandidateSpot s, String game, String engine, bool local) => FeedCandidate(
    spot: s.id,
    game: game,
    engine: engine,
    local: local,
    district: districtAt(s.x, s.y),
    distDm: distDm(s.id),
    visits: visits[s.id] ?? 0,
    landmark: landmarks.any(
      (l) => !discovered.contains(l.id) && (l.x - s.x) * (l.x - s.x) + (l.y - s.y) * (l.y - s.y) <= r2,
    ),
  );
  final out = <FeedCandidate>[];
  for (final s in spots) {
    final meta = s.minigame.isEmpty ? null : catalog[s.minigame];
    if (meta != null) out.add(make(s, s.minigame, meta.engine, meta.cities.contains(cityId)));
  }
  if (!out.any((c) => c.engine == 'drive')) {
    for (final s in spots) {
      if (s.minigame.isEmpty) out.add(make(s, 'challenge', 'drive', false));
    }
  }
  return out;
}
