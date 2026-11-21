import 'dart:math' as math;

import 'package:yaml/yaml.dart';

/// Reads a YAML map strictly: every key must be present, there are no fallback numbers in code.
class _Reader {
  _Reader(this.map, this.path);
  final YamlMap map;
  final String path;

  Object _get(String key) {
    final v = map[key];
    if (v == null) throw FormatException('tuning.yaml: missing $path$key');
    return v;
  }

  double d(String key) {
    final v = _get(key);
    if (v is! num) throw FormatException('tuning.yaml: $path$key must be a number');
    return v.toDouble();
  }

  int i(String key) {
    final v = _get(key);
    if (v is! int) throw FormatException('tuning.yaml: $path$key must be an integer');
    return v;
  }

  _Reader sub(String key) {
    final v = _get(key);
    if (v is! YamlMap) throw FormatException('tuning.yaml: $path$key must be a map');
    return _Reader(v, '$path$key.');
  }

  Map<String, double> numMap(String key) {
    final r = sub(key);
    return {for (final k in r.map.keys.cast<String>()) k: r.d(k)};
  }
}

class StreamingTuning {
  StreamingTuning._(_Reader r)
      : ahead = r.i('ahead'),
        behind = r.i('behind'),
        side = r.i('side'),
        keep = r.i('keep'),
        maxInFlight = r.i('max_in_flight'),
        retryS = r.d('retry_s');
  int ahead, behind, side, keep, maxInFlight;
  double retryS;
}

class CameraTuning {
  CameraTuning._(_Reader r)
      : headingFollowRate = r.d('heading_follow_rate'),
        zoomFollowRate = r.d('zoom_follow_rate');
  double headingFollowRate, zoomFollowRate;
}

class DriveTuning {
  DriveTuning._(_Reader r)
      : stepHz = r.i('step_hz'),
        substeps = r.i('substeps'),
        axleOffset = r.d('axle_offset'),
        steerLock = r.d('steer_lock_rad'),
        steerLockDrop = r.d('steer_lock_drop_rad'),
        countersteerGain = r.d('countersteer_gain'),
        countersteerMinSlip = r.d('countersteer_min_slip_rad'),
        countersteerMinMps = r.d('countersteer_min_mps'),
        countersteerMaxInput = r.d('countersteer_max_input'),
        brakeMinMps = r.d('brake_min_mps'),
        reverseMaxMps = r.d('reverse_max_mps'),
        reversePower = r.d('reverse_power'),
        engineBrake = r.d('engine_brake_mps2'),
        overspeedMps = r.d('overspeed_mps'),
        dragLinear = r.d('drag_linear'),
        dragQuadratic = r.d('drag_quadratic'),
        handbrakeDecel = r.d('handbrake_decel_mps2'),
        handbrakeYaw = r.d('handbrake_yaw'),
        handbrakeYawRefMps = r.d('handbrake_yaw_ref_mps'),
        handbrakeYawMax = r.d('handbrake_yaw_max'),
        handbrakeMinMps = r.d('handbrake_min_mps'),
        angularDamping = r.d('angular_damping'),
        stopSpinDamping = r.d('stop_spin_damping'),
        stopSpeedMps = r.d('stop_speed_mps'),
        bodyRound = r.d('body_round_m'),
        carFriction = r.d('car_friction'),
        carRestitution = r.d('car_restitution'),
        buildingFriction = r.d('building_friction'),
        buildingRestitution = r.d('building_restitution');
  int stepHz, substeps;
  double axleOffset, steerLock, steerLockDrop;
  double countersteerGain, countersteerMinSlip, countersteerMinMps, countersteerMaxInput;
  double brakeMinMps, reverseMaxMps, reversePower, engineBrake, overspeedMps;
  double dragLinear, dragQuadratic;
  double handbrakeDecel, handbrakeYaw, handbrakeYawRefMps, handbrakeYawMax, handbrakeMinMps;
  double angularDamping, stopSpinDamping, stopSpeedMps;
  double bodyRound, carFriction, carRestitution, buildingFriction, buildingRestitution;

  double get step => 1 / stepHz;
}

class LayerTuning {
  LayerTuning._(_Reader r)
      : searchM = r.d('search_m'),
        switchMarginM = r.d('switch_margin_m'),
        railMargin = r.d('rail_margin'),
        railBounce = r.d('rail_bounce'),
        spawnSearchM = r.d('spawn_search_m');
  double searchM, switchMarginM, railMargin, railBounce, spawnSearchM;
}

class ControlsTuning {
  ControlsTuning._(_Reader r)
      : aFullSteerWidth = r.d('a_full_steer_width'),
        aDeadZoneHeight = r.d('a_dead_zone_height'),
        aFullBrakeHeight = r.d('a_full_brake_height'),
        cMaxWheel = r.d('c_max_wheel_rad');
  double aFullSteerWidth, aDeadZoneHeight, aFullBrakeHeight, cMaxWheel;
}

class PropsTuning {
  PropsTuning._(_Reader r)
      : spacingM = r.d('spacing_m'),
        spacingJitterM = r.d('spacing_jitter_m'),
        skipChance = r.d('skip_chance'),
        firstM = r.d('first_m'),
        clearIntersectionM = r.d('clear_intersection_m'),
        mix = r.numMap('mix'),
        radiusM = r.numMap('radius_m'),
        knockMinMps = r.d('knock_min_mps'),
        knockSlowdown = r.d('knock_slowdown'),
        knockCarry = r.d('knock_carry'),
        knockSide = r.d('knock_side'),
        knockSpin = r.d('knock_spin'),
        knockSpinPerMps = r.d('knock_spin_per_mps'),
        flyS = r.d('fly_s'),
        flyDamping = r.d('fly_damping'),
        respawnS = r.d('respawn_s');
  double spacingM, spacingJitterM, skipChance, firstM, clearIntersectionM;
  final Map<String, double> mix;
  final Map<String, double> radiusM;
  double knockMinMps, knockSlowdown, knockCarry, knockSide, knockSpin, knockSpinPerMps;
  double flyS, flyDamping, respawnS;
}

class SkidTuning {
  SkidTuning._(_Reader r)
      : minSlipMps = r.d('min_slip_mps'),
        brakeMinMps = r.d('brake_min_mps'),
        maxSegments = r.i('max_segments');
  double minSlipMps, brakeMinMps;
  int maxSegments;
}

class HudTuning {
  HudTuning._(_Reader r)
      : streetLabelsBelowMps = r.d('street_labels_below_mps'),
        streetLabelRadiusM = r.d('street_label_radius_m'),
        streetLabelsMax = r.i('street_labels_max'),
        borderNoticeM = r.d('border_notice_m');
  double streetLabelsBelowMps, streetLabelRadiusM, borderNoticeM;
  int streetLabelsMax;
}

/// Game numbers from content/tuning.yaml (METROPOLE_PLAN 5.1). Pure Dart, no UI.
///
/// Parsing is strict: a missing key is an error, so the YAML stays the only source.
/// The debug panel mutates fields and calls [changed].
class Tuning {
  Tuning._(_Reader r)
      : carScale = r.d('car_scale'),
        laneWidthM = r.d('lane_width_m'),
        sidewalkWidthM = r.d('sidewalk_width_m'),
        viewWidthSlow = r.sub('view_width_m').d('slow'),
        viewWidthFast = r.sub('view_width_m').d('fast'),
        anchorX = r.sub('car_anchor').d('x'),
        anchorY = r.sub('car_anchor').d('y'),
        extrusionK = r.sub('extrusion').d('k'),
        extrusionKnee = r.sub('extrusion').d('knee_m'),
        extrusionExp = r.sub('extrusion').d('exp'),
        extrusionMaxScale = r.sub('extrusion').d('max_scale'),
        chunkM = r.i('chunk_m'),
        cruiseMps = r.sub('speed_mps').d('cruise'),
        topMps = r.sub('speed_mps').d('top_default'),
        streaming = StreamingTuning._(r.sub('streaming')),
        camera = CameraTuning._(r.sub('camera')),
        drive = DriveTuning._(r.sub('drive')),
        layers = LayerTuning._(r.sub('layers')),
        controls = ControlsTuning._(r.sub('controls')),
        props = PropsTuning._(r.sub('props')),
        skids = SkidTuning._(r.sub('skids')),
        hud = HudTuning._(r.sub('hud'));

  factory Tuning.fromYaml(String src) {
    final y = loadYaml(src);
    if (y is! YamlMap) throw const FormatException('tuning.yaml: expected a map');
    return Tuning._(_Reader(y, ''));
  }

  double carScale;
  double laneWidthM;
  double sidewalkWidthM;
  double viewWidthSlow;
  double viewWidthFast;
  double anchorX;
  double anchorY;
  double extrusionK;
  double extrusionKnee;
  double extrusionExp;
  double extrusionMaxScale;
  int chunkM;
  double cruiseMps;
  double topMps;
  final StreamingTuning streaming;
  final CameraTuning camera;
  final DriveTuning drive;
  final LayerTuning layers;
  final ControlsTuning controls;
  final PropsTuning props;
  final SkidTuning skids;
  final HudTuning hud;

  final _listeners = <void Function()>[];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void changed() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// The values the debug panel edits, in tuning.yaml syntax, ready to paste into the repo.
  String panelYaml() {
    String f(double v) => _fmt(v);
    return '''
car_scale: ${f(carScale)}
view_width_m: {slow: ${f(viewWidthSlow)}, fast: ${f(viewWidthFast)}}
car_anchor: {x: ${f(anchorX)}, y: ${f(anchorY)}}
extrusion: {k: ${f(extrusionK)}, knee_m: ${f(extrusionKnee)}, exp: ${f(extrusionExp)}, max_scale: ${f(extrusionMaxScale)}}
speed_mps: {cruise: ${f(cruiseMps)}, top_default: ${f(topMps)}}
''';
  }

  static String _fmt(double v) {
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? '${s}0' : s;
  }
}

/// Roof scale for height [h] (METROPOLE_PLAN 6.2):
/// h_eff = h for h ≤ knee, knee + (h − knee)^exp above; s = min(1 + k·h_eff, max_scale).
double extrusionScale(double h, Tuning t) {
  final he = h <= t.extrusionKnee ? h : t.extrusionKnee + math.pow(h - t.extrusionKnee, t.extrusionExp);
  return math.min(1 + t.extrusionK * he, t.extrusionMaxScale);
}
