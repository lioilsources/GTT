import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Canvas, Color, Offset, Paint, Rect, RSTransform;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:game_loop/game_loop.dart' show garageDecalIds, garageWheelIds;
import 'package:shared_gen/shared_gen.dart' show Tokens;

// Car sprites (specs/art.md v2 "Auta"): `assets/cars/<id>/{body,paint_mask,wheel,lights}.png`
// replace only the drawing; sizes, collisions and the shadow stay from the JSON and the code.

/// Sprite pixels per metre of the real car (before `car_scale`, docs/art-requests.md kap. 3).
const carSpritePxPerM = 32.0;

/// The sprite canvas is the car size × this (a 5 % margin all round, docs/art-requests.md kap. 3).
const carSpriteCanvas = 1.1;

/// Pre-tinted bodies kept decoded (specs/art.md: LRU 48, apart from the 24 portraits and postcards).
const carSpriteCacheSize = 48;

/// The layer files of one car sprite (paths relative to `assets/`).
class CarSpriteFiles {
  const CarSpriteFiles(this.body, {this.mask, this.wheel, this.lights});
  final String body;

  /// Null for the patrol (not tinted).
  final String? mask;

  /// Null for class `micro` (wheels are in the body).
  final String? wheel;

  /// Optional: without it the code draws the lights as before.
  final String? lights;
}

/// Which files car [id] draws from, or null = procedural (never half): `body.png`, `paint_mask.png`
/// unless [tinted] is false (the patrol) and `wheel.png` unless [wheels] is false (class `micro`)
/// must all be in the art index ([has]); `lights.png` is optional.
CarSpriteFiles? carSpriteFiles(bool Function(String path) has, String id, {bool tinted = true, bool wheels = true}) {
  final d = 'cars/$id/';
  final body = '${d}body.png', mask = '${d}paint_mask.png', wheel = '${d}wheel.png', lights = '${d}lights.png';
  if (!has(body) || (tinted && !has(mask)) || (wheels && !has(wheel))) return null;
  return CarSpriteFiles(
    body,
    mask: tinted ? mask : null,
    wheel: wheels ? wheel : null,
    lights: has(lights) ? lights : null,
  );
}

/// Decal sprite of choice [decal] (specs/art.md v3 "Polep"): `garage/decals/<id>.png`, null for 0
/// or out of range.
String? garageDecalPath(int decal) =>
    decal >= 1 && decal <= garageDecalIds.length ? 'garage/decals/${garageDecalIds[decal - 1]}.png' : null;

/// Garage wheel sprite of choice [wheels] (specs/art.md v3 "Kola"): `garage/wheels/<id>.png`, null
/// for 0 (stock) or out of range.
String? garageWheelPath(int wheels) =>
    wheels >= 1 && wheels <= garageWheelIds.length ? 'garage/wheels/${garageWheelIds[wheels - 1]}.png' : null;

/// Luminance weights of the mask brightness `m` (the mask is greyscale, so any weights summing to 1
/// give the same `m`).
const _lr = 0.2126, _lg = 0.7152, _lb = 0.0722;

/// One channel of the tint (specs/art.md "Lak"): `body × mix(1, paint, m)`, all in 0…1.
double tintChannel(double body, double paint, double m) => body * (1 + (paint - 1) * m);

/// The tinted colour of a body pixel [body] (0xAARRGGBB) under mask brightness [m] (0…1) with
/// [paint] (0xAARRGGBB); the alpha stays the body's.
int tintArgb(int body, int paint, double m) {
  int ch(int shift) {
    final b = ((body >> shift) & 0xff) / 255, p = ((paint >> shift) & 0xff) / 255;
    return (tintChannel(b, p, m) * 255).round().clamp(0, 255);
  }

  return (body & 0xff000000) | ch(16) << 16 | ch(8) << 8 | ch(0);
}

/// Colour matrix turning the mask into the opaque multiplier `mix(1, paint, m)` per channel; drawn
/// over the body with [ui.BlendMode.modulate] it gives `body × mix(1, paint, m)`, alpha the body's.
List<double> tintMatrix(int paint) {
  final c = Color(paint);
  List<double> row(double p) => [-(1 - p) * _lr, -(1 - p) * _lg, -(1 - p) * _lb, 0, 255];
  return [...row(c.r), ...row(c.g), ...row(c.b), 0, 0, 0, 0, 255];
}

/// Colour matrix taking the mask brightness as alpha (decal clip: only on the paint).
const _maskAlpha = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, _lr, _lg, _lb, 0, 0];

/// The decoded layers of one car. All images are flipped upside down at load (the world canvas has
/// y north), so a rotation + uniform scale ([RSTransform]) puts them on the car.
class CarSprite {
  CarSprite._(this.id, this.files, this.body, this.mask, this.wheels, this.lights, this.wheelW, this.wheelH);
  final String id;
  final CarSpriteFiles files;

  /// Source images (body, mask as decoded, not flipped).
  final ui.Image body;
  final ui.Image? mask;

  /// Right wheel | left wheel (mirrored), flipped; null for micro.
  final ui.Image? wheels;

  /// Lights layer, flipped; null = the code draws the lights.
  final ui.Image? lights;

  /// Size of one wheel in px.
  final double wheelW, wheelH;

  int get width => body.width;
  int get height => body.height;
}

/// Loads car sprites lazily (first use) and keeps the pre-tinted bodies in an LRU. Until the layers
/// of a car are decoded, [sprite] returns null and the car is drawn procedurally. Listeners are
/// notified when a car finished loading (the garage preview repaints).
class CarSprites extends ChangeNotifier {
  CarSprites({required this.has, required this.load, this.capacity = carSpriteCacheSize});

  /// No sprites at all (tests, missing index).
  CarSprites.none() : this(has: (_) => false, load: (_) async => throw StateError('no sprites'));

  final bool Function(String path) has;

  /// Decodes one file (path relative to `assets/`).
  final Future<ui.Image> Function(String path) load;
  final int capacity;

  final _cars = <String, CarSprite?>{}; // null value = loading or failed
  final _bodies = <(String, int?, int, bool, int, int), ui.Image>{}; // insertion order = LRU order
  final _lights = <(String, int, int), ui.Image>{}; // stretched lights (traffic, patrol): one size each

  // Garage cosmetics (specs/art.md v3): decoded decal images and garage wheel pairs by choice
  // (null value = loading or failed), garage wheel pairs scaled to a car's wheel.png size.
  final _decals = <int, ui.Image?>{};
  final _garageWheels = <int, ui.Image?>{};
  final _wheelFits = <(int, int, int), ui.Image>{};

  int get cachedBodies => _bodies.length;
  Iterable<(String, int?, int, bool, int, int)> get cachedKeys => _bodies.keys;

  /// The decoded sprite of [id] or null (procedural): not in the index, still loading, or failed.
  CarSprite? sprite(String id, {bool tinted = true, bool wheels = true}) {
    if (_cars.containsKey(id)) return _cars[id];
    final files = carSpriteFiles(has, id, tinted: tinted, wheels: wheels);
    _cars[id] = null;
    if (files != null) _load(id, files);
    return null;
  }

  /// The decal sprite of choice [decal] (as decoded, nose up) or null: not in the index (the
  /// procedural decal), still loading, or failed. Loads lazily; listeners hear when it is ready.
  ui.Image? decalArt(int decal) => _cosmetic(_decals, decal, garageDecalPath(decal));

  /// The garage wheel of choice [wheels] (as decoded, nose up) or null: stock, not in the index (the
  /// car's own wheel in the rim colour), still loading, or failed.
  ui.Image? wheelArt(int wheels) => _cosmetic(_garageWheels, wheels, garageWheelPath(wheels));

  ui.Image? _cosmetic(Map<int, ui.Image?> m, int i, String? path) {
    if (m.containsKey(i)) return m[i];
    m[i] = null;
    if (path == null || !has(path)) return null;
    load(path).then((img) {
      m[i] = img;
      notifyListeners();
    }, onError: (Object _) {});
    return null;
  }

  /// Puts a decoded decal sprite of choice [decal] in place (tests).
  void putDecal(int decal, ui.Image img) => _decals[decal] = img;

  /// Puts a decoded garage wheel of choice [wheels] in place (tests).
  void putWheel(int wheels, ui.Image img) => _garageWheels[wheels] = img;

  /// The garage wheel pair of choice [wheels] scaled to the wheel.png size of [s] (specs/art.md
  /// v3: the garage wheel takes the car's wheel size), built once per size; null without the art.
  ui.Image? wheelFor(CarSprite s, int wheels) {
    final src = wheels > 0 ? wheelArt(wheels) : null;
    if (src == null) return null;
    final w = s.wheelW.round(), h = s.wheelH.round();
    if (w <= 0 || h <= 0) return null;
    return _wheelFits.putIfAbsent((wheels, w, h), () {
      final rec = ui.PictureRecorder();
      Canvas(rec)
        ..scale(w / src.width, h / src.height)
        ..drawImage(src, Offset.zero, Paint()..filterQuality = ui.FilterQuality.medium);
      return _wheelPair(rec.endRecording().toImageSync(w, h));
    });
  }

  /// Puts ready layers in place (the loader, tests).
  CarSprite put(String id, CarSpriteFiles files, ui.Image body, {ui.Image? mask, ui.Image? wheel, ui.Image? lights}) {
    final s = CarSprite._(
      id,
      files,
      body,
      mask,
      wheel == null ? null : _wheelPair(wheel),
      lights == null ? null : _flipped(lights),
      wheel?.width.toDouble() ?? 0,
      wheel?.height.toDouble() ?? 0,
    );
    _cars[id] = s;
    return s;
  }

  Future<void> _load(String id, CarSpriteFiles f) async {
    try {
      final imgs = await Future.wait([
        load(f.body),
        if (f.mask != null) load(f.mask!),
        if (f.wheel != null) load(f.wheel!),
        if (f.lights != null) load(f.lights!),
      ]);
      var i = 1;
      final mask = f.mask != null ? imgs[i++] : null;
      final wheel = f.wheel != null ? imgs[i++] : null;
      final lights = f.lights != null ? imgs[i++] : null;
      put(id, f, imgs[0], mask: mask, wheel: wheel, lights: lights);
      notifyListeners();
    } catch (_) {
      // Unreadable file: this car stays procedural.
    }
  }

  /// The lights of [s] stretched to [w] × [h] px like a stretched body (built once).
  ui.Image lightsFor(CarSprite s, int w, int h) {
    final l = s.lights!;
    if (l.width == w && l.height == h) return l;
    return _lights.putIfAbsent((s.id, w, h), () {
      final rec = ui.PictureRecorder();
      Canvas(rec)
        ..scale(w / l.width, h / l.height)
        ..drawImage(l, Offset.zero, Paint()..filterQuality = ui.FilterQuality.medium);
      return rec.endRecording().toImageSync(w, h);
    });
  }

  /// The body of [s] tinted with [paint] (null = untinted, the patrol) and decal [decal]: the
  /// decal sprite [decalImage] stretched over the canvas (specs/art.md v3), else drawn by
  /// [paintDecal] in car space (metres, x forward, y left, [mPerPx] metres per source px), clipped
  /// to the mask; [outW] × [outH] px (a stretched traffic sprite), flipped. Built once per key in a
  /// [ui.PictureRecorder], then kept in the LRU.
  ui.Image body(
    CarSprite s,
    int? paint, {
    int decal = 0,
    double mPerPx = 1,
    void Function(Canvas c)? paintDecal,
    ui.Image? decalImage,
    int? outW,
    int? outH,
  }) {
    final w = outW ?? s.width, h = outH ?? s.height;
    final drawn = s.mask != null && (paintDecal != null || decalImage != null);
    final key = (s.id, s.mask == null ? null : paint, drawn ? decal : 0, drawn && decalImage != null, w, h);
    final hit = _bodies.remove(key);
    if (hit != null) return _bodies[key] = hit;
    final img = composeCarBody(
      s.body,
      s.mask,
      key.$2,
      w,
      h,
      mPerPx: mPerPx,
      paintDecal: key.$3 == 0 || key.$4 ? null : paintDecal,
      decalImage: key.$4 ? decalImage : null,
    );
    _bodies[key] = img;
    while (_bodies.length > capacity) {
      _bodies.remove(_bodies.keys.first)!.dispose();
    }
    return img;
  }
}

/// The app-wide sprites; [CarSprites.none] until main wires the art index (tests stay procedural).
CarSprites carSprites = CarSprites.none();

/// Composes a body: flipped and scaled to [w] × [h], tinted `body × mix(1, paint, m)` by drawing the
/// mask through [tintMatrix] with [ui.BlendMode.modulate], with the decal clipped to the mask:
/// [decalImage] (a decal sprite, specs/art.md v3) stretched over the canvas in `color.garage.decal`
/// × its alpha, or else [paintDecal]; masked by the paint mask ([ui.BlendMode.dstIn]), then drawn
/// over the body (srcOver).
ui.Image composeCarBody(
  ui.Image body,
  ui.Image? mask,
  int? paint,
  int w,
  int h, {
  double mPerPx = 1,
  void Function(Canvas c)? paintDecal,
  ui.Image? decalImage,
}) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final sw = body.width.toDouble(), sh = body.height.toDouble();
  c.translate(0, h.toDouble());
  c.scale(w / sw, -h / sh);
  final p = Paint()..filterQuality = ui.FilterQuality.medium;
  c.drawImage(body, Offset.zero, p);
  if (mask != null && paint != null) {
    c.drawImage(
      mask,
      Offset.zero,
      Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..colorFilter = ui.ColorFilter.matrix(tintMatrix(paint))
        ..blendMode = ui.BlendMode.modulate,
    );
  }
  if (mask != null && decalImage != null) {
    c.saveLayer(Rect.fromLTWH(0, 0, sw, sh), Paint());
    c.drawImageRect(
      decalImage,
      Rect.fromLTWH(0, 0, decalImage.width.toDouble(), decalImage.height.toDouble()),
      Rect.fromLTWH(0, 0, sw, sh),
      Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..colorFilter = const ui.ColorFilter.mode(Color(Tokens.colorGarageDecal), ui.BlendMode.srcIn),
    );
    c.drawImage(
      mask,
      Offset.zero,
      Paint()
        ..colorFilter = const ui.ColorFilter.matrix(_maskAlpha)
        ..blendMode = ui.BlendMode.dstIn,
    );
    c.restore();
  } else if (mask != null && paintDecal != null) {
    c.saveLayer(Rect.fromLTWH(0, 0, sw, sh), Paint());
    c.save();
    // Car space (x forward = up in the source image, y left) → source px.
    c.translate(sw / 2, sh / 2);
    c.transform(Float64List.fromList([0, -1 / mPerPx, 0, 0, -1 / mPerPx, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    paintDecal(c);
    c.restore();
    c.drawImage(
      mask,
      Offset.zero,
      Paint()
        ..colorFilter = const ui.ColorFilter.matrix(_maskAlpha)
        ..blendMode = ui.BlendMode.dstIn,
    );
    c.restore();
  }
  return rec.endRecording().toImageSync(w, h);
}

ui.Image _flipped(ui.Image img) {
  final rec = ui.PictureRecorder();
  Canvas(rec)
    ..translate(0, img.height.toDouble())
    ..scale(1, -1)
    ..drawImage(img, Offset.zero, Paint());
  return rec.endRecording().toImageSync(img.width, img.height);
}

/// [wheel] flipped, then the same mirrored left/right next to it (the left side of the car).
ui.Image _wheelPair(ui.Image wheel) {
  final w = wheel.width.toDouble(), h = wheel.height.toDouble();
  final rec = ui.PictureRecorder();
  Canvas(rec)
    ..save()
    ..translate(0, h)
    ..scale(1, -1)
    ..drawImage(wheel, Offset.zero, Paint())
    ..restore()
    ..translate(2 * w, h)
    ..scale(-1, -1)
    ..drawImage(wheel, Offset.zero, Paint());
  return rec.endRecording().toImageSync(wheel.width * 2, wheel.height);
}

/// Sprites collected per image and drawn with one [Canvas.drawAtlas] per image and layer: wheels,
/// then bodies, then the procedural extras over the bodies, then the lights (additive).
class CarSpriteBatch {
  final _wheels = <ui.Image, _Runs>{};
  final _bodies = <ui.Image, _Runs>{};
  final _lights = <ui.Image, _Runs>{};
  final _over = <void Function(Canvas c)>[];

  bool get isEmpty => _wheels.isEmpty && _bodies.isEmpty && _lights.isEmpty && _over.isEmpty;

  /// The body [img] ([k] metres per px) centred at (x, y) with the nose at [heading].
  void addBody(ui.Image img, double x, double y, double heading, double k) {
    _add(
      _bodies,
      img,
      _xf(heading, k, img.width / 2, img.height / 2, x, y),
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    );
  }

  /// The lights [img] like [addBody], whole or with [rearOnly] only its rear half.
  void addLights(ui.Image img, double x, double y, double heading, double k, {required bool rearOnly}) {
    final w = img.width.toDouble(), h = img.height.toDouble();
    // Flipped image: the rear is the top half.
    _add(_lights, img, _xf(heading, k, w / 2, h / 2, x, y), Rect.fromLTWH(0, 0, w, rearOnly ? h / 2 : h));
  }

  /// One wheel of [s] centred at car-space (fx, sy) of a car at (x, y, [heading]), turned by
  /// [steer]; [k] metres per px; [tint] multiplies it (garage wheels).
  /// [garage] is a garage wheel pair already scaled to the car's wheel size (replaces wheel.png).
  void addWheel(
    CarSprite s,
    double x,
    double y,
    double heading,
    double fx,
    double sy,
    double steer,
    double k,
    Color? tint, {
    ui.Image? garage,
  }) {
    final img = garage ?? s.wheels!;
    final ch = math.cos(heading), sh = math.sin(heading);
    final wx = x + fx * ch - sy * sh, wy = y + fx * sh + sy * ch;
    final left = sy > 0;
    final r = Rect.fromLTWH(left ? s.wheelW : 0, 0, s.wheelW, s.wheelH);
    _add(_wheels, img, _xf(heading + steer, k, s.wheelW / 2, s.wheelH / 2, wx, wy), r, tint);
  }

  /// Procedural drawing over the bodies (lights without `lights.png`, the patrol beacon).
  void over(void Function(Canvas c) f) => _over.add(f);

  static RSTransform _xf(double heading, double k, double ax, double ay, double x, double y) =>
      RSTransform.fromComponents(
        rotation: heading - math.pi / 2,
        scale: k,
        anchorX: ax,
        anchorY: ay,
        translateX: x,
        translateY: y,
      );

  void _add(Map<ui.Image, _Runs> m, ui.Image img, RSTransform t, Rect r, [Color? tint]) {
    final runs = m.putIfAbsent(img, _Runs.new);
    runs.xf.add(t);
    runs.rects.add(r);
    runs.colors.add(tint ?? const Color(0xffffffff));
    if (tint != null) runs.tinted = true;
  }

  /// Draws everything collected and empties the batch.
  void flush(Canvas canvas) {
    final p = Paint()..filterQuality = ui.FilterQuality.medium;
    void draw(Map<ui.Image, _Runs> m, Paint p) {
      m.forEach((img, r) {
        canvas.drawAtlas(
          img,
          r.xf,
          r.rects,
          r.tinted ? r.colors : null,
          r.tinted ? ui.BlendMode.modulate : null,
          null,
          p,
        );
      });
      m.clear();
    }

    draw(_wheels, p);
    draw(_bodies, p);
    for (final f in _over) {
      f(canvas);
    }
    _over.clear();
    draw(
      _lights,
      Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..blendMode = ui.BlendMode.plus,
    );
  }
}

class _Runs {
  final xf = <RSTransform>[];
  final rects = <Rect>[];
  final colors = <Color>[];
  bool tinted = false;
}
