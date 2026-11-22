import 'package:shared_gen/shared_gen.dart';

import 'passport.dart';

/// A landmark as the passport needs it (label anchor in dm, as in landmarks.pb).
typedef PassportLandmarkIn = ({String id, String name, int x, int y, double heightM, bool hero});

/// The parts of a citypack the passport needs (plain data, so tests need no pack).
class PassportCity {
  const PassportCity({required this.landmarks, required this.districts, required this.spotMinigames});
  final List<PassportLandmarkIn> landmarks;

  /// District names in pack order (duplicates allowed).
  final List<String> districts;

  /// Minigame ids of spots in spot order ('' = none).
  final List<String> spotMinigames;
}

class PassportLandmark {
  const PassportLandmark(this.id, this.name, this.x, this.y, this.heightM);
  final String id;
  final String name;

  /// Label anchor in metres.
  final double x, y;
  final double heightM;
}

MessageKey? _key(String k) {
  for (final m in MessageKey.values) {
    if (m.key == k) return m;
  }
  return null;
}

MessageKey? postcardTitleKey(String id) => _key('lm_${id}_title');
MessageKey? postcardTextKey(String id) => _key('lm_${id}_text');
bool hasPostcard(String id) => postcardTitleKey(id) != null;

/// A new stamp; [landmark] for landmarks, [name] (display name) for districts.
class StampEvent {
  const StampEvent(this.kind, this.id, {this.landmark, this.name});
  final String kind;
  final String id;
  final PassportLandmark? landmark;
  final String? name;
  @override
  String toString() => stampId(kind, id);
}

/// Passport state for one city while driving (specs/passport.md "Objevování za jízdy").
/// The save feature reads [stamps] and passes them back in as `saved`.
class PassportTracker {
  PassportTracker(PassportCity city, this.tuning, [List<String> saved = const []]) {
    landmarks = [
      for (final l in city.landmarks)
        if (l.hero && hasPostcard(l.id)) PassportLandmark(l.id, l.name, l.x / 10, l.y / 10, l.heightM),
    ];
    for (final n in city.districts) {
      final id = districtId(n);
      if (id.isNotEmpty) districtNames.putIfAbsent(id, () => n);
    }
    state = rules.init({
      'landmarks': [for (final l in landmarks) l.id],
      'districts': [...districtNames.keys],
      'minigames': [
        for (final m in city.spotMinigames)
          if (m.isNotEmpty) m,
      ],
      'photos': <String>[],
      'weights': tuning.weights,
      'starsForStamp': tuning.starsForStamp,
      'stamps': saved,
    }, 0);
  }

  final TuningPassport tuning;
  final rules = PassportRules();
  late final List<PassportLandmark> landmarks;

  /// District id → first display name.
  final districtNames = <String, String>{};
  late PassportState state;
  final _listeners = <void Function(StampEvent)>[];

  /// Save.stamps out.
  List<String> get stamps => [...state.stamps];

  /// Loads saved stamps (specs/save.md); unknown ones are dropped by the rules.
  void restore(List<String> stamps) {
    final c = state.catalog;
    state = rules.init({
      'landmarks': c['landmark']!,
      'districts': c['district']!,
      'minigames': c['minigame']!,
      'photos': c['photo']!,
      'weights': tuning.weights,
      'starsForStamp': tuning.starsForStamp,
      'stamps': stamps,
    }, 0);
  }
  PassportResult get result => rules.result(state);
  bool has(String kind, String id) => state.stamps.contains(stampId(kind, id));
  void onStamp(void Function(StampEvent) f) => _listeners.add(f);

  /// Called ~10× a second with the car position (m) and the district name under it.
  List<StampEvent> update(double x, double y, String? district) {
    final out = <StampEvent>[];
    final r2 = tuning.discoverRadiusM * tuning.discoverRadiusM;
    for (final l in landmarks) {
      if (has('landmark', l.id) || (l.x - x) * (l.x - x) + (l.y - y) * (l.y - y) > r2) continue;
      if (_visit('landmark', l.id)) out.add(StampEvent('landmark', l.id, landmark: l));
      break;
    }
    if (district != null) {
      final id = districtId(district);
      if (state.catalog['district']!.contains(id) && _visit('district', id)) {
        out.add(StampEvent('district', id, name: districtNames[id] ?? district));
      }
    }
    for (final e in out) {
      for (final f in _listeners) {
        f(e);
      }
    }
    return out;
  }

  /// A finished minigame (MinigameResult.stars); stamps at passport.stars_for_stamp.
  bool minigame(String id, int stars) {
    if (!state.catalog['minigame']!.contains(id)) return false;
    final ok = _visit('minigame', id, stars);
    if (ok) {
      for (final f in _listeners) {
        f(StampEvent('minigame', id));
      }
    }
    return ok;
  }

  bool _visit(String kind, String id, [int? stars]) {
    state = rules.apply(state, PassportAction(kind, id, stars: stars));
    return state.last.isNotEmpty;
  }
}
