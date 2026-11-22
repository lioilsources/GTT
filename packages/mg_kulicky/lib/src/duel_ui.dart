import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

/// UI bits shared by the flick duels (Kuličky, Čára, Nohejbal); same visual language as Koulená.

/// A swipe shorter than this (upwards) is no throw.
const duelMinSwipePx = 12.0;

/// Pause-aware delayed call: waits [d], then keeps re-checking while the shell is paused.
class DuelTimer {
  Timer? _t;

  void later(Duration d, bool Function() paused, VoidCallback fn) {
    _t?.cancel();
    void run() {
      if (paused()) {
        _t = Timer(const Duration(milliseconds: 200), run);
        return;
      }
      _t = null;
      fn();
    }

    _t = Timer(d, run);
  }

  void cancel() {
    _t?.cancel();
    _t = null;
  }
}

/// Board millimetres (y up) → canvas px, fitted and centred in [size].
class BoardMap {
  factory BoardMap(Size size, double left, double top, double width, double height) {
    final k = math.min(size.width / width, size.height / height);
    return BoardMap._(left, top, k, (size.width - width * k) / 2, (size.height - height * k) / 2);
  }

  const BoardMap._(this.left, this.top, this.k, this.ox, this.oy);

  final double left, top, k, ox, oy;

  Offset p(num x, num y) => Offset(ox + (x - left) * k, oy + (top - y) * k);
}

/// A marble, coin or player disc: [fill] with a text-coloured rim; [faded] for a burnt coin.
void drawDisc(Canvas canvas, Offset c, double r, int fill, double k, {bool faded = false}) {
  final a = faded ? 0.45 : 1.0;
  canvas.drawCircle(c, r, Paint()..color = Color(fill).withValues(alpha: Color(fill).a * a));
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..color = const Color(Tokens.colorUiText).withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * k,
  );
}

/// Aim guide like Koulená's.
void drawGuide(Canvas canvas, Offset from, Offset to, double k) {
  canvas.drawLine(
    from,
    to,
    Paint()
      ..color = const Color(Tokens.colorUiControlHint)
      ..strokeWidth = 8 * k
      ..strokeCap = StrokeCap.round,
  );
}

/// Turn line above the board and the round note below it.
class DuelFrame extends StatelessWidget {
  const DuelFrame({super.key, required this.info, required this.note, required this.flash, required this.board});

  final String info, note;
  final bool flash;
  final Widget board;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Tokens.spaceMd),
    child: Column(
      children: [
        Text(info, style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
        Expanded(child: board),
        SizedBox(
          height: 32,
          child: Text(
            note,
            style: TextStyle(
              color: Color(flash ? Tokens.colorBrandAccent : Tokens.colorUiText),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
