import 'dart:math' as math;

import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:game_loop/game_loop.dart' show CarLook;
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import '../garage/garage_controller.dart';
import '../garage/garage_tabs.dart';
import '../l10n/app_localizations.dart';

/// Garage list (specs/cars.md "Garáž") with the tabs of specs/garage.md: **Auta** (owned cars,
/// picking one drives out with it; the cars for sale, specs/economy.md "Nákup auta"; the free air
/// refill, specs/hop.md "Doplnění"), **Tuning** and **Vzhled** ([garage], hidden with
/// `garage.enabled` off) and **Polička** (specs/shops.md: [shelf] = owned souvenirs in purchase
/// order with their names). The caller holds the pause and calls [GarageController.leave] after.
Future<void> showGarage(
  BuildContext context,
  CarFleet fleet, {
  List<({String id, String name})> Function()? shelf,
  GarageController? garage,
  bool testBlocked = false,
  bool here = false,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(Tokens.colorUiSheet),
  isScrollControlled: true,
  builder: (context) => GarageSheet(fleet: fleet, shelf: shelf, garage: garage, testBlocked: testBlocked, here: here),
);

/// Tabs of the garage sheet, in order.
enum GarageTab { cars, tuning, looks, shelf }

class GarageSheet extends StatefulWidget {
  const GarageSheet({
    super.key,
    required this.fleet,
    this.shelf,
    this.garage,
    this.initialTab = GarageTab.cars,
    this.testBlocked = false,
    this.here = false,
  });
  final CarFleet fleet;

  /// A world minigame runs: "Vyzkoušet" is grey (specs/testdrive.md "Pořadí").
  final bool testBlocked;

  /// Opened from the phone away from the garage spot: a chosen or tried car appears in place of
  /// the player's car (specs/testdrive.md v2 "Garáž z telefonu").
  final bool here;
  final List<({String id, String name})> Function()? shelf;
  final GarageController? garage;
  final GarageTab initialTab;

  @override
  State<GarageSheet> createState() => _GarageSheetState();
}

class _GarageSheetState extends State<GarageSheet> {
  /// The car of the Tuning and Vzhled tabs (the driven own car first).
  String? _car;

  List<GarageTab> get _tabs => [
    GarageTab.cars,
    if (widget.garage?.enabled ?? false) ...[GarageTab.tuning, GarageTab.looks],
    if (widget.shelf != null) GarageTab.shelf,
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tabs = _tabs;
    final g = widget.garage;
    final owned = g?.owned ?? const <String>[];
    final car = _car != null && owned.contains(_car) ? _car : g?.defaultCar;
    void pick(String id) => setState(() => _car = id);
    Widget body(GarageTab t) => switch (t) {
      GarageTab.cars => _carsTab(context, l),
      GarageTab.tuning => car == null ? const SizedBox.shrink() : TuningTab(garage: g!, car: car, onPick: pick),
      GarageTab.looks => car == null ? const SizedBox.shrink() : LooksTab(garage: g!, car: car, onPick: pick),
      GarageTab.shelf => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
        child: SouvenirShelf(items: widget.shelf!()),
      ),
    };
    String label(GarageTab t) => switch (t) {
      GarageTab.cars => l.garageTabCars,
      GarageTab.tuning => l.garageTabTuning,
      GarageTab.looks => l.garageTabLooks,
      GarageTab.shelf => l.garageTabShelf,
    };
    final listen = Listenable.merge([?g, ?g?.toast]);
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) => SafeArea(
        child: DefaultTabController(
          length: tabs.length,
          initialIndex: math.max(0, tabs.indexOf(widget.initialTab)),
          child: Padding(
            padding: const EdgeInsets.all(Tokens.spaceLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.garageTitle,
                  style: const TextStyle(
                    color: Color(Tokens.colorUiText),
                    fontSize: Tokens.fontHud,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (tabs.length > 1)
                  TabBar(
                    key: const ValueKey('garageTabs'),
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: const Color(Tokens.colorUiText),
                    unselectedLabelColor: const Color(Tokens.colorUiTextMuted),
                    indicatorColor: const Color(Tokens.colorGarageLevel),
                    tabs: [for (final t in tabs) Tab(key: ValueKey('garageTab:${t.name}'), text: label(t))],
                  ),
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6,
                  child: tabs.length > 1 ? TabBarView(children: [for (final t in tabs) body(t)]) : body(tabs.first),
                ),
                if (g != null && g.toast.value)
                  Container(
                    key: const ValueKey('garageBought'),
                    padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceXs),
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorUiNotice),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: Text(
                      l.garageBought,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(Tokens.colorUiText)),
                    ),
                  ),
                Text(
                  l.cashHud(widget.fleet.state.cash),
                  key: const ValueKey('garageCash'),
                  style: const TextStyle(color: Color(Tokens.colorLoopCash)),
                ),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.close)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _carsTab(BuildContext context, AppLocalizations l) {
    final fleet = widget.fleet;
    final buyable = fleet.buyable().toSet();
    final sale = saleOrder(fleet.specs.values, fleet.owned, fleet.drive.city.id);
    final drive = fleet.drive;
    final hopFull = hopCharges(drive.spec);
    final g = widget.garage;
    Widget preview(CarSpec spec, CarLook look) => CarPreview(
      key: ValueKey('garageCarPreview:${spec.id}'),
      spec: spec,
      look: look,
      tuning: fleet.tuning,
      width: _previewW,
      height: _previewH,
      sideways: true,
    );
    Widget subtitle(CarSpec spec) =>
        Text(carClassName(l, spec.class_), style: const TextStyle(color: Color(Tokens.colorUiTextMuted)));
    return ListView(
      key: const ValueKey('garageCars'),
      children: [
        if (hopFull != null) ...[
          if (drive.hop.charges == 0) Text(l.hopEmpty, style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
          FilledButton.tonal(
            key: const ValueKey('hopRefill'),
            onPressed: drive.hop.canRefill(drive.spec) ? () => setState(() => drive.refillHop()) : null,
            child: Text('${l.hopRefill}  ${drive.hop.charges}/$hopFull'),
          ),
        ],
        for (final id in fleet.owned)
          if (fleet.specs[id] case final spec?)
            ListTile(
              leading: preview(spec, g?.lookOf(spec.id) ?? const CarLook()),
              title: Text(spec.name, style: const TextStyle(color: Color(Tokens.colorUiText))),
              subtitle: subtitle(spec),
              trailing: fleet.canSelect(id)
                  ? FilledButton(
                      onPressed: () {
                        fleet.select(id, here: widget.here);
                        Navigator.of(context).pop();
                      },
                      child: Text(l.garageTakeOut),
                    )
                  : Text(l.garageDriving, style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
            ),
        if (sale.isNotEmpty) ...[
          const SizedBox(height: Tokens.spaceSm),
          Text(
            l.garageForSale,
            style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
          ),
          for (final spec in sale)
            ListTile(
              key: ValueKey('garageSale:${spec.id}'),
              isThreeLine: true,
              leading: preview(spec, const CarLook()),
              title: Text(spec.name, style: const TextStyle(color: Color(Tokens.colorUiText))),
              subtitle: subtitle(spec),
              // "Vyzkoušet" next to "Koupit" (specs/testdrive.md "Nabídka"): the test drive starts
              // as the sheet closes; the caller's GarageController.leave rebuilds the same body.
              trailing: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      style: _compact,
                      onPressed: buyable.contains(spec.id) ? () => setState(() => fleet.buy(spec.id)) : null,
                      child: Text(l.garageBuy(spec.price)),
                    ),
                    TextButton(
                      key: ValueKey('garageTestDrive:${spec.id}'),
                      style: _compact,
                      onPressed: widget.testBlocked || !fleet.canTest(spec.id)
                          ? null
                          : () {
                              fleet.startTest(spec.id, here: widget.here);
                              Navigator.of(context).pop();
                            },
                      child: Text(l.garageTestDrive),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Size of the small car preview in the garage list (logical px), the nose to the right.
const _previewW = 56.0, _previewH = 28.0;

/// "Koupit" and "Vyzkoušet" stacked in the trailing slot of a sale row.
const _compact = ButtonStyle(
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  minimumSize: WidgetStatePropertyAll(Size(0, 30)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Tokens.spaceSm)),
);

/// The name of a car class (`carClass*` in i18n, specs/cars.md "Garáž").
String carClassName(AppLocalizations l, String cls) => switch (cls) {
  'mini' => l.carClassMini,
  'hatchback' => l.carClassHatchback,
  'sedan' => l.carClassSedan,
  'kombi' => l.carClassKombi,
  'coupe' => l.carClassCoupe,
  'muscle' => l.carClassMuscle,
  'supersport' => l.carClassSupersport,
  'veteran' => l.carClassVeteran,
  'offroad' => l.carClassOffroad,
  'pickup' => l.carClassPickup,
  'van' => l.carClassVan,
  'taxi' => l.carClassTaxi,
  'limo' => l.carClassLimo,
  'bus' => l.carClassBus,
  'micro' => l.carClassMicro,
  _ => l.carClassSpecial,
};

/// Size of one souvenir on the shelf (logical px).
const _souvenirPx = 72.0;

/// The Garage shelf (specs/shops.md "Polička"): the picture `assets/souvenirs/<id>.png` when it is
/// in assets/index.json, else an icon in `shops.souvenir`, the name below; `shopShelfEmpty` empty.
class SouvenirShelf extends StatelessWidget {
  const SouvenirShelf({super.key, required this.items});
  final List<({String id, String name})> items;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const icon = Icon(Icons.redeem, size: _souvenirPx * 0.6, color: Color(Tokens.colorShopsSouvenir));
    return Column(
      key: const ValueKey('shopShelf'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.shopShelf,
          style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Tokens.spaceSm),
        if (items.isEmpty)
          Text(l.shopShelfEmpty, style: const TextStyle(color: Color(Tokens.colorUiTextMuted)))
        else
          Wrap(
            spacing: Tokens.spaceMd,
            runSpacing: Tokens.spaceMd,
            children: [
              for (final s in items)
                SizedBox(
                  width: _souvenirPx,
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: _souvenirPx,
                        child: switch (artIndex.souvenir(s.id)) {
                          final path? => ArtImage(
                            path: path,
                            decodeWidth: _souvenirPx,
                            fit: BoxFit.contain,
                            fallback: const Center(child: icon),
                          ),
                          null => const Center(child: icon),
                        },
                      ),
                      Text(
                        s.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontFaint),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
