import 'dart:convert';

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/kviz.md, version 1. Pure Dart: no Flutter imports here.
/// [bank] = the correct option index of every bank question, in bank order.
class KvizConfig {
  const KvizConfig({required this.bank, required this.rounds, required this.starCorrect});

  factory KvizConfig.fromTuning(TuningMinigamesKviz t, List<int> bank) =>
      KvizConfig(bank: List.unmodifiable(bank), rounds: t.rounds, starCorrect: List.unmodifiable(t.starCorrect));

  factory KvizConfig.fromJson(Map<String, Object?> j) => KvizConfig(
    bank: List.unmodifiable((j['bank'] as List).cast<int>()),
    rounds: j['rounds'] as int,
    starCorrect: List.unmodifiable((j['starCorrect'] as List).cast<int>()),
  );

  final List<int> bank;
  final int rounds;
  final List<int> starCorrect;
}

class KvizState {
  const KvizState({
    required this.config,
    required this.order,
    required this.perms,
    required this.cur,
    required this.correct,
    required this.answers,
    required this.over,
    required this.rng,
  });

  /// Carried along for the rules (not part of the vector state).
  final KvizConfig config;

  /// Bank indices of the questions in play.
  final List<int> order;

  /// perms[k][d] = the original option shown at position d of question k.
  final List<List<int>> perms;
  final int cur, correct;

  /// Chosen shown indices, -1 = the question timer ran out.
  final List<int> answers;
  final bool over;
  final int rng;

  KvizState copyWith({int? cur, int? correct, List<int>? answers, bool? over}) => KvizState(
    config: config,
    order: order,
    perms: perms,
    cur: cur ?? this.cur,
    correct: correct ?? this.correct,
    answers: answers ?? this.answers,
    over: over ?? this.over,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'order': order,
    'perms': perms,
    'cur': cur,
    'correct': correct,
    'answers': answers,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, answer: -1…3} or {by: timeout}.
class KvizAction {
  const KvizAction(this.answer) : by = 'player';
  const KvizAction.timeout() : by = 'timeout', answer = 0;

  final String by;
  final int answer;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'answer': answer};

  @override
  bool operator ==(Object other) => other is KvizAction && other.by == by && other.answer == answer;

  @override
  int get hashCode => Object.hash(by, answer);

  @override
  String toString() => toJson().toString();
}

class KvizResult {
  const KvizResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.correct,
    required this.rounds,
  });

  final String winner;
  final int stars, score, correct, rounds;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'correct': correct,
    'rounds': rounds,
  };
}

class KvizRules extends MgRules<KvizState, KvizAction, KvizResult> {
  @override
  String get id => 'kviz';

  @override
  int get specVersion => 1;

  @override
  KvizState init(Map<String, Object?> config, int seed) => start(KvizConfig.fromJson(config), seed);

  KvizState start(KvizConfig c, int seed) {
    final rng = Prng(seed);
    final n = c.bank.length;
    final rounds = c.rounds < n ? c.rounds : n;
    final idx = List.generate(n, (i) => i);
    for (var i = 0; i < rounds; i++) {
      final j = i + rng.nextInt(n - i);
      final t = idx[i];
      idx[i] = idx[j];
      idx[j] = t;
    }
    final order = List<int>.unmodifiable(idx.take(rounds));
    final perms = <List<int>>[
      for (var k = 0; k < order.length; k++)
        () {
          final p = [0, 1, 2, 3];
          for (var i = 3; i >= 1; i--) {
            final j = rng.nextInt(i + 1);
            final t = p[i];
            p[i] = p[j];
            p[j] = t;
          }
          return List<int>.unmodifiable(p);
        }(),
    ];
    return KvizState(
      config: c,
      order: order,
      perms: List.unmodifiable(perms),
      cur: 0,
      correct: 0,
      answers: const [],
      over: rounds == 0,
      rng: rng.state,
    );
  }

  @override
  List<KvizAction> legalActions(KvizState s) =>
      s.over ? const [] : const [KvizAction(0), KvizAction(1), KvizAction(2), KvizAction(3), KvizAction(-1)];

  /// True when shown option [d] of the current question is the right one.
  bool isRight(KvizState s, int d) => d >= 0 && s.perms[s.cur][d] == s.config.bank[s.order[s.cur]];

  @override
  KvizState apply(KvizState s, KvizAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != 'player' || a.answer < -1 || a.answer > 3) throw IllegalAction(id, a);
    final cur = s.cur + 1;
    return s.copyWith(
      cur: cur,
      correct: isRight(s, a.answer) ? s.correct + 1 : s.correct,
      answers: List.unmodifiable([...s.answers, a.answer]),
      over: cur >= s.order.length,
    );
  }

  @override
  KvizAction aiAction(KvizState s, int level, Prng ai) => throw UnsupportedError('kviz: no opponent');

  @override
  KvizResult? result(KvizState s) {
    if (!s.over) return null;
    final c = s.config;
    final rounds = s.order.length;
    final need = [for (final t in c.starCorrect) rounds < c.rounds ? (t * rounds) ~/ c.rounds : t];
    var stars = 0;
    for (var k = 0; k < need.length; k++) {
      if (s.correct >= need[k]) {
        stars = need.length - k;
        break;
      }
    }
    return KvizResult(
      winner: stars >= 1 ? 'player' : 'ai',
      stars: stars,
      score: s.correct * 100,
      correct: s.correct,
      rounds: rounds,
    );
  }

  @override
  KvizAction actionFromJson(Map<String, Object?> json) =>
      json['by'] == 'timeout' ? const KvizAction.timeout() : KvizAction(json['answer'] as int);

  @override
  Map<String, Object?> stateToJson(KvizState state) => state.toJson();

  @override
  Map<String, Object?> resultToJson(KvizResult result) => result.toJson();
}

/// One question of `content/quiz/<city>.json` (written by `metro sync`).
class QuizQuestion {
  const QuizQuestion({required this.id, required this.q, required this.options, required this.answer});

  factory QuizQuestion.fromJson(Map<String, Object?> j) => QuizQuestion(
    id: j['id'] as String,
    q: (j['q'] as Map).cast<String, String>(),
    options: {for (final e in (j['options'] as Map).entries) e.key as String: (e.value as List).cast<String>()},
    answer: j['answer'] as int,
  );

  final String id;

  /// Question text by language ('en', 'cs').
  final Map<String, String> q;

  /// The four options by language, in file order.
  final Map<String, List<String>> options;
  final int answer;
}

class QuizBank {
  const QuizBank(this.questions);

  factory QuizBank.fromJson(String json) => QuizBank([
    for (final q in ((jsonDecode(json) as Map)['questions'] as List).cast<Map<String, Object?>>())
      QuizQuestion.fromJson(q),
  ]);

  final List<QuizQuestion> questions;

  /// The rules' view of the bank: correct indices in bank order.
  List<int> get answers => [for (final q in questions) q.answer];
}
