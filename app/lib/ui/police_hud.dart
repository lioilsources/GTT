import 'dart:async';

import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';

/// Police HUD (specs/police.md "Kreslení a HUD"): wanted badges top centre, a short reason toast
/// and the "busted" card. Thin widget over the Police hooks.
class PoliceHud extends StatefulWidget {
  const PoliceHud({super.key, required this.police});

  final Police police;

  @override
  State<PoliceHud> createState() => _PoliceHudState();
}

class _PoliceHudState extends State<PoliceHud> {
  int _level = 0;
  String? _toast;
  int? _fine;
  Timer? _toastTimer;
  Timer? _cardTimer;

  Police get _p => widget.police;

  @override
  void initState() {
    super.initState();
    _level = _p.wantedLevel;
    _p.onOffence.add(_onOffence);
    _p.onWantedChanged.add(_onWanted);
    _p.onFined.add(_onFined);
  }

  @override
  void dispose() {
    _p.onOffence.remove(_onOffence);
    _p.onWantedChanged.remove(_onWanted);
    _p.onFined.remove(_onFined);
    _toastTimer?.cancel();
    _cardTimer?.cancel();
    super.dispose();
  }

  Duration _s(double s) => Duration(milliseconds: (s * 1000).round());

  void _say(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(_s(_p.tuning.police.toastS), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _onOffence(String kind) {
    final l = AppLocalizations.of(context);
    _say(switch (kind) {
      'crash' => l.policeReason_crash,
      'hitrun' => l.policeReason_hitrun,
      'sidewalk' => l.policeReason_sidewalk,
      _ => l.policeReason_theft,
    });
  }

  void _onWanted(WantedChange e) {
    setState(() => _level = e.level);
    if (e.reason == 'escape' && e.level == 0) _say(AppLocalizations.of(context).policeEscaped);
  }

  void _onFined(int amount) {
    _cardTimer?.cancel();
    _toastTimer?.cancel();
    setState(() {
      _fine = amount;
      _toast = null;
    });
    _cardTimer = Timer(_s(_p.tuning.police.bustedS), () {
      if (mounted) setState(() => _fine = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_p.enabled) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final max = _p.tuning.police.maxLevel;
    return IgnorePointer(
      child: SafeArea(
        child: Stack(
          children: [
            if (_level > 0)
              Positioned(
                top: 44,
                left: 0,
                right: 0,
                child: Center(
                  child: Semantics(
                    label: l.policeWanted(_level),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < max; i++)
                          Icon(
                            Icons.star,
                            size: 24,
                            color: Color(i < _level ? Tokens.colorPoliceStar : Tokens.colorPoliceStarEmpty),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_toast case final text?)
              Positioned(
                top: 76,
                left: 24,
                right: 24,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorPoliceToast),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontNotice),
                    ),
                  ),
                ),
              ),
            if (_fine case final amount?)
              Align(
                alignment: const Alignment(0, -0.25),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Transform.rotate(
                    angle: -0.035,
                    child: Transform.scale(scale: v, child: child),
                  ),
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorPoliceBusted),
                      border: Border.all(color: const Color(Tokens.colorPoliceBustedEdge), width: 3),
                      borderRadius: BorderRadius.circular(Tokens.radiusButton),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.policeBusted,
                          style: const TextStyle(
                            color: Color(Tokens.colorUiText),
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.policeFine(amount),
                          style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontHud),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
