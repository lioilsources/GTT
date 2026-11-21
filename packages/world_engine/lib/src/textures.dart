import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:shared_gen/shared_gen.dart';

/// Procedural facade textures: a 4×4 grid of 64 px window cells, tiled over every wall.
/// White wall pixels keep the vertex colour (modulate), windows darken it; at night some
/// windows glow.
class FacadeTextures {
  FacadeTextures._(this.day, this.night);

  final ui.Image day;
  final ui.Image night;

  late final ui.Paint dayPaint = _paint(day);
  late final ui.Paint nightPaint = _paint(night);

  static ui.Paint _paint(ui.Image img) => ui.Paint()
    ..shader = ui.ImageShader(img, ui.TileMode.repeated, ui.TileMode.repeated, Float64List.fromList(_identity))
    ..filterQuality = ui.FilterQuality.low;

  static const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

  static Future<FacadeTextures> create() async {
    return FacadeTextures._(await _draw(night: false), await _draw(night: true));
  }

  static Future<ui.Image> _draw({required bool night}) {
    const cell = 64.0, size = 256;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    final rnd = math.Random(night ? 7 : 3);
    c.drawRect(const ui.Rect.fromLTWH(0, 0, 256, 256),
        ui.Paint()..color = night ? const ui.Color(Tokens.colorFacadeNightWall) : const ui.Color(Tokens.colorFacadeDayWall));
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        final r = ui.Rect.fromLTWH(i * cell + 12, j * cell + 14, cell - 24, cell - 26);
        ui.Color col;
        if (night) {
          final lit = rnd.nextDouble() < 0.45;
          col = lit
              ? ui.Color.lerp(const ui.Color(Tokens.colorFacadeNightLitA), const ui.Color(Tokens.colorFacadeNightLitB), rnd.nextDouble() * 0.4)!
              : const ui.Color(Tokens.colorFacadeNightDark);
        } else {
          col = ui.Color.lerp(const ui.Color(Tokens.colorFacadeDayGlassA), const ui.Color(Tokens.colorFacadeDayGlassB), rnd.nextDouble())!;
        }
        c.drawRect(r, ui.Paint()..color = col);
        if (!night) {
          // Mullion.
          c.drawRect(ui.Rect.fromLTWH(r.center.dx - 1.5, r.top, 3, r.height), ui.Paint()..color = const ui.Color(Tokens.colorFacadeDayMullion));
        }
      }
    }
    return rec.endRecording().toImage(size, size);
  }
}
