import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

/// Outline of a die: plain, held / selected, or a busted roll.
enum DieRing { none, selected, bust }

/// One die with pips, shared by the dice minigames (same pip layout as the web client's
/// `web/src/minigames/dice.ts`); value 0 draws a blank face.
class DiePainter extends CustomPainter {
  DiePainter({required this.value, this.ring = DieRing.none});

  final int value;
  final DieRing ring;

  static const _pips = <int, List<(double, double)>>{
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = RRect.fromRectAndRadius(Offset.zero & Size.square(s), Radius.circular(s * 0.19));
    canvas.drawRRect(rect, Paint()..color = Color(Tokens.colorWorldDayFacades[0]));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = Color(switch (ring) {
        DieRing.none => Tokens.colorUiTextFaint,
        DieRing.selected => Tokens.colorBrandAccent,
        DieRing.bust => Tokens.colorUiControlBrake,
      })
      ..strokeWidth = s * (ring == DieRing.none ? 0.03 : 0.09);
    canvas.drawRRect(rect, stroke);
    final pip = Paint()..color = const Color(Tokens.colorUiBackground);
    for (final (x, y) in _pips[value] ?? const <(double, double)>[]) {
      canvas.drawCircle(Offset(x * s, y * s), s * 0.1, pip);
    }
  }

  @override
  bool shouldRepaint(DiePainter old) => old.value != value || old.ring != ring;
}
