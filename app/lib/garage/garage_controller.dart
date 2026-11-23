import 'package:drive_core/drive_core.dart';
import 'package:flutter/foundation.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../loop/loop_controller.dart';
import '../phone/phone_controller.dart';
import '../phone/phone_sheet.dart';
import 'garage_app.dart';

/// Tuning and cosmetics of client F (specs/garage.md P1): the `garage` module of the session, cash
/// in and out through the cars state, the save, the body of the driven owned car built from
/// [tunedSpec] (at start, respawn, car switch and leaving the garage) and the looks drawn on owned
/// cars. The Tuning and Vzhled tabs of the garage sheet and the read-only phone app read it.
/// `garage.enabled` off only hides the Tuning and Vzhled tabs: what was bought still applies.
class GarageController extends ChangeNotifier {
  GarageController(this.game, this.loop, {PhoneController? phone}) {
    world = GarageWorld(
      GarageConfig.fromTuning(tuning.garage, {for (final s in game.data.cars.values) s.id: s.tuningSlots}),
      upgrades: loop.savedUpgrades,
      looks: loop.savedLooks,
    );
    loop.garage = () => (upgrades: world.state.upgrades, looks: world.state.looks);
    loop.onGarageRestored = _restored;
    game
      ..drive.bodySpec = _bodySpec
      ..playerLook = _playerLook
      ..parkedLook = _parkedLook;
    game.hud.addListener(_tick);
    if (phone != null) registerPhoneApp(PhoneAppId.garage, (context, phone) => GarageAppScreen(garage: this));
    // Start of the game: the body of the loaded car with its upgrades.
    game.drive.rebuildCar();
  }

  final MetropoleGame game;
  final LoopController loop;
  late final GarageWorld world;

  Tuning get tuning => game.tuning;
  bool get enabled => tuning.garage.enabled;
  CarFleet get fleet => game.fleet;
  int get cash => fleet.state.cash;
  Map<String, CarSpec> get specs => game.data.cars;

  /// Owned cars in the order they were acquired (the garage offers only these).
  List<String> get owned => [
    for (final id in fleet.owned)
      if (specs.containsKey(id)) id,
  ];

  /// Whether the car the player drives now is [id] and his own (not stolen, not the Taxi shift car).
  bool drivesOwn(String id) {
    final s = fleet.state;
    return s.driving == id && s.owned.contains(id) && !s.stolen;
  }

  /// The car the tabs show first: the driven own car, else the first owned one.
  String? get defaultCar {
    final d = game.drive.spec.id;
    if (drivesOwn(d)) return d;
    final o = owned;
    return o.isEmpty ? null : o.first;
  }

  CarSpec _bodySpec(CarSpec spec) => drivesOwn(spec.id) ? tunedSpec(spec, world.levels(spec.id), tuning.garage) : spec;

  CarLook? _playerLook() {
    final id = game.drive.spec.id;
    return drivesOwn(id) ? lookOf(id) : null;
  }

  CarLook? _parkedLook(ParkedCar p) => p.owner == 'player' ? lookOf(p.carId) : null;

  /// The look of [car], with [preview] values over the bought ones (the live preview).
  CarLook lookOf(String car, [Map<String, int> preview = const {}]) => CarLook.of({...world.looks(car), ...preview});

  void _restored(CarLevels upgrades, CarLevels looks) {
    world.load(upgrades, looks);
    game.drive.rebuildCar();
    notifyListeners();
  }

  // ---------- buying (specs/garage.md "Hotovost": cash from the cars state, last.amount off it)

  int? upgradePrice(String car, String slot) => world.upgradePrice(car, slot);

  bool canUpgrade(String car, String slot) => owned.contains(car) && world.canUpgrade(car, slot, cash);

  bool canLook(String car, String part, int value) => owned.contains(car) && world.canLook(car, part, value, cash);

  int lookPrice(String part, int value) => world.config.lookPrice(part, value);

  /// "Vylepšit": true when bought (toast and save).
  bool upgrade(String car, String slot) {
    if (!canUpgrade(car, slot)) return false;
    final c = cash;
    final paid = world.upgrade(car, slot, c);
    if (paid == null) return false;
    _bought(c - paid);
    return true;
  }

  /// "Koupit" a look (or back to stock for free): true when set (toast and save).
  bool buyLook(String car, String part, int value) {
    if (!canLook(car, part, value)) return false;
    final c = cash;
    final paid = world.setLook(car, part, value, c);
    if (paid == null) return false;
    _bought(c - paid);
    return true;
  }

  void _bought(int cashLeft) {
    fleet.setCash(cashLeft);
    toast.value = true;
    _toastS = tuning.nav.toastS;
    loop.save();
    notifyListeners();
  }

  /// Leaving the garage: the world stood, so the driven car is built again in the same place at
  /// speed 0 with its new upgrades.
  void leave() => game.drive.rebuildCar();

  /// "Otevřít garáž" in the phone app (specs/testdrive.md v2): closes the phone and opens the full
  /// garage sheet anywhere; set by the game screen. Null = no button.
  void Function()? openSheet;

  /// The phone app shows "Otevřít garáž": a garage spot in the city, no world minigame running.
  bool get canOpenAnywhere => openSheet != null && fleet.garage != null && !loop.inWorldGame;

  /// The souvenir shelf for the phone app (set by the shops module's owner); null = no shelf.
  List<({String id, String name})> Function()? shelf;

  // ---------- toast `garageBought`
  final toast = ValueNotifier<bool>(false);
  double _toastS = 0;

  /// HUD tick (~10×/s, also while paused). Public for tests.
  void tick([double dt = 0.1]) {
    if (_toastS > 0 && (_toastS -= dt) <= 0) toast.value = false;
  }

  void _tick() => tick();

  @override
  void dispose() {
    if (game.drive.bodySpec == _bodySpec) game.drive.bodySpec = null;
    if (game.playerLook == _playerLook) game.playerLook = null;
    if (game.parkedLook == _parkedLook) game.parkedLook = null;
    loop
      ..garage = null
      ..onGarageRestored = null;
    game.hud.removeListener(_tick);
    toast.dispose();
    super.dispose();
  }
}
