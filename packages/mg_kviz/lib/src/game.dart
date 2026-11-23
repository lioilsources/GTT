import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Bundle path of a city bank written by `metro sync` (`content/quiz/<city>.json`).
String quizAssetPath(String city) => 'assets/shared/content/quiz/$city.json';

final Map<String, Future<QuizBank>> _banks = {};

/// The bundled bank of [city], loaded once per city; a failed load is retried next time.
Future<QuizBank> _bundledBank(String city) => _banks.putIfAbsent(city, () {
  final f = rootBundle.loadString(quizAssetPath(city), cache: false).then(QuizBank.fromJson);
  f.then<void>(
    (_) {},
    onError: (Object _) {
      _banks.remove(city);
    },
  );
  return f;
});

/// Městský kvíz, specs/minigames/kviz.md: the question on top, four big buttons below, a bar
/// counting down `question_s` (then the answer is -1). After an answer it flashes right / wrong.
class KvizGame implements Minigame {
  const KvizGame({this.loadBank});

  /// Returns the bank JSON of a city; null = the bundled asset ([quizAssetPath]), cached per city.
  final Future<String> Function(String city)? loadBank;

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.kviz]!;

  Future<QuizBank> _bank(String city) {
    final load = loadBank;
    return load == null ? _bundledBank(city) : load(city).then(QuizBank.fromJson);
  }

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.kviz;
    return MinigameShell(
      id: MinigameId.kviz,
      env: env,
      rules: const [MessageKey.kvizRules1, MessageKey.kvizRules2, MessageKey.kvizRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) =>
          _KvizBody(ctx: ctx, env: env, shell: shell, hooks: hooks, bank: _bank(ctx.cityId)),
    );
  }
}

class _KvizBody extends StatefulWidget {
  const _KvizBody({required this.ctx, required this.env, required this.shell, required this.hooks, required this.bank});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;
  final Future<QuizBank> bank;

  @override
  State<_KvizBody> createState() => _KvizBodyState();
}

class _KvizBodyState extends State<_KvizBody> {
  final KvizRules _rules = KvizRules();
  KvizState? _s;

  /// The state of the question still flashing after an answer (already applied to [_s]).
  KvizState? _shown;
  QuizBank? _bank;
  bool _failed = false;

  /// Shown index picked for the current question; -2 = not answered yet.
  int _picked = -2;
  bool _right = false;
  int _leftMs = 0;
  Timer? _qTimer, _nextTimer;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);
  int get _questionMs => widget.env.tuning.minigames.kviz.questionS * 1000;
  String get _lang => widget.env.locale == 'cs' ? 'cs' : 'en';

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.shell.status(''));
    widget.bank.then(
      (b) {
        if (!mounted) return;
        if (b.questions.isEmpty) {
          setState(() => _failed = true);
          return;
        }
        final s = _rules.start(KvizConfig.fromTuning(widget.env.tuning.minigames.kviz, b.answers), widget.ctx.seed);
        setState(() {
          _bank = b;
          _s = s;
        });
        final r = _rules.result(s);
        r != null ? _finish(r) : _startQuestion();
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  @override
  void dispose() {
    _qTimer?.cancel();
    _nextTimer?.cancel();
    super.dispose();
  }

  void _finish(KvizResult r) => widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));

  void _startQuestion() {
    setState(() {
      _shown = null;
      _picked = -2;
      _leftMs = _questionMs;
    });
    _qTimer?.cancel();
    _qTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || widget.shell.paused || _picked != -2) return;
      setState(() => _leftMs -= 100);
      if (_leftMs <= 0) _answer(-1);
    });
  }

  void _answer(int d) {
    final s = _s;
    if (s == null || s.over || _picked != -2 || widget.shell.paused) return;
    _qTimer?.cancel();
    setState(() {
      _picked = d;
      _right = _rules.isRight(s, d);
      _shown = s;
      _s = _rules.apply(s, KvizAction(d));
    });
    void advance() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _nextTimer = Timer(const Duration(milliseconds: 200), advance);
        return;
      }
      final r = _rules.result(_s!);
      r != null ? _finish(r) : _startQuestion();
    }

    _nextTimer = Timer(const Duration(milliseconds: 1100), advance);
  }

  void _timeout() {
    final s = _s;
    if (s == null || s.over) return;
    _qTimer?.cancel();
    _nextTimer?.cancel();
    final n = _rules.apply(s, const KvizAction.timeout());
    setState(() => _s = n);
    _finish(_rules.result(n)!);
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final s = _shown ?? _s, bank = _bank;
    if (s == null || bank == null || s.over) {
      return Center(child: Text(_failed ? t(MessageKey.notYet) : '', style: muted));
    }
    final q = bank.questions[s.order[s.cur]];
    final perm = s.perms[s.cur];
    final options = q.options[_lang] ?? q.options['en']!;
    final fill = (_leftMs / _questionMs).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(MessageKey.kvizQuestion, {'n': s.cur + 1, 'total': s.order.length}),
            style: muted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Tokens.spaceSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fill,
              minHeight: 6,
              backgroundColor: const Color(Tokens.colorUiPill),
              color: const Color(Tokens.colorBrandAccent),
            ),
          ),
          const Spacer(),
          Text(
            q.q[_lang] ?? q.q['en'] ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          for (var d = 0; d < perm.length; d++)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.spaceSm),
              child: SizedBox(
                height: 56,
                child: FilledButton(
                  key: ValueKey('kviz-option-$d'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(_optionColor(s, d)),
                    disabledBackgroundColor: Color(_optionColor(s, d)),
                    foregroundColor: const Color(Tokens.colorUiText),
                    disabledForegroundColor: const Color(Tokens.colorUiText),
                  ),
                  onPressed: _picked == -2 ? () => _answer(d) : null,
                  child: Text(options[perm[d]], textAlign: TextAlign.center),
                ),
              ),
            ),
          SizedBox(
            height: 28,
            child: Text(
              _picked == -2 ? '' : t(_right ? MessageKey.kvizRight : MessageKey.kvizWrong),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(_right ? Tokens.colorWorldDayPark : Tokens.colorUiControlBrake),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _optionColor(KvizState s, int d) {
    if (_picked == -2) return Tokens.colorUiPill;
    if (_rules.isRight(s, d)) return Tokens.colorWorldDayPark;
    if (d == _picked) return Tokens.colorUiControlBrake;
    return Tokens.colorUiPill;
  }
}
