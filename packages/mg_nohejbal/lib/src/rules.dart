import 'package:mg_kulicky/mg_kulicky.dart' show DuelResult, scatterShot;
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/nohejbal.md, version 1. Pure Dart: no Flutter imports here.
class NohejbalConfig {
  const NohejbalConfig({
    required this.halfWidth,
    required this.depth,
    required this.winPoints,
    required this.winBy,
    required this.maxPoints,
    required this.scatter,
    required this.aiScatter,
    required this.aiReach,
    required this.playerReach,
    required this.aiMargin,
    required this.starMargins,
  });

  factory NohejbalConfig.fromTuning(TuningMinigamesNohejbal t) => NohejbalConfig(
    halfWidth: t.halfWidth,
    depth: t.depth,
    winPoints: t.winPoints,
    winBy: t.winBy,
    maxPoints: t.maxPoints,
    scatter: List.unmodifiable(t.scatter),
    aiScatter: List.unmodifiable(t.aiScatter),
    aiReach: List.unmodifiable(t.aiReach),
    playerReach: t.playerReach,
    aiMargin: List.unmodifiable(t.aiMargin),
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory NohejbalConfig.fromJson(Map<String, Object?> j) {
    List<int> ints(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return NohejbalConfig(
      halfWidth: j['halfWidth'] as int,
      depth: j['depth'] as int,
      winPoints: j['winPoints'] as int,
      winBy: j['winBy'] as int,
      maxPoints: j['maxPoints'] as int,
      scatter: ints('scatter'),
      aiScatter: ints('aiScatter'),
      aiReach: ints('aiReach'),
      playerReach: j['playerReach'] as int,
      aiMargin: ints('aiMargin'),
      starMargins: ints('starMargins'),
    );
  }

  final int halfWidth, depth, winPoints, winBy, maxPoints, playerReach;
  final List<int> scatter, aiScatter, aiReach, aiMargin, starMargins;

  /// Centre of a half, y back from the net (integer division).
  int get homeY => depth ~/ 2;
}

class NohejbalShot {
  const NohejbalShot(this.by, this.x, this.y, this.inCourt, this.reached);

  static const empty = NohejbalShot('', 0, 0, false, false);

  /// Who hit it; '' before the first shot.
  final String by;

  /// Landing point in the receiver's half (mm, y back from the net).
  final int x, y;

  /// Serialised as `in`.
  final bool inCourt;

  /// The receiver got to it (within its reach of the centre of its half).
  final bool reached;

  Map<String, Object?> toJson() => {'by': by, 'x': x, 'y': y, 'in': inCourt, 'reached': reached};
}

class NohejbalState {
  const NohejbalState({
    required this.playerPts,
    required this.aiPts,
    required this.turn,
    required this.server,
    required this.rally,
    required this.lastShot,
    required this.over,
    required this.rng,
  });

  final int playerPts, aiPts;

  /// Who plays the ball, 'player' or 'ai'.
  final String turn;

  /// Who served this rally.
  final String server;

  /// Hits in this rally.
  final int rally;
  final NohejbalShot lastShot;
  final bool over;
  final int rng;

  NohejbalState copyWith({
    int? playerPts,
    int? aiPts,
    String? turn,
    String? server,
    int? rally,
    NohejbalShot? lastShot,
    bool? over,
    int? rng,
  }) => NohejbalState(
    playerPts: playerPts ?? this.playerPts,
    aiPts: aiPts ?? this.aiPts,
    turn: turn ?? this.turn,
    server: server ?? this.server,
    rally: rally ?? this.rally,
    lastShot: lastShot ?? this.lastShot,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'playerPts': playerPts,
    'aiPts': aiPts,
    'turn': turn,
    'server': server,
    'rally': rally,
    'lastShot': lastShot.toJson(),
    'over': over,
    'rng': rng,
  };
}

/// {by: player | ai, x, y, level} (aim in the receiver's half, mm) or {by: timeout}.
class NohejbalAction {
  const NohejbalAction(this.x, this.y, this.level, {this.by = 'player'});
  const NohejbalAction.timeout() : by = 'timeout', x = 0, y = 0, level = 0;

  final String by;
  final int x, y, level;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'x': x, 'y': y, 'level': level};

  @override
  String toString() => toJson().toString();
}

/// True once a side has won: winPoints with a winBy lead, or maxPoints outright.
bool nohejbalOver(NohejbalConfig c, int p, int a) {
  bool won(int x, int y) => (x >= c.winPoints && x - y >= c.winBy) || x >= c.maxPoints;
  return won(p, a) || won(a, p);
}

class NohejbalRules extends MgRules<NohejbalState, NohejbalAction, DuelResult> {
  NohejbalConfig? _cfg;

  NohejbalConfig get config => _cfg ?? (throw StateError('nohejbal: init first'));

  @override
  String get id => 'nohejbal';

  @override
  int get specVersion => 1;

  @override
  NohejbalState init(Map<String, Object?> config, int seed) => start(NohejbalConfig.fromJson(config), seed);

  NohejbalState start(NohejbalConfig config, int seed) {
    _cfg = config;
    return NohejbalState(
      playerPts: 0,
      aiPts: 0,
      turn: 'player',
      server: 'player',
      rally: 0,
      lastShot: NohejbalShot.empty,
      over: false,
      rng: Prng(seed).state,
    );
  }

  /// Actions are continuous; [apply] checks them.
  @override
  List<NohejbalAction> legalActions(NohejbalState s) => const [];

  @override
  NohejbalState apply(NohejbalState s, NohejbalAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    final c = config;
    final table = a.by == 'player' ? c.scatter : c.aiScatter;
    if (a.by != s.turn || a.level < 1 || a.level > table.length || (a.by == 'player' && a.level > c.aiReach.length)) {
      throw IllegalAction(id, a);
    }
    final sc = table[a.level - 1];
    final r = withRng(s.rng, (p) => scatterShot(p, a.x, a.y, sc));
    final p = r.value;
    final inCourt = p.x.abs() <= c.halfWidth && p.y >= 0 && p.y <= c.depth;
    var reached = false;
    if (inCourt) {
      final reach = a.by == 'player' ? c.aiReach[a.level - 1] : c.playerReach;
      final dy = p.y - c.homeY;
      reached = p.x * p.x + dy * dy <= reach * reach;
    }
    final lastShot = NohejbalShot(a.by, p.x, p.y, inCourt, reached);
    final other = a.by == 'player' ? 'ai' : 'player';
    if (reached) return s.copyWith(lastShot: lastShot, turn: other, rally: s.rally + 1, rng: r.rng);
    // Out: point to the receiver; in but out of reach: point to the hitter.
    final winner = inCourt ? a.by : other;
    final playerPts = s.playerPts + (winner == 'player' ? 1 : 0);
    final aiPts = s.aiPts + (winner == 'ai' ? 1 : 0);
    return s.copyWith(
      playerPts: playerPts,
      aiPts: aiPts,
      lastShot: lastShot,
      server: winner,
      turn: winner,
      rally: 0,
      over: nohejbalOver(c, playerPts, aiPts),
      rng: r.rng,
    );
  }

  /// Aims at one of the four corners of the player's half, kept aiMargin inside the lines.
  @override
  NohejbalAction aiAction(NohejbalState s, int level, Prng ai) {
    final c = config;
    final m = c.aiMargin[level - 1];
    final k = ai.nextInt(4);
    final x = (k % 2 == 0 ? -1 : 1) * (c.halfWidth - m);
    final y = k < 2 ? m : c.depth - m;
    return NohejbalAction(x, y, level, by: 'ai');
  }

  @override
  DuelResult? result(NohejbalState s) => s.over ? DuelResult.of(s.playerPts, s.aiPts, config.starMargins) : null;

  @override
  NohejbalAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const NohejbalAction.timeout()
      : NohejbalAction(j['x'] as int, j['y'] as int, j['level'] as int, by: j['by'] as String);

  @override
  Map<String, Object?> stateToJson(NohejbalState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DuelResult r) => r.toJson();
}
