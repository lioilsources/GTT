import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/drift.md, version 1: scoring over integer samples the world sends (P0, no
/// randomness). Port of web/src/minigames/drift/rules.ts.
class DriftConfig {
  const DriftConfig({
    required this.level,
    required this.minSlipMrad,
    required this.maxSlipMrad,
    required this.minSpeedCms,
    required this.maxSpeedCms,
    required this.ptsDiv,
    required this.maxDtMs,
    required this.graceMs,
    required this.multStepMs,
    required this.maxMult,
    required this.starScores,
    required this.levelPct,
  });

  factory DriftConfig.fromTuning(TuningMinigamesDrift t, int level) => DriftConfig(
    level: level,
    minSlipMrad: t.minSlipMrad,
    maxSlipMrad: t.maxSlipMrad,
    minSpeedCms: t.minSpeedCms,
    maxSpeedCms: t.maxSpeedCms,
    ptsDiv: t.ptsDiv,
    maxDtMs: t.maxDtMs,
    graceMs: t.graceMs,
    multStepMs: t.multStepMs,
    maxMult: t.maxMult,
    starScores: List.unmodifiable(t.starScores),
    levelPct: List.unmodifiable(t.levelPct),
  );

  factory DriftConfig.fromJson(Map<String, Object?> j) => DriftConfig(
    level: j['level'] as int,
    minSlipMrad: j['minSlipMrad'] as int,
    maxSlipMrad: j['maxSlipMrad'] as int,
    minSpeedCms: j['minSpeedCms'] as int,
    maxSpeedCms: j['maxSpeedCms'] as int,
    ptsDiv: j['ptsDiv'] as int,
    maxDtMs: j['maxDtMs'] as int,
    graceMs: j['graceMs'] as int,
    multStepMs: j['multStepMs'] as int,
    maxMult: j['maxMult'] as int,
    starScores: List.unmodifiable((j['starScores'] as List).cast<int>()),
    levelPct: List.unmodifiable((j['levelPct'] as List).cast<int>()),
  );

  final int level, minSlipMrad, maxSlipMrad, minSpeedCms, maxSpeedCms, ptsDiv, maxDtMs, graceMs, multStepMs, maxMult;

  /// Scores for 3, 2, 1 stars at difficulty 3; star thresholds × % by difficulty 1–5.
  final List<int> starScores, levelPct;

  /// Star thresholds t[0..2] for this level.
  List<int> get thresholds => [for (final s in starScores) s * levelPct[level - 1] ~/ 100];
}

class DriftState {
  const DriftState({
    this.phase = 'run',
    this.clockMs = 0,
    this.lastDriftMs = 0,
    this.score = 0,
    this.chain = 0,
    this.chainMs = 0,
    this.mult = 1,
    this.best = 0,
    this.drifts = 0,
    this.hits = 0,
  });

  /// 'run' or 'over'.
  final String phase;
  final int clockMs, lastDriftMs, score, chain, chainMs, mult, best, drifts, hits;

  DriftState copyWith({
    String? phase,
    int? clockMs,
    int? lastDriftMs,
    int? score,
    int? chain,
    int? chainMs,
    int? mult,
    int? best,
    int? drifts,
    int? hits,
  }) => DriftState(
    phase: phase ?? this.phase,
    clockMs: clockMs ?? this.clockMs,
    lastDriftMs: lastDriftMs ?? this.lastDriftMs,
    score: score ?? this.score,
    chain: chain ?? this.chain,
    chainMs: chainMs ?? this.chainMs,
    mult: mult ?? this.mult,
    best: best ?? this.best,
    drifts: drifts ?? this.drifts,
    hits: hits ?? this.hits,
  );

  /// The open chain banked (spec "Připsání").
  DriftState banked() {
    final b = chain * mult;
    return copyWith(score: score + b, best: math.max(best, b), drifts: drifts + 1, chain: 0, chainMs: 0, mult: 1);
  }

  Map<String, Object?> toJson() => {
    'phase': phase,
    'clockMs': clockMs,
    'lastDriftMs': lastDriftMs,
    'score': score,
    'chain': chain,
    'chainMs': chainMs,
    'mult': mult,
    'best': best,
    'drifts': drifts,
    'hits': hits,
  };
}

/// {by: player, op: sample | hit, atMs, …} or {by: timeout}.
class DriftAction {
  const DriftAction.sample(this.atMs, this.slipMrad, this.speedCms, this.inZone) : by = 'player', op = 'sample';
  const DriftAction.hit(this.atMs) : by = 'player', op = 'hit', slipMrad = 0, speedCms = 0, inZone = false;
  const DriftAction.timeout() : by = 'timeout', op = '', atMs = 0, slipMrad = 0, speedCms = 0, inZone = false;

  final String by, op;
  final int atMs, slipMrad, speedCms;
  final bool inZone;

  Map<String, Object?> toJson() => switch (op) {
    'sample' => {'by': by, 'op': op, 'atMs': atMs, 'slipMrad': slipMrad, 'speedCms': speedCms, 'inZone': inZone},
    'hit' => {'by': by, 'op': op, 'atMs': atMs},
    _ => {'by': by},
  };

  @override
  String toString() => toJson().toString();
}

class DriftResult {
  const DriftResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.best,
    required this.drifts,
    required this.hits,
  });
  final String winner;
  final int stars, score, best, drifts, hits;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'best': best,
    'drifts': drifts,
    'hits': hits,
  };
}

class DriftRules extends MgRules<DriftState, DriftAction, DriftResult> {
  DriftConfig? _cfg;

  DriftConfig get config => _cfg ?? (throw StateError('drift: init first'));

  @override
  String get id => 'drift';

  @override
  int get specVersion => 1;

  /// The seed is unused: the game has no randomness.
  @override
  DriftState init(Map<String, Object?> config, int seed) => start(DriftConfig.fromJson(config));

  DriftState start(DriftConfig config) {
    _cfg = config;
    return const DriftState();
  }

  @override
  List<DriftAction> legalActions(DriftState s) =>
      s.phase == 'run' ? [DriftAction.sample(s.clockMs, 0, 0, false), const DriftAction.timeout()] : const [];

  @override
  DriftState apply(DriftState s, DriftAction a) {
    if (s.phase != 'run') throw IllegalAction(id, a);
    if (a.by == 'timeout') return (s.chain > 0 ? s.banked() : s).copyWith(phase: 'over');
    if (a.by != 'player' || a.atMs < s.clockMs) throw IllegalAction(id, a);
    final c = config;
    switch (a.op) {
      case 'hit':
        return s.copyWith(clockMs: a.atMs, hits: s.hits + 1, chain: 0, chainMs: 0, mult: 1);
      case 'sample':
        if (a.slipMrad < 0 || a.speedCms < 0) throw IllegalAction(id, a);
        final dt = math.min(a.atMs - s.clockMs, c.maxDtMs);
        final t = s.copyWith(clockMs: a.atMs);
        if (a.inZone && a.slipMrad >= c.minSlipMrad && a.speedCms >= c.minSpeedCms) {
          final ang = dt * math.min(a.slipMrad, c.maxSlipMrad) ~/ 1000;
          final pts = ang * math.min(a.speedCms, c.maxSpeedCms) ~/ c.ptsDiv;
          final chainMs = t.chainMs + dt;
          return t.copyWith(
            chain: t.chain + pts,
            chainMs: chainMs,
            mult: math.min(1 + chainMs ~/ c.multStepMs, c.maxMult),
            lastDriftMs: a.atMs,
          );
        }
        if (t.chain > 0 && a.atMs - t.lastDriftMs > c.graceMs) return t.banked();
        return t;
    }
    throw IllegalAction(id, a);
  }

  @override
  DriftAction aiAction(DriftState state, int level, Prng ai) => throw UnsupportedError('drift: no opponent');

  @override
  DriftResult? result(DriftState s) {
    if (s.phase != 'over') return null;
    final t = config.thresholds;
    final stars = s.score >= t[0]
        ? 3
        : s.score >= t[1]
        ? 2
        : s.score >= t[2]
        ? 1
        : 0;
    return DriftResult(
      winner: stars >= 1 ? 'player' : 'draw',
      stars: stars,
      score: s.score,
      best: s.best,
      drifts: s.drifts,
      hits: s.hits,
    );
  }

  /// Strict JSON reading: wrong types are illegal actions (the web side checks the same).
  @override
  DriftAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const DriftAction.timeout();
    final at = j['atMs'];
    if (j['by'] != 'player' || at is! int) throw IllegalAction(id, j);
    switch (j['op']) {
      case 'hit':
        return DriftAction.hit(at);
      case 'sample':
        final slip = j['slipMrad'], speed = j['speedCms'], zone = j['inZone'];
        if (slip is! int || speed is! int || zone is! bool) throw IllegalAction(id, j);
        return DriftAction.sample(at, slip, speed, zone);
    }
    throw IllegalAction(id, j);
  }

  @override
  Map<String, Object?> stateToJson(DriftState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DriftResult r) => r.toJson();
}
