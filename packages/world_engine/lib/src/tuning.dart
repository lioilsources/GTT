import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

/// Live-editable values from content/tuning.yaml (METROPOLE_PLAN 5.1).
///
/// The debug panel mutates fields and calls [changed]; listeners pick the new values up.
class Tuning extends ChangeNotifier {
  double carScale = 2.5;
  double laneWidthM = 8.0;
  double sidewalkWidthM = 5.0;
  double viewWidthSlow = 50;
  double viewWidthFast = 85;
  double anchorX = 0.5;
  double anchorY = 0.72;
  double extrusionK = 0.004;
  double extrusionKnee = 50;
  double extrusionExp = 0.85;
  double extrusionMaxScale = 2.2;
  int chunkM = 256;
  double cruiseMps = 25;
  double topMps = 40;

  Tuning();

  factory Tuning.fromYaml(String src) {
    final y = loadYaml(src) as YamlMap;
    double d(Object? v, double def) => v is num ? v.toDouble() : def;
    final t = Tuning();
    t.carScale = d(y['car_scale'], t.carScale);
    t.laneWidthM = d(y['lane_width_m'], t.laneWidthM);
    t.sidewalkWidthM = d(y['sidewalk_width_m'], t.sidewalkWidthM);
    final vw = y['view_width_m'];
    if (vw is YamlMap) {
      t.viewWidthSlow = d(vw['slow'], t.viewWidthSlow);
      t.viewWidthFast = d(vw['fast'], t.viewWidthFast);
    }
    final a = y['car_anchor'];
    if (a is YamlMap) {
      t.anchorX = d(a['x'], t.anchorX);
      t.anchorY = d(a['y'], t.anchorY);
    }
    final e = y['extrusion'];
    if (e is YamlMap) {
      t.extrusionK = d(e['k'], t.extrusionK);
      t.extrusionKnee = d(e['knee_m'], t.extrusionKnee);
      t.extrusionExp = d(e['exp'], t.extrusionExp);
      t.extrusionMaxScale = d(e['max_scale'], t.extrusionMaxScale);
    }
    t.chunkM = (y['chunk_m'] as num?)?.toInt() ?? t.chunkM;
    final s = y['speed_mps'];
    if (s is YamlMap) {
      t.cruiseMps = d(s['cruise'], t.cruiseMps);
      t.topMps = d(s['top_default'], t.topMps);
    }
    return t;
  }

  void changed() => notifyListeners();

  /// Serialises back to the tuning.yaml format so dogfooded values can be pasted into the repo.
  String toYaml() {
    String f(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 1 : 4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '.0');
    return '''
car_scale: ${f(carScale)}
lane_width_m: ${f(laneWidthM)}
sidewalk_width_m: ${f(sidewalkWidthM)}
view_width_m: {slow: ${f(viewWidthSlow)}, fast: ${f(viewWidthFast)}}
car_anchor: {x: ${f(anchorX)}, y: ${f(anchorY)}}
extrusion: {k: ${f(extrusionK)}, knee_m: ${f(extrusionKnee)}, exp: ${f(extrusionExp)}, max_scale: ${f(extrusionMaxScale)}}
chunk_m: $chunkM
speed_mps: {cruise: ${f(cruiseMps)}, top_default: ${f(topMps)}}
''';
  }
}
