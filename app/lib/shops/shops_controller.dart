import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart' show ControlInput;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../game/pause.dart';
import '../loop/loop_controller.dart';
import '../phone/phone_controller.dart';

/// A toast of the shops module: what to say and its number ([n] = percent or beers).
enum ShopToast { snack, souvenir, beer, drunk, sober }

/// Shops and bars of client F (specs/shops.md P1): venue icons and Map dots, the "Koupit" / "Bar"
/// context buttons, the shop and bar cards (pause kind `shop`), cash in and out through the cars
/// state, the snack bonus, beers and the drunk driver, and the Garage shelf. [ShopsLayer] draws the
/// HUD part. Off (no [world], no hooks) when `shops.enabled` / `shops.cities.<city>` is false or the
/// city has no venues; the shelf still shows the saved souvenirs.
class ShopsController extends ChangeNotifier {
  ShopsController(this.game, this.phone, this.loop) {
    shops = shopsOf(game.city.spots.items);
    _byId = {for (final s in shops) s.id: s};
    games = barGames(shops, [for (final m in minigameCatalog.keys) m.id]);
    if (!shopsOn(tuning.shops, game.city.id, shops.length)) return;
    final w = world = ShopWorld(shops, tuning.shops, owned: loop.savedSouvenirs);
    w.onSober.add(() => _toast(ShopToast.sober, 0));
    loop.souvenirs = () => w.owned;
    loop.onSouvenirsRestored = _restored;
    loop.book.snack = w.reward;
    loop.book.shopsFinish = w.finish;
    // A bar with a minigame shows "Bar" in the place of "Hrát" (its game is in the bar card).
    loop.playHidden = (id) => _byId[id]?.isBar ?? false;
    // Priority: Zvednout > Foťák > Bar / Koupit > Hrát > Přesednout (spec "Ve světě").
    _prevLoopYield = loop.yieldTo;
    _prevCarYield = game.carActionYield;
    loop.yieldTo = _yieldLoop;
    game.carActionYield = _yieldCar;
    phone.mapPoints.add(_mapPoints);
    game.hud.addListener(_hud);
    _prevUpdate = game.afterUpdate;
    _prevWorld = game.paintWorld;
    _prevInput = game.inputHook;
    game
      ..afterUpdate = _afterUpdate
      ..paintWorld = _paintWorld
      ..inputHook = _input;
  }

  final MetropoleGame game;
  final PhoneController phone;
  final LoopController loop;
  late final List<Shop> shops;
  late final Map<String, Shop> _byId;

  /// Every distinct playable minigame of the city's bars, in spot order (the bar card).
  late final List<String> games;

  /// Null when the module does not run in this city.
  ShopWorld? world;

  bool Function()? _prevLoopYield, _prevCarYield;
  void Function(double)? _prevUpdate;
  void Function(ui.Canvas)? _prevWorld;
  void Function(ControlInput)? _prevInput;

  Tuning get tuning => game.tuning;

  /// The open shop or bar card (the game is paused while it is up).
  final card = ValueNotifier<Shop?>(null);

  /// True when a skit of the host runs in the open card.
  bool skit = false;

  /// True while the skit is open as the full dialogue over the card.
  bool chat = false;

  /// The venue whose context button shows now (HUD tick), or null.
  final here = ValueNotifier<Shop?>(null);

  /// The toast shown now, or null.
  final toast = ValueNotifier<({ShopToast kind, int n})?>(null);
  double _toastS = 0;

  bool get drunk => world?.drunk ?? false;
  int get beers => world?.beers ?? 0;

  /// The venue in reach of the car (same conditions as "Hrát"), the nearest one; null without.
  Shop? shopHere() {
    final c = game.drive.car, t = tuning.loop;
    Shop? best;
    var bd = double.infinity;
    for (final s in shops) {
      if (!shopInReach(s, c.x, c.y, c.speed, c.layer, t)) continue;
      final d = (s.x - c.x) * (s.x - c.x) + (s.y - c.y) * (s.y - c.y);
      if (d < bd) {
        bd = d;
        best = s;
      }
    }
    return best;
  }

  /// The "Koupit" / "Bar" button: at a venue, nothing else up, no Zvednout / Foťák first, not
  /// during a minigame or a Taxi shift.
  bool canOpen() =>
      world != null &&
      card.value == null &&
      !loop.busy &&
      !loop.inWorldGame &&
      !phone.isOpen &&
      !phone.nav.active &&
      !game.worldPaused &&
      !(_prevLoopYield?.call() ?? false) &&
      shopHere() != null;

  bool _yieldLoop() => (_prevLoopYield?.call() ?? false) || card.value != null || canOpen();
  bool _yieldCar() => (_prevCarYield?.call() ?? false) || card.value != null || canOpen();

  void _restored(List<String> owned) {
    final w = world;
    if (w != null) w.state = w.rules.apply(w.state, ShopsAction.load(owned));
    notifyListeners();
  }

  List<({double x, double y, int color})> _mapPoints() => [
    for (final s in shops) (x: s.x, y: s.y, color: kindColor(s.kind)),
  ];

  static int kindColor(String kind) => switch (kind) {
    'food' => Tokens.colorShopsFood,
    'souvenir' => Tokens.colorShopsSouvenir,
    _ => Tokens.colorShopsBar,
  };

  void _hud() => tick();

  /// HUD tick (~10×/s): the toast and the context button. Public for tests.
  void tick([double dt = 0.1]) {
    if (_toastS > 0 && (_toastS -= dt) <= 0) toast.value = null;
    final s = canOpen() ? shopHere() : null;
    if (s?.id != here.value?.id) here.value = s;
  }

  void _toast(ShopToast kind, int n) {
    toast.value = (kind: kind, n: n);
    _toastS = tuning.nav.toastS;
  }

  void _afterUpdate(double dt) {
    _prevUpdate?.call(dt);
    update(game.worldDt(dt));
  }

  /// One frame: [stepDt] = game dt (0 while paused, so the clock stands). Public for tests.
  void update(double stepDt) {
    final w = world;
    if (w == null) return;
    final was = (w.beers, w.drunk, w.snack);
    w.update(stepDt);
    if (was != (w.beers, w.drunk, w.snack)) notifyListeners();
  }

  /// Drunk: the driving input is ignored and the car brakes to a stop (it never reverses).
  void _input(ControlInput input) {
    _prevInput?.call(input);
    if (!drunk) return;
    final fwd = game.drive.car.forwardSpeed;
    input
      ..reset()
      ..brake = fwd > tuning.drive.brakeMinMps ? 1 : 0
      ..handbrake = true;
  }

  /// Opens the card of [s] (the context button): the phone closes, the game stands, the host's
  /// skit of context `shop` / `bar` starts when one fits.
  void open(Shop s) {
    if (world == null || card.value != null) return;
    phone.close();
    here.value = null;
    card.value = s;
    game.pauseOverlays.register(GameOverlay.shop);
    final n = loop.npc, id = hostId(s);
    skit = n != null && id != null && n.startSkit(id, s.isBar ? 'bar' : 'shop');
    notifyListeners();
  }

  /// Opens the card of the venue in reach; false when not offered.
  bool tryOpen() {
    final s = canOpen() ? shopHere() : null;
    if (s == null) return false;
    open(s);
    return true;
  }

  /// Opens the running skit as the dialogue (a tap on the host's opening line).
  void openChat() {
    if (!skit || chat) return;
    chat = true;
    notifyListeners();
  }

  /// The host's skit ended ("Odejít" or done): the card stays without it.
  void skitDone() {
    if (!skit) return;
    skit = false;
    chat = false;
    loop.save();
    notifyListeners();
  }

  /// "Zpět": back to driving.
  void close() {
    if (card.value == null) return;
    if (skit) {
      loop.npc?.leave();
      skit = false;
      chat = false;
    }
    card.value = null;
    game.pauseOverlays.unregister(GameOverlay.shop);
    notifyListeners();
  }

  int price(Shop s) => world?.price(s.id) ?? shopPrice(tuning.shops, s.kind);

  bool owns(Shop s) => world?.owns(s.id) ?? false;

  bool canBuy(Shop s) => world?.canBuy(s.id, game.fleet.state.cash) ?? false;

  /// "Koupit" / "Pivo": cash from the cars state goes in `buy`, `last.amount` comes off it; a
  /// toast, and a save after a souvenir. Returns the amount paid (0 = nothing bought).
  int buy(Shop s) {
    final w = world;
    if (w == null) return 0;
    final cash = game.fleet.state.cash;
    if (!w.canBuy(s.id, cash)) return 0;
    final paid = w.buy(s.id, cash);
    game.fleet.setCash(cash - paid);
    switch (s.kind) {
      case 'food':
        _toast(ShopToast.snack, w.config.snackPct);
      case 'souvenir':
        _toast(ShopToast.souvenir, 0);
        loop.save();
      default:
        _toast(w.drunk ? ShopToast.drunk : ShopToast.beer, w.beers);
    }
    notifyListeners();
    return paid;
  }

  /// "Zahrát `název`": the loop on this bar with the chosen minigame (specs/loop.md v2).
  void play(Shop bar, String minigame) {
    close();
    loop.start(bar.id, minigame: minigame);
  }

  /// Host: characters[fnv1a(spotId) mod n] (as the booth), null without characters.
  String? hostId(Shop s) {
    final chars = loop.npc?.pack.characters ?? const [];
    final i = shopHost(s.id, chars.length);
    return i >= 0 ? chars[i].id : null;
  }

  /// The Garage shelf: owned souvenirs in purchase order with their shop names.
  List<({String id, String name})> shelf() {
    final ids = world?.owned ?? loop.savedSouvenirs;
    final names = {for (final s in game.city.spots.items) s.id: s.name};
    return [
      for (final id in ids)
        if (names[id] case final name?) (id: id, name: name),
    ];
  }

  // ---------- drawing: a round icon of shops.icon_m at the parking point in the kind's colour
  void _paintWorld(ui.Canvas c) {
    final r = tuning.shops.iconM / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r / 4
      ..color = const Color(Tokens.colorUiText);
    for (final s in shops) {
      final at = Offset(s.x, s.y);
      c
        ..drawCircle(at, r, Paint()..color = Color(kindColor(s.kind)))
        ..drawCircle(at, r, ring);
    }
    _prevWorld?.call(c);
  }

  @override
  void dispose() {
    if (world != null) {
      if (card.value != null) {
        card.value = null;
        game.pauseOverlays.unregister(GameOverlay.shop);
      }
      if (game.afterUpdate == _afterUpdate) game.afterUpdate = _prevUpdate;
      if (game.paintWorld == _paintWorld) game.paintWorld = _prevWorld;
      if (game.inputHook == _input) game.inputHook = _prevInput;
      if (loop.yieldTo == _yieldLoop) loop.yieldTo = _prevLoopYield;
      if (game.carActionYield == _yieldCar) game.carActionYield = _prevCarYield;
      loop
        ..souvenirs = null
        ..onSouvenirsRestored = null
        ..playHidden = null;
      loop.book
        ..snack = null
        ..shopsFinish = null;
      phone.mapPoints.remove(_mapPoints);
      game.hud.removeListener(_hud);
    }
    card.dispose();
    here.dispose();
    toast.dispose();
    super.dispose();
  }
}
