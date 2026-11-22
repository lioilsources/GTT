import 'package:flutter/material.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import 'loop_controller.dart';

/// Loop UI over the world (specs/loop.md): cash pill, "Play" context button, "coming soon" toast,
/// the minigame route and the loop result card.
class LoopLayer extends StatefulWidget {
  const LoopLayer({super.key, required this.loop});
  final LoopController loop;

  @override
  State<LoopLayer> createState() => _LoopLayerState();
}

class _LoopLayerState extends State<LoopLayer> {
  LoopController get loop => widget.loop;

  @override
  void initState() {
    super.initState();
    loop.request.addListener(_mount);
  }

  @override
  void dispose() {
    loop.request.removeListener(_mount);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = Localizations.localeOf(context).languageCode;
    loop.locale = messageLocales.contains(lang) ? lang : 'en';
  }

  /// Pushes the requested minigame; the route cannot be popped except through onFinish.
  void _mount() {
    final q = loop.request.value;
    if (q == null || !mounted) return;
    var done = false;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => PopScope(
          canPop: false,
          child: q.game.build(q.ctx, q.env, (r) {
            if (done) return;
            done = true;
            Navigator.of(routeContext).pop();
            loop.finish(r);
          }),
        ),
      ),
    );
  }

  String _mgName(String id) {
    final k = LoopController.nameKey(id);
    return k == null ? id : tr(loop.locale, k);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([loop, loop.playSpot, loop.soon, loop.outcome, loop.game.hud]),
      builder: (context, _) {
        final o = loop.outcome.value;
        final spot = loop.playSpot.value;
        final soon = loop.soon.value;
        return SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: 12,
                bottom: 92,
                child: _Pill(text: l.cashHud(loop.game.fleet.state.cash), color: const Color(Tokens.colorLoopCash)),
              ),
              if (spot != null && o == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 148,
                  child: Center(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(Tokens.colorLoopPlay)),
                      onPressed: () => loop.start(spot.id),
                      child: Text(l.loopPlay(_mgName(spot.minigame))),
                    ),
                  ),
                ),
              if (soon != null)
                Align(
                  alignment: const Alignment(0, 0.35),
                  child: _Pill(text: l.loopSoon(_mgName(soon)), color: const Color(Tokens.colorUiText)),
                ),
              if (o != null)
                Positioned.fill(
                  child: _ResultCard(outcome: o, name: _mgName(o.minigame), loop: loop),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(Tokens.colorUiPill),
      borderRadius: BorderRadius.circular(Tokens.radiusPill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: Tokens.fontHudSmall, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// The loop result (specs/loop.md "Výsledek smyčky"): stars, score, cash and its parts, stamp, best.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.outcome, required this.name, required this.loop});
  final LoopOutcome outcome;
  final String name;
  final LoopController loop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final o = outcome, c = o.cash;
    const muted = TextStyle(color: Color(Tokens.colorLoopMuted));
    final parts = [
      if (c.base > 0) l.loopBase(c.base),
      if (c.trip > 0) l.loopTrip(c.trip),
      if (c.band > 0) l.loopBand(c.band),
      if (c.first > 0) l.loopFirst(c.first),
    ];
    return ColoredBox(
      color: const Color(Tokens.colorUiPill),
      child: Center(
        child: Container(
          width: 360,
          margin: const EdgeInsets.all(Tokens.spaceLg),
          padding: const EdgeInsets.all(Tokens.spaceLg),
          decoration: BoxDecoration(
            color: const Color(Tokens.colorUiSheet),
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.loopTitle,
                  style: const TextStyle(
                    color: Color(Tokens.colorUiText),
                    fontSize: Tokens.fontHud,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Tokens.spaceSm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Text(
                        '★',
                        style: TextStyle(
                          fontSize: 40,
                          color: Color(i < o.stars ? Tokens.colorBrandAccent : Tokens.colorUiTextFaint),
                        ),
                      ),
                  ],
                ),
                Text(l.scoreValue(o.score), style: const TextStyle(color: Color(Tokens.colorUiText))),
                const SizedBox(height: Tokens.spaceSm),
                if (o.aborted)
                  Text(l.loopAborted, style: muted)
                else
                  Text(
                    l.loopCash(c.amount + o.booth),
                    style: const TextStyle(
                      color: Color(Tokens.colorLoopCash),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                for (final p in parts) Text(p, style: muted),
                if (o.booth > 0) Text(l.loopBooth(o.booth), style: muted),
                if (o.stamp)
                  Text(
                    l.loopStamp(name),
                    style: const TextStyle(color: Color(Tokens.colorLoopStamp), fontWeight: FontWeight.w700),
                  )
                else if (!o.hasStamp)
                  Text(l.loopStampHint, style: muted, textAlign: TextAlign.center),
                if (o.newBest && o.stars > 0)
                  Text(
                    l.loopBest,
                    style: const TextStyle(color: Color(Tokens.colorLoopBest), fontWeight: FontWeight.w700),
                  ),
                Text(l.cashHud(o.total), style: muted),
                const SizedBox(height: Tokens.spaceMd),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: loop.closeResult, child: Text(l.loopDrive)),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: () => loop.closeResult(feed: true), child: Text(l.loopFeed)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
