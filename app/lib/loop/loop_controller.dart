import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:game_loop/game_loop.dart';
import 'package:mg_api/mg_api.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';
import 'package:world_engine/world_engine.dart' show Spot;

import '../game/metropole_game.dart';
import '../minigames/registry.dart';
import '../phone/phone_controller.dart';
import 'save_store.dart';

/// A minigame the layer should mount now (specs/loop.md "Kontext minihry").
class LoopRequest {
  const LoopRequest({
    required this.spot,
    required this.id,
    required this.game,
    required this.ctx,
    required this.env,
    required this.driveDm,
  });
  final String spot;
  final MinigameId id;
  final Minigame game;
  final MinigameContext ctx;
  final MinigameEnv env;
  final int driveDm;
}

typedef LoopSettings = ({String scheme, bool night});

/// Loop glue of client F (specs/loop.md): loads the save, wires arrival → minigame → result → save.
/// The UI ([LoopLayer]) mounts [request] as a route and shows [outcome] over the paused world.
class LoopController extends ChangeNotifier {
  LoopController(
    this.game,
    this.phone, {
    required this.store,
    required this.npc,
    required this.settingsGet,
    required this.settingsSet,
    Object? saved,
  }) {
    cfg = SaveConfig.fromTuning(tuning, game.city.id, CarId.values.map((c) => c.id));
    book = LoopBook(
      tuning,
      LoopPorts(getCash: () => game.fleet.state.cash, setCash: game.fleet.setCash, stamp: game.passport.minigame),
    );
    _spots = {for (final s in game.city.spots.items) s.id: s};
    _loopSpots = [for (final s in game.city.spots.items) LoopSpot(s.id, s.minigame, s.parkX / 10, s.parkY / 10)];
    phone.discovered = () => {
      for (final s in game.passport.stamps)
        if (s.startsWith('landmark:')) s.substring(9),
    };
    restore(normalizeSave(cfg, saved));
    phone.onArrived.add(_arrived);
    game.fleet.onCarChanged.add((_) => save());
    game.fleet.onBought.add((_, _) => save());
    game.hud.addListener(_tick);
    _life = AppLifecycleListener(onPause: save, onInactive: save, onHide: save);
  }

  final MetropoleGame game;
  final PhoneController phone;
  final SaveStore store;
  final DialogueSession? npc;
  final LoopSettings Function() settingsGet;
  final void Function(LoopSettings) settingsSet;
  late final SaveConfig cfg;
  late final LoopBook book;
  late final Map<String, Spot> _spots;
  late final List<LoopSpot> _loopSpots;
  late final AppLifecycleListener _life;
  final _random = math.Random();
  ({Map<String, int> vibe, List<String> contacts, List<String> recent}) _savedNpc = (
    vibe: const {},
    contacts: const [],
    recent: const [],
  );

  /// UI language ('cs', 'en'); the layer keeps it current.
  String locale = 'en';

  final request = ValueNotifier<LoopRequest?>(null);
  final outcome = ValueNotifier<LoopOutcome?>(null);
  final playSpot = ValueNotifier<LoopSpot?>(null);

  /// Minigame id of the "coming soon" toast, or null.
  final soon = ValueNotifier<String?>(null);
  Timer? _soonTimer;
  double _holdS = 0;
  bool _resetting = false;

  Tuning get tuning => game.tuning;

  /// True while a minigame or the result card is up: the world is paused.
  bool get busy => request.value != null || outcome.value != null;

  // ---------- save
  Map<String, Object?> snapshot() {
    final cs = game.fleet.state;
    final n = npc;
    final s = settingsGet();
    return composeSave(
      cfg,
      SaveParts(
        cash: cs.cash,
        cars: cs.owned,
        car: cs.stolen && cs.owned.isNotEmpty ? cs.owned.first : cs.driving,
        stamps: game.passport.stamps,
        best: book.best,
        plays: book.plays,
        feed: phone.feedSave(),
        npc: n == null
            ? _savedNpc
            : (vibe: {...n.state.vibe}, contacts: [...n.state.contacts], recent: [...n.state.recent]),
        settings: (scheme: s.scheme, night: s.night),
      ),
    );
  }

  void restore(Map<String, Object?> json) {
    final s = saveOf(json);
    game.fleet.restore(cash: s.cash, owned: s.cars, driving: s.car);
    game.passport.restore(s.stamps);
    book.restore({for (final e in s.best.entries) e.key: (stars: e.value.stars, score: e.value.score)}, s.plays);
    phone.feedRestore((prefs: s.feed.prefs, visits: s.feed.visits, districts: s.feed.districts));
    _savedNpc = (vibe: s.npc.vibe, contacts: s.npc.contacts, recent: s.npc.recent);
    final n = npc;
    if (n != null) {
      final known = {for (final c in n.pack.characters) c.id};
      final skits = {for (final k in n.pack.skits) k.id};
      final vibe = {...n.state.vibe};
      for (final e in s.npc.vibe.entries) {
        if (known.contains(e.key)) vibe[e.key] = e.value.clamp(0, tuning.npc.vibeMax);
      }
      final recent = s.npc.recent.where(skits.contains).toList();
      n.state = n.state.copyWith(
        vibe: vibe,
        contacts: s.npc.contacts.where(known.contains).toList(),
        recent: recent.sublist(math.max(0, recent.length - tuning.npc.recentK)),
      );
    }
    settingsSet((scheme: s.settings.scheme, night: s.settings.night));
  }

  Future<void> save() => _resetting ? Future.value() : store.write(game.city.id, snapshot());

  /// Debug "reset save": a fresh save on disk and in the running game.
  Future<void> resetSave() async {
    _resetting = true;
    final fresh = freshSave(cfg);
    restore(fresh);
    await store.write(game.city.id, fresh);
    _resetting = false;
    notifyListeners();
  }

  /// Police fine hook (specs/economy.md).
  void fine(int amount) {
    book.fine(amount);
    save();
    notifyListeners();
  }

  /// Tow fee hook for a wrecked car (specs/economy.md).
  void tow() {
    book.tow();
    save();
    notifyListeners();
  }

  // ---------- loop
  static MessageKey? nameKey(String id) {
    for (final k in MessageKey.values) {
      if (k.key == 'mg_$id') return k;
    }
    return null;
  }

  void _arrived(String spotId) {
    if ((_spots[spotId]?.minigame ?? '').isNotEmpty) start(spotId);
  }

  /// Starts the minigame of a spot (arrival or the context button).
  void start(String spotId) {
    final spot = _spots[spotId];
    if (busy || spot == null || spot.minigame.isEmpty) return;
    final id = MinigameId.values.where((m) => m.id == spot.minigame).firstOrNull;
    final meta = id == null ? null : minigameCatalog[id];
    if (id == null || meta == null) return;
    final mg = minigames[id];
    if (meta.engine == 'drive' || mg == null) {
      _soonTimer?.cancel();
      soon.value = spot.minigame;
      _soonTimer = Timer(Duration(milliseconds: (tuning.nav.toastS * 1000).round()), () => soon.value = null);
      return;
    }
    final a = phone.accepted;
    final card = a != null && a.spot == spotId ? a : null;
    phone.accepted = null;
    phone.close();
    final seed = _random.nextInt(1 << 32);
    final chars = npc?.pack.characters ?? const [];
    final oi = opponentIndex(spotId, chars.length);
    final opponentId = oi >= 0 ? chars[oi].id : null;
    final env = MinigameEnv(tuning: tuning, locale: locale, opponent: opponentFor(npc, opponentId, seed, locale));
    request.value = LoopRequest(
      spot: spotId,
      id: id,
      game: mg,
      ctx: MinigameContext(
        cityId: game.city.id,
        difficulty: loopDifficulty(card?.difficulty, book.plays[spotId] ?? 0, tuning.feed),
        seed: seed,
        locale: locale,
        opponentId: opponentId,
      ),
      env: env,
      driveDm: card?.distDm ?? 0,
    );
    playSpot.value = null;
    game.pauseEngine();
    notifyListeners();
  }

  /// The minigame's onFinish: applies the loop result and saves.
  void finish(MinigameResult r) {
    final q = request.value;
    if (q == null) return;
    outcome.value = book.finish(
      spot: q.spot,
      minigame: q.id.id,
      engine: minigameCatalog[q.id]!.engine,
      result: r,
      driveDm: q.driveDm,
      hasStamp: (m) => game.passport.has('minigame', m),
    );
    request.value = null;
    save();
    notifyListeners();
  }

  /// Result card closed: back to driving, optionally with the phone's Feed.
  void closeResult({bool feed = false}) {
    outcome.value = null;
    game.resumeEngine();
    if (feed) phone.open(PhoneAppId.feed);
    notifyListeners();
  }

  /// HUD tick (~10×/s): the "Play" context button (specs/loop.md "Bez trasy").
  void _tick() {
    const dt = 0.1;
    final c = game.drive.car;
    LoopSpot? s;
    if (!busy && !phone.isOpen && !phone.nav.active) {
      final now = spotInReach(_loopSpots, c.x, c.y, c.speed, c.layer, tuning.loop);
      final prev = playSpot.value;
      if (now != null) {
        s = now;
        _holdS = tuning.loop.actionHoldS;
      } else if (prev != null && _holdS > 0) {
        _holdS -= dt;
        final d2 = (prev.x - c.x) * (prev.x - c.x) + (prev.y - c.y) * (prev.y - c.y);
        if (_holdS > 0 && d2 <= tuning.loop.spotRadiusM * tuning.loop.spotRadiusM) s = prev;
      }
    }
    if (s?.id != playSpot.value?.id) playSpot.value = s;
  }

  @override
  void dispose() {
    game.hud.removeListener(_tick);
    phone.onArrived.remove(_arrived);
    _life.dispose();
    _soonTimer?.cancel();
    request.dispose();
    outcome.dispose();
    playSpot.dispose();
    soon.dispose();
    super.dispose();
  }
}
