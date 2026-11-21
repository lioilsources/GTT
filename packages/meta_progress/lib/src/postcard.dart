import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_gen/shared_gen.dart';

/// One shape of the placeholder postcard picture on a 300 × 200 canvas (y down). Colours are
/// 0xAARRGGBB from [Tokens]. Real illustrations come later from ComfyUI (tools/artgen).
sealed class PostcardShape {
  const PostcardShape(this.color);
  final int color;
}

class PostcardRect extends PostcardShape {
  const PostcardRect(this.x, this.y, this.w, this.h, super.color);
  final double x, y, w, h;
}

class PostcardCircle extends PostcardShape {
  const PostcardCircle(this.x, this.y, this.r, super.color);
  final double x, y, r;
}

class PostcardPoly extends PostcardShape {
  const PostcardPoly(this.pts, super.color);

  /// Interleaved x, y.
  final List<double> pts;
}

const postcardW = 300.0;
const postcardH = 200.0;

/// 32-bit FNV-1a over the UTF-8 bytes of [s].
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// specs/passport.md "Pohlednice": sky, skyline, then the building (or open space).
List<PostcardShape> postcardShapes(String id, double heightM) {
  const base = 170.0;
  final out = <PostcardShape>[const PostcardRect(0, 0, postcardW, postcardH, Tokens.colorPassportSky)];
  final hash = fnv1a(id);
  for (var i = 0; i < 6; i++) {
    final h = 30 + ((hash >> (4 * i)) & 31);
    out.add(PostcardRect(6.0 + 50 * i, base - h, 44, h.toDouble(), Tokens.colorPassportSkyline));
  }
  if (heightM > 0) {
    out.add(const PostcardRect(0, base, postcardW, postcardH - base, Tokens.colorPassportGround));
    final bh = (30 + 120 * math.min(heightM, 541) / 541).round().toDouble();
    final bw = heightM >= 150 ? 56.0 : 110.0;
    final left = 150 - bw / 2;
    final top = base - bh;
    out.add(PostcardRect(left, top, bw, bh, Tokens.colorPassportTower));
    for (var r = 0; top + 9 + 12 * r + 6 <= 164; r++) {
      for (var c = 0; left + 9 + 12 * c + 6 <= left + bw - 3; c++) {
        out.add(PostcardRect(left + 9 + 12 * c, top + 9 + 12 * r, 6, 6, Tokens.colorPassportWindow));
      }
    }
    if (heightM >= 300) {
      out.add(PostcardPoly([150 - bw / 6, top, 150 + bw / 6, top, 150, top - 22], Tokens.colorPassportTower));
    }
  } else {
    out.add(const PostcardRect(0, 130, postcardW, postcardH - 130, Tokens.colorPassportPark));
    for (var i = 0; i < 5; i++) {
      out.add(PostcardCircle(60.0 + 45 * i, 128, 14, Tokens.colorPassportTree));
    }
  }
  return out;
}
