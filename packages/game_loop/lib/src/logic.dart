// Loop glue (specs/loop.md): pure helpers and the loop book (best results, plays, cash, stamps).
// Port of web/src/loop/logic.ts.
import 'package:meta_progress/meta_progress.dart' show fnv1a;
import 'package:shared_gen/shared_gen.dart';

import 'economy.dart';

/// Difficulty of the minigame at a spot (specs/loop.md "Kontext minihry").
int loopDifficulty(int? cardDifficulty, int plays, TuningFeed feed) {
  final d = cardDifficulty ?? _min(feed.difficultyMax, feed.difficultyBase + plays);
  return d.clamp(1, 5);
}

int _min(int a, int b) => a < b ? a : b;

/// NPC opponent index for a spot: fnv1a(spotId) mod count, -1 without characters.
int opponentIndex(String spotId, int count) => count <= 0 ? -1 : fnv1a(spotId) % count;

typedef BestScore = ({int stars, int score});

/// True when (stars, score) beats the stored best (or there is none).
bool betterBest(BestScore? old, int stars, int score) =>
    old == null || stars > old.stars || (stars == old.stars && score > old.score);

class LoopSpot {
  const LoopSpot(this.id, this.minigame, this.x, this.y);
  final String id;
  final String minigame;

  /// Parking point, metres.
  final double x, y;
}

/// The nearest spot with a minigame within loop.spot_radius_m while the car stands (layer 0).
LoopSpot? spotInReach(List<LoopSpot> spots, double x, double y, double speed, int layer, TuningLoop t) {
  if (speed > t.stopSpeedMps || layer != 0) return null;
  return nearestSpot(spots, x, y, t.spotRadiusM);
}

LoopSpot? nearestSpot(List<LoopSpot> spots, double x, double y, double radius) {
  LoopSpot? best;
  var bd = radius * radius;
  for (final s in spots) {
    if (s.minigame.isEmpty) continue;
    final d = (s.x - x) * (s.x - x) + (s.y - y) * (s.y - y);
    if (d <= bd) {
      bd = d;
      best = s;
    }
  }
  return best;
}

/// Where the loop reads and writes the state it does not own (cash: cars state, stamps: passport).
class LoopPorts {
  const LoopPorts({required this.getCash, required this.setCash, required this.stamp});
  final int Function() getCash;
  final void Function(int cash) setCash;

  /// Passport minigame(id, stars); true when a new stamp was added.
  final bool Function(String minigame, int stars) stamp;
}

/// Everything the result screen shows (specs/loop.md "Výsledek smyčky").
class LoopOutcome {
  const LoopOutcome({
    required this.spot,
    required this.minigame,
    required this.stars,
    required this.score,
    required this.aborted,
    required this.cash,
    required this.total,
    required this.firstTime,
    required this.newBest,
    required this.stamp,
    required this.hasStamp,
  });
  final String spot, minigame;
  final int stars, score;
  final bool aborted;
  final EconomyLast cash;

  /// Cash after the reward.
  final int total;
  final bool firstTime, newBest, stamp, hasStamp;
}

/// Best results, plays per spot and the economy of one session.
class LoopBook {
  LoopBook(this.tuning, this.ports) {
    eco = economy.start(EconomyConfig.fromTuning(tuning, ports.getCash()));
  }

  final Tuning tuning;
  final LoopPorts ports;
  final economy = EconomyRules();
  late EconomyState eco;
  Map<String, BestScore> best = {};
  Map<String, int> plays = {};

  void restore(Map<String, BestScore> b, Map<String, int> p) {
    best = {...b};
    plays = {...p};
  }

  /// One economy action on the cash held by the cars state.
  EconomyLast pay(EconomyAction a) {
    eco = economy.apply(eco.withCash(ports.getCash()), a);
    ports.setCash(eco.cash);
    return eco.last;
  }

  EconomyLast tow() => pay(const EconomyAction.tow());

  /// Police fine hook (the police feature calls this).
  EconomyLast fine(int amount) => pay(EconomyAction.fine(amount < 0 ? 0 : amount));

  LoopOutcome finish({
    required String spot,
    required String minigame,
    required String engine,
    required MinigameResult result,
    required int driveDm,
    required bool Function(String id) hasStamp,
  }) {
    final r = result;
    final stars = r.aborted ? 0 : r.stars;
    final old = best[minigame];
    final firstTime = old == null || old.stars < 1;
    final cash = pay(
      EconomyAction.reward(
        engine: engine,
        stars: stars,
        score: r.score,
        first: firstTime,
        driveDm: driveDm,
        aborted: r.aborted,
      ),
    );
    final stamp = r.aborted ? false : ports.stamp(minigame, stars);
    final newBest = !r.aborted && betterBest(old, stars, r.score);
    if (newBest) best = {...best, minigame: (stars: stars, score: r.score)};
    if (!r.aborted) plays = {...plays, spot: (plays[spot] ?? 0) + 1};
    return LoopOutcome(
      spot: spot,
      minigame: minigame,
      stars: stars,
      score: r.score,
      aborted: r.aborted,
      cash: cash,
      total: eco.cash,
      firstTime: firstTime && cash.first > 0,
      newBest: newBest,
      stamp: stamp,
      hasStamp: hasStamp(minigame),
    );
  }
}
