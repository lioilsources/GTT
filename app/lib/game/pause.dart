import 'package:flutter/foundation.dart';

/// Overlays that pause the game while open (specs/pause.md "Co hru zastaví"). Short toasts (cash,
/// fine, wanted level, navigation) are deliberately not here: they never pause. Client F has no
/// separate arrival card: arriving at a spot opens the minigame ([minigame]) straight away.
/// [booth] = the offer card of a ringing booth (specs/booths.md).
enum GameOverlay { phone, garage, passport, about, postcard, dialogue, minigame, result, gallery, tuning, bench, booth }

/// The pure rule: the game is paused while at least one overlay is open.
bool paused(Iterable<GameOverlay> overlays) => overlays.isNotEmpty;

/// The one overlay registry of client F: an overlay registers on open and unregisters on close.
/// Counted, so the same kind opened twice (a route over a route) stays paused until both close.
class OverlayRegistry extends ChangeNotifier {
  final Map<GameOverlay, int> _open = {};

  Iterable<GameOverlay> get open => _open.keys;

  bool get isPaused => paused(open);

  bool isOpen(GameOverlay o) => _open.containsKey(o);

  void register(GameOverlay o) {
    _open[o] = (_open[o] ?? 0) + 1;
    if (_open[o] == 1) notifyListeners();
  }

  void unregister(GameOverlay o) {
    final n = _open[o];
    if (n == null) return;
    if (n > 1) {
      _open[o] = n - 1;
      return;
    }
    _open.remove(o);
    notifyListeners();
  }

  /// Registers [o] if [on] and it is not open yet, unregisters it otherwise (one-shot overlays).
  void set(GameOverlay o, bool on) {
    if (on == isOpen(o)) return;
    on ? register(o) : _open.remove(o);
    if (!on) notifyListeners();
  }

  /// Keeps [o] registered until [f] completes (a pushed route or a modal sheet).
  Future<T> hold<T>(GameOverlay o, Future<T> f) {
    register(o);
    return f.whenComplete(() => unregister(o));
  }
}
