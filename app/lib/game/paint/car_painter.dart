import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:game_loop/game_loop.dart' show CarLook;
import 'package:shared_gen/shared_gen.dart';
import 'package:world_engine/world_engine.dart' show extrusionScale;

import 'car_shape.dart';
import 'car_sprites.dart';

/// How a car in a hop is drawn (specs/hop.md "Kreslení"): centre lifted towards the viewer,
/// size [scale] (like an extruded height), and [flip] = cos of the roll angle (1 upright, −1 upside
/// down) that scales the body width.
typedef CarLift = ({double x, double y, double scale, double flip});

/// A car's look as drawn (specs/garage.md "Kreslení"): the resolved [look], the underglow margin
/// `garage.glow_margin_m` and its strength [glow] (1 at night or in a tunnel, `garage.glow_day` by day).
typedef LookPaint = ({CarLook look, double glowMarginM, double glow});

/// The look of an owned car in the world: full glow at night or in a tunnel (layer < 0).
LookPaint lookPaint(CarLook look, TuningGarage t, {required bool night, int layer = 0}) =>
    (look: look, glowMarginM: t.glowMarginM, glow: night || layer < 0 ? 1.0 : t.glowDay);

/// Lift of a car [heightM] above the ground at (x, y), seen from the vanishing point (vpX, vpY).
CarLift carLift(double x, double y, double vpX, double vpY, double heightM, double rollRad, Tuning t) {
  final s = extrusionScale(heightM, t);
  return (x: vpX + (x - vpX) * s, y: vpY + (y - vpY) * s, scale: s, flip: math.cos(rollRad));
}

/// Top-down car drawn in world space (canvas transformed to metres, y north). With [lift] the car
/// is in the air: no shadow here ([paintHopShadow] draws it on the ground), lifted and rolled.
/// [shadow] is the city's ground shadow by day (specs/style.md).
void paintCar(
  Canvas canvas,
  Car car, {
  required bool night,
  CarLift? lift,
  Color shadow = const Color(Tokens.colorCarShadow),
  LookPaint? look,
}) {
  _paintShape(
    canvas,
    car.spec,
    lift?.x ?? car.x,
    lift?.y ?? car.y,
    car.heading,
    car.halfLength,
    car.halfWidth,
    car.axleOffset,
    wheelAngle: car.wheelAngle,
    night: night,
    cone: night && lift == null,
    rear: car.braking || car.reversing
        ? (car.reversing ? const Color(Tokens.colorCarReverse) : const Color(Tokens.colorCarBrake))
        : null,
    lift: lift,
    shadow: shadow,
    look: look,
  );
}

/// A car from above for the garage preview (specs/garage.md "Vzhled") and the garage list
/// (specs/cars.md "Garáž"): drawn like in the world with [look], nose up ([sideways]: nose right),
/// centred in [size] and scaled to fit; straight wheels, lights off.
void paintCarPreview(Canvas canvas, Size size, CarSpec spec, Tuning t, LookPaint? look, {bool sideways = false}) {
  final hl = spec.lengthM * t.carScale / 2, hw = spec.widthM * t.carScale / 2;
  final margin = (look?.glowMarginM ?? 0) + 0.6;
  final (along, across) = sideways ? (size.width, size.height) : (size.height, size.width);
  final k = math.min(along / (2 * (hl + margin)), across / (2 * (hw + margin)));
  canvas.save();
  canvas.translate(size.width / 2, size.height / 2);
  // World space is y north: flip so the car's left is on the screen's left, then turn the nose up.
  canvas.scale(k, -k);
  _paintShape(
    canvas,
    spec,
    0,
    0,
    sideways ? 0 : math.pi / 2,
    hl,
    hw,
    hl * t.drive.axleOffset,
    wheelAngle: 0,
    night: false,
    cone: false,
    look: look,
  );
  canvas.restore();
}

/// The shadow of a car in a hop: stays on the ground under the car and shrinks with the height
/// (inverse of the lift scale).
void paintHopShadow(Canvas canvas, Car car, CarLift lift, {Color shadow = const Color(Tokens.colorCarShadow)}) {
  final hl = car.halfLength, hw = car.halfWidth;
  final r = carShape(car.spec.class_, hl, hw, lengthM: car.spec.lengthM).first;
  final k = 1 / lift.scale;
  canvas.save();
  canvas.translate(car.x, car.y);
  canvas.rotate(car.heading);
  canvas.scale(k, k);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), Radius.circular(hw * 0.5)),
    Paint()..color = shadow,
  );
  canvas.restore();
}

/// Parked cars (specs/cars.md): same shape, straight wheels, lights off. [lookOf] gives the look of
/// a car the player left parked (specs/garage.md); null = the catalog drawing.
void paintParked(
  Canvas canvas,
  Iterable<ParkedCar> cars,
  Map<String, CarSpec> specs,
  Tuning t, {
  Color shadow = const Color(Tokens.colorCarShadow),
  LookPaint? Function(ParkedCar p)? lookOf,
}) {
  // Sprite cars go into one batch (one drawAtlas per image and layer), procedural ones draw now.
  final batch = CarSpriteBatch();
  for (final p in cars) {
    final s = specs[p.carId];
    if (s == null) continue;
    final hl = s.lengthM * t.carScale / 2, hw = s.widthM * t.carScale / 2;
    _paintShape(
      canvas,
      s,
      p.x,
      p.y,
      p.heading,
      hl,
      hw,
      hl * t.drive.axleOffset,
      wheelAngle: 0,
      night: false,
      cone: false,
      shadow: shadow,
      look: lookOf?.call(p),
      batch: batch,
    );
  }
  batch.flush(canvas);
}

void _paintShape(
  Canvas canvas,
  CarSpec spec,
  double x,
  double y,
  double heading,
  double hl,
  double hw,
  double axle, {
  required double wheelAngle,
  required bool night,
  required bool cone,
  Color? rear,
  CarLift? lift,
  Color shadow = const Color(Tokens.colorCarShadow),
  LookPaint? look,
  CarSpriteBatch? batch,
}) {
  final p = Paint();
  final lk = look?.look;
  final paint = Color(lk?.paint ?? paintArgb(spec));
  final micro = spec.class_ == 'micro';
  final shape = carShape(spec.class_, hl, hw, lengthM: spec.lengthM, axle: axle);
  final body = bodyBounds(shape, micro: micro);
  canvas.save();
  canvas.translate(x, y);
  canvas.rotate(heading);
  RRect rr(CarRect r, double radius) =>
      RRect.fromRectAndRadius(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), Radius.circular(radius));
  if (lift != null) {
    canvas.scale(lift.scale, lift.scale * lift.flip);
    if (lift.flip < 0) {
      // Past the quarter turn the underside faces up: the body outline as a dark floor.
      p.color = const Color(Tokens.colorCarTyre);
      canvas.drawRRect(rr(body, hw * 0.45), p);
      canvas.restore();
      return;
    }
  } else {
    // Underglow under the shadow (specs/garage.md "glow"), then the shadow, the headlight cone and
    // the wheels under the body.
    final glow = lk?.glow;
    if (glow != null && look!.glow > 0) {
      final m = look.glowMarginM;
      final c = Color(glow);
      p.color = c.withValues(alpha: c.a * look.glow.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(body.x0 - m, body.y0 - m, body.x1 + m, body.y1 + m),
          Radius.circular(hw * 0.5 + m),
        ),
        p,
      );
    }
    p.color = shadow;
    canvas.drawRRect(rr(shape.first, hw * 0.5), p);
  }
  if (cone && !micro) {
    final path = Path()
      ..moveTo(hl, hw * 0.6)
      ..lineTo(hl + 14 * hw, hw * 4)
      ..lineTo(hl + 14 * hw, -hw * 4)
      ..lineTo(hl, -hw * 0.6)
      ..close();
    p.color = const Color(Tokens.colorCarHeadlightCone);
    canvas.drawPath(path, p);
  }
  final sprite = carSprites.sprite(spec.id, wheels: !micro);
  if (sprite != null) {
    // Sprite (specs/art.md v2 "Auta"): without a lift into [batch] in world coordinates, otherwise
    // drawn now in the car's frame (the canvas is already moved, turned and scaled).
    final b = lift == null ? batch : null;
    final own = b ?? CarSpriteBatch();
    final (bx, by, bh) = b == null ? (0.0, 0.0, 0.0) : (x, y, heading);
    _addSprite(
      own,
      sprite,
      spec,
      shape,
      bx,
      by,
      bh,
      hl,
      hw,
      axle,
      paint: paint,
      look: lk,
      wheelAngle: wheelAngle,
      night: night,
      rear: rear,
    );
    if (b == null) own.flush(canvas);
    canvas.restore();
    return;
  }
  p.color = const Color(Tokens.colorCarTyre);
  // A garage wheel sprite (specs/art.md v3 "Kola") replaces the procedural wheel, tinted by the rim.
  final wheelArt = micro || (lk?.wheels ?? 0) == 0 ? null : carSprites.wheelArt(lk!.wheels);
  final wheelTint = wheelArt == null ? null : _tinted(Color(lk!.rim ?? Tokens.colorGarageWheels.first));
  // Long vehicles (limo, van, bus) keep car-sized wheels: at most hw long.
  final ww = math.min(hl * 0.36, hw), wt = hw * 0.32;
  // Micro vehicles carry their wheels in the shape, the trike and the rickshaw their front one.
  for (final (fx, sy) in carWheels(spec.class_, hl, hw, axle, lengthM: spec.lengthM)) {
    canvas.save();
    canvas.translate(fx, sy);
    if (fx > 0) canvas.rotate(wheelAngle);
    if (wheelArt != null) {
      drawImageOnCar(canvas, wheelArt, -ww / 2, -wt / 2, ww / 2, wt / 2, wheelTint!, mirror: sy > 0);
      canvas.restore();
      continue;
    }
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: ww, height: wt), p);
    final rim = lk?.rim;
    if (rim != null) {
      p.color = Color(rim);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: ww * 0.5, height: wt * 0.55), p);
      p.color = const Color(Tokens.colorCarTyre);
    }
    canvas.restore();
  }
  final decal = lk?.decal ?? 0;
  // A decal sprite (specs/art.md v3 "Polep") replaces the procedural decal of that choice: over
  // 2 hl × 2 hw, clipped to the body, right after the body (under the glass, details and lights).
  final decalArt = decal == 0 ? null : carSprites.decalArt(decal);
  var decalDone = decal == 0 || decalArt != null;
  var artPending = decalArt != null;
  void artDecal() {
    artPending = false;
    canvas.save();
    canvas.clipPath(_bodyClip(shape, hw));
    drawImageOnCar(canvas, decalArt!, -hl, -hw, hl, hw, _decalPaint);
    canvas.restore();
  }

  var bodyDrawn = false;
  for (final r in shape.skip(1)) {
    if (artPending && bodyDrawn && r.part != CarPart.body) artDecal();
    // The decal goes over the body, the cabin and the class details (muscle stripes, taxi checker),
    // under the lights, a rider and a wheel over the body (trike, rickshaw), as client W.
    if (!decalDone &&
        (r.part == CarPart.head ||
            r.part == CarPart.tail ||
            r.part == CarPart.rider ||
            (r.part == CarPart.wheel && bodyDrawn))) {
      decalDone = true;
      paintCarDecal(canvas, decal, body, [
        for (final q in shape)
          if (q.part == CarPart.body) q,
      ], hw);
    }
    if (r.part == CarPart.body) bodyDrawn = true;
    switch (r.part) {
      case CarPart.body:
        p.color = paint;
        canvas.drawRRect(rr(r, hw * 0.45), p);
      case CarPart.cabin:
        p.color = const Color(Tokens.colorCarCabin);
        canvas.drawRRect(rr(r, hw * 0.25), p);
      case CarPart.glass:
        p.color = Color.lerp(paint, const Color(Tokens.colorUiText), 0.12)!;
        canvas.drawRRect(rr(r, hw * 0.2), p);
      case CarPart.head:
        p.color = night ? const Color(Tokens.colorCarHeadlightNight) : const Color(Tokens.colorCarHeadlightDay);
        canvas.drawRect(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      case CarPart.tail:
        p.color = rear ?? const Color(Tokens.colorCarTail);
        canvas.drawRect(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      case CarPart.wheel:
        // The front wheel steers about its centre.
        p.color = const Color(Tokens.colorCarTyre);
        final cx = (r.x0 + r.x1) / 2, cy = (r.y0 + r.y1) / 2;
        final w = r.x1 - r.x0, h = r.y1 - r.y0;
        canvas.save();
        canvas.translate(cx, cy);
        if (cx > 0) canvas.rotate(wheelAngle);
        if (wheelArt != null) {
          drawImageOnCar(canvas, wheelArt, -w / 2, -h / 2, w / 2, h / 2, wheelTint!, mirror: cy > 0);
          canvas.restore();
          continue;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h / 2)),
          p,
        );
        // Micro vehicles get no rims (as client W).
        final rim = micro ? null : lk?.rim;
        if (rim != null) {
          p.color = Color(rim);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: w * 0.5, height: h * 0.5),
              Radius.circular(h / 4),
            ),
            p,
          );
        }
        canvas.restore();
      case CarPart.rider:
        p.color = const Color(Tokens.colorCarCabin);
        canvas.drawOval(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      case CarPart.spare:
        p.color = Color(r.color ?? Tokens.colorCarTyre);
        canvas.drawOval(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      case CarPart.shadow || CarPart.stripe || CarPart.detail:
        p.color = Color(r.color ?? Tokens.colorCarStripe);
        canvas.drawRect(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
    }
  }
  if (artPending) artDecal();
  canvas.restore();
}

final _decalPaint = Paint()
  ..filterQuality = FilterQuality.medium
  ..colorFilter = const ColorFilter.mode(Color(Tokens.colorGarageDecal), BlendMode.srcIn);

/// A paint multiplying a white glyph by [c] (garage wheel tint).
Paint _tinted(Color c) => Paint()
  ..filterQuality = FilterQuality.medium
  ..colorFilter = ColorFilter.mode(c, BlendMode.modulate);

/// The body parts of [shape] as one clip path (rounded like the drawn body).
Path _bodyClip(List<CarRect> shape, double hw) {
  final clip = Path();
  for (final b in shape) {
    if (b.part != CarPart.body) continue;
    clip.addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1), Radius.circular(hw * 0.45)));
  }
  return clip;
}

/// Draws [img] (nose up, image left = car left) stretched over the car-space rectangle
/// x0…x1 (along, x forward) × y0…y1 (across, y left) with [paint]; [mirror] flips it left/right
/// (the wheels on the car's left side).
void drawImageOnCar(
  Canvas c,
  Image img,
  double x0,
  double y0,
  double x1,
  double y1,
  Paint paint, {
  bool mirror = false,
}) {
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  // Image px (u right, v down) → car: x = x1 − v·len/ih, y = y1 − u·wid/iw (mirrored: y0 + u·wid/iw).
  final len = x1 - x0, wid = y1 - y0;
  c.save();
  c.transform(
    Float64List.fromList([
      0, mirror ? wid / iw : -wid / iw, 0, 0, //
      -len / ih, 0, 0, 0,
      0, 0, 1, 0,
      x1, mirror ? y0 : y1, 0, 1,
    ]),
  );
  c.drawImage(img, Offset.zero, paint);
  c.restore();
}

/// Adds the sprite of a catalog car at (x, y, [heading]) to [b]: the wheels at [carWheels] (plus
/// the trike's and the rickshaw's front wheel), the body tinted with [paint] and the decal clipped
/// to the paint mask, the lights (`lights.png` at night whole, by day its rear half when braking;
/// without it the code's head and tail lights as before).
void _addSprite(
  CarSpriteBatch b,
  CarSprite s,
  CarSpec spec,
  List<CarRect> shape,
  double x,
  double y,
  double heading,
  double hl,
  double hw,
  double axle, {
  required Color paint,
  required CarLook? look,
  required double wheelAngle,
  required bool night,
  required Color? rear,
}) {
  // Metres per sprite px: w ÷ 32 × car_scale, car_scale = hl / (length_m / 2).
  final k = hl / (spec.lengthM / 2) / carSpritePxPerM;
  if (s.wheels != null) {
    final rim = look?.rim;
    // A garage wheel sprite (specs/art.md v3 "Kola") replaces wheel.png at its size, rim-tinted.
    final garage = carSprites.wheelFor(s, look?.wheels ?? 0);
    final tint = rim == null || (garage == null && rim == Tokens.colorGarageWheels.first) ? null : Color(rim);
    final kind = drawKind(spec.class_, spec.lengthM);
    final wheels = [
      ...carWheels(spec.class_, hl, hw, axle, lengthM: spec.lengthM),
      if (kind == 'trike' || kind == 'rickshaw') (hl * frontWheelX, 0.0),
    ];
    for (final (fx, sy) in wheels) {
      b.addWheel(s, x, y, heading, fx, sy, fx > 0 ? wheelAngle : 0, k, tint, garage: garage);
    }
  }
  final decal = look?.decal ?? 0;
  final body = carSprites.body(
    s,
    paint.toARGB32(),
    decal: decal,
    mPerPx: k,
    // The decal sprite stretched over the body canvas (specs/art.md v3), else the procedural one.
    decalImage: decal == 0 ? null : carSprites.decalArt(decal),
    paintDecal: decal == 0
        ? null
        : (c) => paintCarDecal(c, decal, bodyBounds(shape), [
            for (final q in shape)
              if (q.part == CarPart.body) q,
          ], hw),
  );
  b.addBody(body, x, y, heading, k);
  final lights = s.lights;
  if (lights != null) {
    final braking = rear == const Color(Tokens.colorCarBrake);
    if (night || braking) b.addLights(lights, x, y, heading, k, rearOnly: !night);
  } else {
    b.over((c) {
      final p = Paint();
      c.save();
      c.translate(x, y);
      c.rotate(heading);
      for (final r in shape) {
        if (r.part == CarPart.head) {
          p.color = night ? const Color(Tokens.colorCarHeadlightNight) : const Color(Tokens.colorCarHeadlightDay);
        } else if (r.part == CarPart.tail) {
          p.color = rear ?? const Color(Tokens.colorCarTail);
        } else {
          continue;
        }
        c.drawRect(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      }
      c.restore();
    });
  }
}

/// The outline the looks fit (specs/garage.md: underglow, decal): the bounds of all body parts
/// (the trike's narrow nose, the rickshaw's frame), for micro its deck (the first body part).
CarRect bodyBounds(List<CarRect> shape, {bool micro = false}) {
  final bodies = shape.where((r) => r.part == CarPart.body);
  if (micro) return bodies.first;
  return bodies
      .skip(1)
      .fold(
        bodies.first,
        (a, r) => CarRect(
          CarPart.body,
          math.min(a.x0, r.x0),
          math.min(a.y0, r.y0),
          math.max(a.x1, r.x1),
          math.max(a.y1, r.y1),
        ),
      );
}

/// Procedural decal polygons (specs/garage.md v2 "Kreslení") in car space laid out on [body] (the
/// body bounds): 1 two lengthwise stripes at ±0.22 hw over the whole car, 2 three flames from the
/// nose back to 0.35 hl, 3 a band of checker squares along both sides, 4 three diamonds on the long
/// axis (centres +0.55, 0, −0.55 hl, diagonals 0.5 hw across × 0.25 hl along); 5 lightning and
/// 6 waves as the stripes, 7 camo and 8 halftone as the checker (as client W). The fallback when the
/// decal has no sprite (`garage/decals/<id>.png`).
List<List<Offset>> decalPolys(int decal, CarRect body) {
  final hl = body.x1, w = body.y1 - body.y0;
  final out = <List<Offset>>[];
  List<Offset> rect(double x0, double y0, double x1, double y1) => [
    Offset(x0, y0),
    Offset(x1, y0),
    Offset(x1, y1),
    Offset(x0, y1),
  ];
  switch (decal) {
    case 1 || 5 || 6:
      final half = w * 0.04;
      for (final c in [0.22 * w / 2, -0.22 * w / 2]) {
        out.add(rect(body.x0, c - half, body.x1, c + half));
      }
    case 2:
      // Three flame tongues side by side, the middle one reaching furthest back.
      final tip = 0.35 * hl;
      final bands = [(-0.42, -0.12, 0.12), (-0.15, 0.15, 0.0), (0.12, 0.42, 0.12)];
      for (final (a, b, back) in bands) {
        final y0 = body.y0 + (a + 0.5) * w, y1 = body.y0 + (b + 0.5) * w;
        final x = tip + back * hl;
        out.add([Offset(body.x1, y0), Offset(body.x1, y1), Offset(x, (y0 + y1) / 2)]);
      }
    case 3 || 7 || 8:
      final sq = w * 0.1;
      final len = body.x1 - body.x0;
      final n = (len * 0.7 / sq).floor();
      final x0 = body.x0 + (len - n * sq) / 2;
      for (var i = 0; i < n; i++) {
        for (var row = 0; row < 2; row++) {
          if ((i + row).isOdd) continue;
          final x = x0 + i * sq;
          final inner = w / 2 - sq * (row + 1) - w * 0.03;
          out
            ..add(rect(x, inner, x + sq, inner + sq))
            ..add(rect(x, -inner - sq, x + sq, -inner));
        }
      }
    case 4:
      final bhl = (body.x1 - body.x0) / 2, bhw = w / 2;
      final cx = (body.x0 + body.x1) / 2, cy = (body.y0 + body.y1) / 2;
      final dx = bhl * 0.125, dy = bhw * 0.25;
      for (final k in [0.55, 0.0, -0.55]) {
        final x = cx + k * bhl;
        out.add([Offset(x + dx, cy), Offset(x, cy + dy), Offset(x - dx, cy), Offset(x, cy - dy)]);
      }
  }
  return out;
}

/// Procedural decal [decal] in `color.garage.decal` ([decalPolys] on [body], the body bounds),
/// clipped to the [bodies].
void paintCarDecal(Canvas canvas, int decal, CarRect body, List<CarRect> bodies, double hw) {
  final p = Paint()..color = const Color(Tokens.colorGarageDecal);
  canvas.save();
  final clip = Path();
  for (final b in bodies) {
    clip.addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1), Radius.circular(hw * 0.45)));
  }
  canvas.clipPath(clip);
  for (final poly in decalPolys(decal, body)) {
    canvas.drawPath(Path()..addPolygon(poly, true), p);
  }
  canvas.restore();
}

/// Skid marks as thin dark quads; [segs] holds x0, y0, x1, y1 per segment.
void paintSkids(Canvas canvas, List<double> segs, double width) {
  final p = Paint()
    ..color = const Color(Tokens.colorCarSkid)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final n = segs.length ~/ 4;
  if (n == 0) return;
  final pts = <Offset>[];
  for (var i = 0; i < n; i++) {
    final x0 = segs[4 * i], y0 = segs[4 * i + 1], x1 = segs[4 * i + 2], y1 = segs[4 * i + 3];
    if ((x1 - x0).abs() + (y1 - y0).abs() > 30) continue; // teleports
    pts
      ..add(Offset(x0, y0))
      ..add(Offset(x1, y1));
  }
  canvas.drawPoints(PointMode.lines, pts, p);
}
