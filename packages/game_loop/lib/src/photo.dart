// Photo spots and the Camera (specs/photo.md, version 1): the P0 rules (module `photo`) and the pure
// world helpers (spot list, reach, the framing camera, the frame → world shot conversion). Port of
// web/src/photo/rules.ts and web/src/photo/photo.ts; drawing and the mode itself live in the app.
import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot;
import 'package:shared_gen/shared_gen.dart';

/// A photo spot as the P0 module sees it: `look` in dm and the view radius `subject_dm`.
class PhotoSpot {
  const PhotoSpot({required this.id, required this.x, required this.y, required this.r});

  factory PhotoSpot.fromJson(Map<String, Object?> j) =>
      PhotoSpot(id: j['id'] as String, x: j['x'] as int, y: j['y'] as int, r: j['r'] as int);

  final String id;
  final int x, y, r;

  Map<String, Object?> toJson() => {'id': id, 'x': x, 'y': y, 'r': r};
}

class PhotoConfig {
  const PhotoConfig({required this.spots, required this.loosePct});

  /// Config from tuning and the photo spots of the city.
  factory PhotoConfig.fromTuning(TuningPhoto t, Iterable<PhotoSpot> spots) =>
      PhotoConfig(spots: List.unmodifiable(spots), loosePct: t.loosePct);

  factory PhotoConfig.fromJson(Map<String, Object?> j) => PhotoConfig(
    spots: List.unmodifiable([
      for (final s in (j['spots'] as List).cast<Map>()) PhotoSpot.fromJson(s.cast<String, Object?>()),
    ]),
    loosePct: j['loosePct'] as int,
  );

  /// Photo spots of the city in spots.pb order.
  final List<PhotoSpot> spots;
  final int loosePct;

  Map<String, Object?> toJson() => {
    'spots': [for (final s in spots) s.toJson()],
    'loosePct': loosePct,
  };
}

/// '' (nothing yet), ok, again, cut or loose.
typedef PhotoVerdict = String;

/// The last shot; `spot == ''` after init and load.
typedef PhotoLast = ({String spot, PhotoVerdict verdict});

const PhotoLast noPhotoLast = (spot: '', verdict: '');

class PhotoState {
  const PhotoState({required this.taken, required this.last});

  /// Photographed spots in the order they were taken.
  final List<String> taken;
  final PhotoLast last;

  Map<String, Object?> toJson() => {
    'taken': taken,
    'last': {'spot': last.spot, 'verdict': last.verdict},
  };
}

/// A shot in the P0 module's units: frame centre in world dm, half sides in dm.
typedef PhotoShot = ({int cx, int cy, int hw, int hh});

/// `op` is load ([taken]) or shoot ([spot], [shot]).
class PhotoAction {
  const PhotoAction.load(List<String> this.taken) : op = 'load', spot = null, shot = null;
  const PhotoAction.shoot(String this.spot, PhotoShot this.shot) : op = 'shoot', taken = null;

  final String op;
  final List<String>? taken;
  final String? spot;
  final PhotoShot? shot;

  Map<String, Object?> toJson() => switch (op) {
    'load' => {'by': 'player', 'op': op, 'taken': taken},
    _ => {'by': 'player', 'op': op, 'spot': spot, 'cx': shot!.cx, 'cy': shot!.cy, 'hw': shot!.hw, 'hh': shot!.hh},
  };

  @override
  bool operator ==(Object other) =>
      other is PhotoAction &&
      other.op == op &&
      other.spot == spot &&
      other.shot == shot &&
      _sameList(other.taken, taken);
  @override
  int get hashCode => Object.hash(op, spot, shot, taken == null ? null : Object.hashAll(taken!));
  @override
  String toString() => toJson().toString();
}

bool _sameList(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// JSON number → int like TS Number.isInteger (5.0 counts, 1.5 does not).
int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

/// floor(sqrt(n)) of a non-negative integer, exact.
int isqrt(int n) {
  var r = math.sqrt(n.toDouble()).floor();
  while (r * r > n) {
    r--;
  }
  while ((r + 1) * (r + 1) <= n) {
    r++;
  }
  return r;
}

/// The fit of a frame (spec "Akce" shoot, steps 1–2): 'cut', 'loose' or 'fits' (`again` / `ok` is
/// decided by `taken`).
String frameVerdict(PhotoSpot s, int loosePct, PhotoShot f) {
  final h = math.min(f.hw, f.hh);
  final dx = f.cx - s.x, dy = f.cy - s.y;
  final d = isqrt(dx * dx + dy * dy);
  if (d + s.r > h) return 'cut';
  if (h * 100 > s.r * loosePct) return 'loose';
  return 'fits';
}

class PhotoRules extends MgRules<PhotoState, PhotoAction, Map<String, Object?>> {
  @override
  String get id => 'photo';
  @override
  int get specVersion => 1;

  PhotoConfig? _cfg;
  PhotoConfig get config => _cfg ?? (throw StateError('photo: init first'));

  PhotoState start(PhotoConfig c) {
    _cfg = c;
    return const PhotoState(taken: [], last: noPhotoLast);
  }

  @override
  PhotoState init(Map<String, Object?> config, int seed) => start(PhotoConfig.fromJson(config));

  @override
  List<PhotoAction> legalActions(PhotoState s) => [
    const PhotoAction.load([]),
    for (final p in config.spots) PhotoAction.shoot(p.id, (cx: p.x, cy: p.y, hw: p.r, hh: p.r)),
  ];

  @override
  PhotoState apply(PhotoState state, PhotoAction a) {
    final c = config;
    switch (a.op) {
      case 'load':
        final list = a.taken;
        if (list == null) throw IllegalAction(id, a);
        final known = {for (final p in c.spots) p.id}, seen = <String>{};
        return PhotoState(
          taken: [
            for (final x in list)
              if (known.contains(x) && seen.add(x)) x,
          ],
          last: noPhotoLast,
        );
      case 'shoot':
        final p = c.spots.where((x) => x.id == a.spot).firstOrNull, f = a.shot;
        if (p == null || f == null || f.hw < 1 || f.hh < 1) throw IllegalAction(id, a);
        final fit = frameVerdict(p, c.loosePct, f);
        final taken = [...state.taken];
        final String verdict;
        if (fit != 'fits') {
          verdict = fit;
        } else if (taken.contains(p.id)) {
          verdict = 'again';
        } else {
          verdict = 'ok';
          taken.add(p.id);
        }
        return PhotoState(taken: taken, last: (spot: p.id, verdict: verdict));
      default:
        throw IllegalAction(id, a);
    }
  }

  @override
  PhotoAction aiAction(PhotoState state, int level, Prng ai) => throw UnsupportedError('photo: no opponent');

  @override
  Map<String, Object?>? result(PhotoState state) => null;

  /// Strict JSON: a wrong type (non-integer frame, non-string spot), an unknown op or `by ≠ player`
  /// is illegal.
  @override
  PhotoAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'load':
        final t = j['taken'];
        if (t is! List || t.any((x) => x is! String)) throw IllegalAction(id, j);
        return PhotoAction.load(t.cast<String>());
      case 'shoot':
        final spot = j['spot'], cx = _asInt(j['cx']), cy = _asInt(j['cy']), hw = _asInt(j['hw']), hh = _asInt(j['hh']);
        if (spot is! String || cx == null || cy == null || hw == null || hh == null) throw IllegalAction(id, j);
        return PhotoAction.shoot(spot, (cx: cx, cy: cy, hw: hw, hh: hh));
      default:
        throw IllegalAction(id, j);
    }
  }

  @override
  Map<String, Object?> stateToJson(PhotoState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}

// ---------- in the world (specs/photo.md P1)

/// A photo spot: parking point and look in metres, the view radius in metres and dm.
class PhotoPoint {
  const PhotoPoint({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.heading,
    required this.lookXDm,
    required this.lookYDm,
    required this.subjectDm,
  });

  final String id, name;

  /// Parking point (m) and its heading.
  final double x, y, heading;

  /// look in dm and subject_dm, as the P0 module sees them.
  final int lookXDm, lookYDm, subjectDm;

  double get lookX => lookXDm / 10;
  double get lookY => lookYDm / 10;
  double get subjectM => subjectDm / 10;

  PhotoSpot get spot => PhotoSpot(id: id, x: lookXDm, y: lookYDm, r: subjectDm);
}

/// Photo spots = spots `kind: photo` with a view (subject_dm > 0), in spots.pb order.
List<PhotoPoint> photoSpotsOf(Iterable<Spot> spots) => [
  for (final s in spots)
    if (s.kind == 'photo' && s.subjectDm > 0)
      PhotoPoint(
        id: s.id,
        name: s.name,
        x: s.parkX / 10,
        y: s.parkY / 10,
        heading: s.parkHeading,
        lookXDm: s.lookX,
        lookYDm: s.lookY,
        subjectDm: s.subjectDm,
      ),
];

/// Same conditions as "Hrát" at a spot (specs/loop.md): standing, layer 0, parking point in reach.
bool photoInReach(PhotoPoint p, double x, double y, double speed, int layer, TuningLoop t) =>
    speed <= t.stopSpeedMps &&
    layer == 0 &&
    (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) <= t.spotRadiusM * t.spotRadiusM;

/// The nearest photo spot in reach of the car, or null.
PhotoPoint? photoSpotAt(Iterable<PhotoPoint> points, double x, double y, double speed, int layer, TuningLoop t) {
  PhotoPoint? best;
  var bd = double.infinity;
  for (final p in points) {
    if (!photoInReach(p, x, y, speed, layer, t)) continue;
    final d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y);
    if (d < bd) {
      bd = d;
      best = p;
    }
  }
  return best;
}

/// Why the Camera is not offered (spec "Kdy ne"): a minigame or the Taxi shift, or wanted.
enum PhotoBlock { busy, wanted }

PhotoBlock? photoBlocked({required bool busy, required bool inWorldGame, required int wanted}) {
  if (busy || inWorldGame) return PhotoBlock.busy;
  return wanted > 0 ? PhotoBlock.wanted : null;
}

/// Framing view width (m): max(view_width_m.slow, 2 × subject_m × photo.view_factor).
double photoViewWidth(Tuning t, double subjectM) => math.max(t.viewWidthM.slow, 2 * subjectM * t.photo.viewFactor);

/// The camera as the photo code sees it (CameraRig: x, y at the car anchor, heading up, view width).
typedef RigPose = ({double x, double y, double heading, double viewWidth});

/// Screen pixel → world point (m): the inverse of CameraRig.toScreen for a [w] × [h] screen.
({double x, double y}) screenToWorld(RigPose rig, double sx, double sy, double w, double h, Tuning t) {
  final ppm = w / rig.viewWidth;
  final a = math.pi / 2 - rig.heading;
  final rx = (sx - w * t.carAnchor.x) / ppm;
  final ry = (h * t.carAnchor.y - sy) / ppm;
  return (
    x: rig.x + rx * math.cos(a) + ry * math.sin(a),
    y: rig.y - rx * math.sin(a) + ry * math.cos(a),
  );
}

/// Rig position (the point drawn at the car anchor) that puts world point ([mx], [my]) in the
/// middle of the screen with the given heading and view width.
({double x, double y}) rigForCentre(
  double mx,
  double my,
  double heading,
  double viewWidth,
  double w,
  double h,
  Tuning t,
) {
  // The screen centre in a rig sitting at (mx, my) is a world point; shift by the opposite offset.
  final c = screenToWorld((x: mx, y: my, heading: heading, viewWidth: viewWidth), w / 2, h / 2, w, h, t);
  return (x: 2 * mx - c.x, y: 2 * my - c.y);
}

/// Whole dm of metres: floor(x × 10 + 0.5).
int toDm(double m) => (m * 10 + 0.5).floor();

/// The frame dragged between two opposite corners (screen pixels, screen-aligned) → a shot: the
/// frame centre to a world point, half sides ÷ the camera scale (pixels per metre), whole dm, at
/// least 1.
PhotoShot frameToShot(RigPose rig, double x0, double y0, double x1, double y1, double w, double h, Tuning t) {
  final ppm = w / rig.viewWidth;
  final c = screenToWorld(rig, (x0 + x1) / 2, (y0 + y1) / 2, w, h, t);
  int half(double px) => math.max(1, toDm(px.abs() / 2 / ppm));
  return (cx: toDm(c.x), cy: toDm(c.y), hw: half(x1 - x0), hh: half(y1 - y0));
}

double _smooth(double k) => k * k * (3 - 2 * k);

/// The camera glide of the Camera mode (photo.zoom_s): into the framing pose, or back to the car.
/// Holds no rig; [pose] gives the pose for the current time (heading unchanged).
class PhotoGlide {
  PhotoGlide(this.from, this.to, this.seconds);

  final RigPose from;
  final RigPose Function() to;
  final double seconds;
  double _s = 0;

  void step(double dt) => _s += math.max(0, dt);

  bool get done => _s >= seconds;

  RigPose pose() {
    final k = seconds > 0 ? _smooth(math.min(1, _s / seconds)) : 1.0;
    final b = to(), a = from;
    return (
      x: a.x + (b.x - a.x) * k,
      y: a.y + (b.y - a.y) * k,
      heading: a.heading,
      viewWidth: a.viewWidth + (b.viewWidth - a.viewWidth) * k,
    );
  }
}

/// The photo module of one session: photographed spots, shots.
class PhotoWorld {
  PhotoWorld(this.points, Tuning tuning) : _byId = {for (final p in points) p.id: p} {
    state = rules.start(PhotoConfig.fromTuning(tuning.photo, points.map((p) => p.spot)));
  }

  final List<PhotoPoint> points;
  final rules = PhotoRules();
  late PhotoState state;
  final Map<String, PhotoPoint> _byId;

  /// From Passport stamps: `photo:<id>` → load (unknown ids drop silently).
  void loadStamps(Iterable<String> stamps) => state = rules.apply(
    state,
    PhotoAction.load([
      for (final s in stamps)
        if (s.startsWith('photo:')) s.substring(6),
    ]),
  );

  bool isTaken(String id) => state.taken.contains(id);

  PhotoPoint? point(String id) => _byId[id];

  /// A shot at spot [id]; the verdict, null for an unknown spot.
  PhotoVerdict? shoot(String id, PhotoShot s) {
    if (!_byId.containsKey(id)) return null;
    state = rules.apply(state, PhotoAction.shoot(id, s));
    return state.last.verdict;
  }
}
