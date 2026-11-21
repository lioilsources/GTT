import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'chunk.dart';
import 'palette.dart';
import 'tuning.dart';

/// Roof scale for height [h] (METROPOLE_PLAN 6.2):
/// h_eff = h for h ≤ knee, knee + (h − knee)^exp above; s = min(1 + k·h_eff, max_scale).
double extrusionScale(double h, Tuning t) {
  final he = h <= t.extrusionKnee ? h : t.extrusionKnee + math.pow(h - t.extrusionKnee, t.extrusionExp);
  return math.min(1 + t.extrusionK * he, t.extrusionMaxScale);
}

/// Window texture tiling: one window cell is 4 m wide and 3.2 m tall, 64 px square.
const double texPxPerMetreU = 16;
const double texPxPerMetreV = 20;

/// Texture coordinate of a plain wall pixel, used for roofs.
const double roofTexU = 2;
const double roofTexV = 2;

/// Fills one vertex buffer with walls and roofs of many buildings in painter order and
/// flushes it with a single drawVertices call (split only past the 16-bit index limit).
class BuildingBatcher {
  Float32List _pos = Float32List(1 << 15);
  Float32List _tex = Float32List(1 << 15);
  Int32List _col = Int32List(1 << 14);
  Uint16List _idx = Uint16List(1 << 15);
  int _nv = 0;
  int _ni = 0;

  int drawCalls = 0;
  int buildingsDrawn = 0;

  // Scratch for projected footprint points.
  Float32List _bot = Float32List(1024);
  Float32List _top = Float32List(1024);

  void begin() {
    _nv = 0;
    _ni = 0;
    drawCalls = 0;
    buildingsDrawn = 0;
  }

  void _ensure(int verts, int indices) {
    if (_nv + verts > _col.length) {
      final n = math.max(_col.length * 2, _nv + verts);
      _pos = _grow(_pos, n * 2);
      _tex = _grow(_tex, n * 2);
      final c = Int32List(n)..setRange(0, _nv, _col);
      _col = c;
    }
    if (_ni + indices > _idx.length) {
      final n = math.max(_idx.length * 2, _ni + indices);
      _idx = Uint16List(n)..setRange(0, _ni, _idx);
    }
  }

  static Float32List _grow(Float32List a, int n) => Float32List(n)..setRange(0, a.length, a);

  /// Adds one building. [vpX], [vpY] is the vanishing point (the player's car) in world metres.
  void add(ui.Canvas canvas, ui.Paint paint, BuildingData b, double vpX, double vpY, Palette pal, Tuning t,
      {int alpha = 255}) {
    final n = b.vertexCount;
    final walls = n; // upper bound of visible walls
    final needV = walls * 4 + n;
    final needI = walls * 6 + b.roof.length;
    if (needV > 65535) return;
    if (_nv + needV > 65535) flush(canvas, paint);
    _ensure(needV, needI);
    if (_bot.length < n * 2) {
      _bot = Float32List(n * 2);
      _top = Float32List(n * 2);
    }
    final s0 = b.minHeight > 0.5 ? extrusionScale(b.minHeight, t) : 1.0;
    final s1 = extrusionScale(b.height, t);
    final xy = b.xy;
    for (var i = 0; i < n; i++) {
      final dx = xy[2 * i] - vpX, dy = xy[2 * i + 1] - vpY;
      _bot[2 * i] = vpX + dx * s0;
      _bot[2 * i + 1] = vpY + dy * s0;
      _top[2 * i] = vpX + dx * s1;
      _top[2 * i + 1] = vpY + dy * s1;
    }

    final base = b.landmark > 0 ? pal.landmark : pal.facades[b.seed % pal.facades.length];
    final jitter = 0.94 + ((b.seed >> 8) & 0xff) / 255 * 0.12;
    final uOff = ((b.seed >> 16) & 0xff).toDouble();
    final vBot = b.minHeight * texPxPerMetreV, vTop = b.height * texPxPerMetreV;
    final pos = _pos, tex = _tex, col = _col, idx = _idx;
    var nv = _nv, ni = _ni;

    var start = 0;
    for (final end in b.ringEnds) {
      for (var i = start; i < end; i++) {
        final j = i + 1 < end ? i + 1 : start;
        final ax = xy[2 * i], ay = xy[2 * i + 1], bx = xy[2 * j], by = xy[2 * j + 1];
        final ex = bx - ax, ey = by - ay;
        final len = math.sqrt(ex * ex + ey * ey);
        if (len < 0.05) continue;
        // Outward normal (rings are CCW outer, CW holes).
        final nx = ey / len, ny = -ex / len;
        if (nx * (vpX - (ax + bx) / 2) + ny * (vpY - (ay + by) / 2) <= 0) continue;
        final light = pal.ambient + (1 - pal.ambient) * math.max(0.0, nx * pal.sunX + ny * pal.sunY);
        final c = _shade(base, light * jitter, alpha);
        final u0 = uOff + b.wallU[i] * texPxPerMetreU, u1 = u0 + len * texPxPerMetreU;
        pos[2 * nv] = _bot[2 * i];
        pos[2 * nv + 1] = _bot[2 * i + 1];
        pos[2 * nv + 2] = _bot[2 * j];
        pos[2 * nv + 3] = _bot[2 * j + 1];
        pos[2 * nv + 4] = _top[2 * j];
        pos[2 * nv + 5] = _top[2 * j + 1];
        pos[2 * nv + 6] = _top[2 * i];
        pos[2 * nv + 7] = _top[2 * i + 1];
        tex[2 * nv] = u0;
        tex[2 * nv + 1] = vBot;
        tex[2 * nv + 2] = u1;
        tex[2 * nv + 3] = vBot;
        tex[2 * nv + 4] = u1;
        tex[2 * nv + 5] = vTop;
        tex[2 * nv + 6] = u0;
        tex[2 * nv + 7] = vTop;
        col[nv] = c;
        col[nv + 1] = c;
        col[nv + 2] = c;
        col[nv + 3] = c;
        idx[ni] = nv;
        idx[ni + 1] = nv + 1;
        idx[ni + 2] = nv + 2;
        idx[ni + 3] = nv;
        idx[ni + 4] = nv + 2;
        idx[ni + 5] = nv + 3;
        nv += 4;
        ni += 6;
      }
      start = end;
    }

    final roofC = _shade(base, pal.roofLight * jitter, alpha);
    final rb = nv;
    for (var i = 0; i < n; i++) {
      pos[2 * nv] = _top[2 * i];
      pos[2 * nv + 1] = _top[2 * i + 1];
      tex[2 * nv] = roofTexU;
      tex[2 * nv + 1] = roofTexV;
      col[nv] = roofC;
      nv++;
    }
    final roof = b.roof;
    for (var k = 0; k < roof.length; k++) {
      idx[ni++] = rb + roof[k];
    }
    _nv = nv;
    _ni = ni;
    buildingsDrawn++;
  }

  static int _shade(ui.Color c, double k, int alpha) {
    int ch(double v) => (v * 255 * k).clamp(0, 255).toInt();
    return alpha << 24 | ch(c.r) << 16 | ch(c.g) << 8 | ch(c.b);
  }

  void flush(ui.Canvas canvas, ui.Paint paint) {
    if (_ni == 0) return;
    final v = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_pos, 0, _nv * 2),
      textureCoordinates: Float32List.sublistView(_tex, 0, _nv * 2),
      colors: Int32List.sublistView(_col, 0, _nv),
      indices: Uint16List.sublistView(_idx, 0, _ni),
    );
    canvas.drawVertices(v, ui.BlendMode.modulate, paint);
    v.dispose();
    drawCalls++;
    _nv = 0;
    _ni = 0;
  }
}
