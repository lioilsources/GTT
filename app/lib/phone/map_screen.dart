import 'dart:async';

import 'package:feed_hub/feed_hub.dart' hide Navigator;
import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import 'phone_controller.dart';

/// The Map app (specs/phone.md "Mapa"): north-up overview of kept roads, spots, player and route.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final Timer _timer;
  final _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick.value++);
  }

  @override
  void dispose() {
    _timer.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _MapPainter(widget.phone, _tick), child: const SizedBox.expand());
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.phone, Listenable tick) : super(repaint: tick);
  final PhoneController phone;
  Path? _roads;
  Size _size = Size.zero;
  ({double s, double ox, double oy}) _fit = (s: 1, ox: 0, oy: 0);

  Offset _p(double x, double y) => Offset(x * _fit.s + _fit.ox, -y * _fit.s + _fit.oy);

  @override
  void paint(Canvas canvas, Size size) {
    final city = phone.game.city, t = phone.tuning.phone;
    if (size != _size || _roads == null) {
      _size = size;
      _fit = mapFit(city.area, size.width, size.height, t.mapPaddingPx);
      final roads = Path();
      for (final e in city.graph.edges) {
        if (!e.kept) continue;
        for (var i = 0; i < e.pointCount; i++) {
          final p = _p(e.pts[2 * i], e.pts[2 * i + 1]);
          i == 0 ? roads.moveTo(p.dx, p.dy) : roads.lineTo(p.dx, p.dy);
        }
      }
      _roads = roads;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Tokens.colorPhoneMapLand));
    canvas.drawPath(
      _roads!,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(Tokens.colorPhoneMapRoad),
    );
    final route = phone.nav.ahead();
    if (route.length >= 4) {
      final path = Path();
      for (var i = 0; i + 1 < route.length; i += 2) {
        final p = _p(route[i], route[i + 1]);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = t.mapRoutePx
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(Tokens.colorUiRouteArrow),
      );
    }
    final target = phone.nav.target?.id;
    for (final s in city.spots.items) {
      // Only a ringing booth shows, as an extra point (specs/booths.md); photo spots are extra points
      // in their colour (specs/photo.md).
      if (s.kind == 'booth' || s.kind == 'photo') continue;
      final game = s.minigame.isNotEmpty;
      final r = t.mapSpotPx * (s.id == target ? 1.6 : 1) * (game ? 1 : 0.7);
      canvas.drawCircle(
        _p(s.x / 10, s.y / 10),
        r,
        Paint()..color = Color(game ? Tokens.colorPhoneMapGame : Tokens.colorPhoneMapSpot),
      );
    }
    for (final f in phone.mapPoints) {
      for (final e in f()) {
        canvas.drawCircle(_p(e.x, e.y), t.mapSpotPx * 1.6, Paint()..color = Color(e.color));
      }
    }
    final car = phone.game.drive.car, pr = t.mapPlayerPx;
    canvas
      ..save()
      ..translate(_p(car.x, car.y).dx, _p(car.x, car.y).dy)
      ..rotate(-car.heading)
      ..drawPath(
        Path()
          ..moveTo(pr * 1.4, 0)
          ..lineTo(-pr, pr)
          ..lineTo(-pr * 0.4, 0)
          ..lineTo(-pr, -pr)
          ..close(),
        Paint()..color = const Color(Tokens.colorPhoneMapPlayer),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.phone != phone;
}
