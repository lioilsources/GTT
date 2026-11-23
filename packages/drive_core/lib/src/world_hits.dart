import 'drive_world.dart';

/// Shortest gap between two `hit` actions of a world minigame (specs drift.md / sprint.md "Náraz").
const hitGapMs = 500;

/// Crashes of the player's car for world minigames (Drift, Sprint): a building wall (speed along the
/// contact normal), a bridge or tunnel rail (speed into the rail) or a traffic car (its impact speed),
/// each at least [minMps]. [take] once per frame: true when a crash happened since the last call and
/// the previous reported one is at least [hitGapMs] of session time ago. Port of
/// web/src/minigames/worldHits.ts.
class WorldHits {
  WorldHits(this.drive, this.minMps) {
    drive
      ..onWall = _bump
      ..onRail = _bump;
    _offTraffic = drive.traffic?.onHit((_, impact) => _bump(impact));
  }

  final DriveWorld drive;
  final double minMps;
  bool _pending = false;
  int? _lastMs;
  void Function()? _offTraffic;

  void _bump(double mps) {
    if (mps >= minMps) _pending = true;
  }

  /// Forgets crashes so far (session start).
  void reset() {
    _pending = false;
    _lastMs = null;
  }

  bool take(int atMs) {
    if (!_pending) return false;
    _pending = false;
    final last = _lastMs;
    if (last != null && atMs - last < hitGapMs) return false;
    _lastMs = atMs;
    return true;
  }

  void dispose() {
    if (drive.onWall == _bump) drive.onWall = null;
    if (drive.onRail == _bump) drive.onRail = null;
    _offTraffic?.call();
    _offTraffic = null;
  }
}
