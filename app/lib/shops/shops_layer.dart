import 'package:flutter/material.dart';
import 'package:game_loop/game_loop.dart';
import 'package:mg_api/mg_api.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import '../loop/loop_controller.dart';
import 'shops_controller.dart';

/// Shops HUD over the world (specs/shops.md): the "Koupit" / "Bar" context button, the beers pill,
/// the drunk banner, toasts and the shop / bar card.
class ShopsLayer extends StatelessWidget {
  const ShopsLayer({super.key, required this.shops});
  final ShopsController shops;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final locale = messageLocales.contains(lang) ? lang : 'en';
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([shops, shops.card, shops.here, shops.toast]),
        builder: (context, _) {
          final c = shops.card.value, h = shops.here.value, t = shops.toast.value;
          return Stack(
            children: [
              if (shops.drunk)
                const Align(alignment: Alignment(0, -0.7), child: DrunkBanner())
              else if (shops.beers > 0)
                Positioned(
                  left: 12,
                  bottom: 124,
                  child: _Pill(text: l.shopBeers(shops.beers), color: const Color(Tokens.colorUiText)),
                ),
              if (t != null)
                Align(
                  alignment: const Alignment(0, -0.55),
                  child: IgnorePointer(
                    child: _Pill(
                      text: switch (t.kind) {
                        ShopToast.snack => l.shopSnack(t.n),
                        ShopToast.souvenir => l.shopOwned,
                        ShopToast.beer => l.shopBeers(t.n),
                        ShopToast.drunk => l.shopsDrunk,
                        ShopToast.sober => l.shopsSober,
                      },
                      color: const Color(Tokens.colorUiText),
                    ),
                  ),
                ),
              if (h != null && c == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 148,
                  child: Center(
                    child: FilledButton(
                      key: const ValueKey('shopOpen'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Color(ShopsController.kindColor(h.kind)),
                        foregroundColor: const Color(Tokens.colorUiText),
                      ),
                      onPressed: shops.tryOpen,
                      child: Text(h.isBar ? l.barOpen : l.shopOpen),
                    ),
                  ),
                ),
              if (c != null) Positioned.fill(child: ShopCard(shops: shops, shop: c, locale: locale)),
              if (c != null && shops.chat && shops.loop.npc != null)
                Positioned.fill(
                  child: DialogueView(session: shops.loop.npc!, locale: locale, onClose: shops.skitDone),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The drunk strip (spec "Piva"): `shopsDrunk` on `shops.drunk`.
class DrunkBanner extends StatelessWidget {
  const DrunkBanner({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      key: const ValueKey('shopsDrunk'),
      width: double.infinity,
      color: const Color(Tokens.colorShopsDrunk),
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
      child: Text(
        AppLocalizations.of(context).shopsDrunk,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(Tokens.colorUiText),
          fontSize: Tokens.fontHudSmall,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(Tokens.colorUiPill),
      borderRadius: BorderRadius.circular(Tokens.radiusPill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: Tokens.fontHudSmall, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

const _cardW = 360.0;

/// The shop or bar card: host bust, the host's skit, the venue, what it sells, price and buttons.
class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shops, required this.shop, required this.locale});
  final ShopsController shops;
  final Shop shop;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = shops.hostId(shop);
    final bust = id == null ? null : artIndex.bust(id);
    final beat = shops.skit ? shops.loop.npc?.beat : null;
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final price = shops.price(shop);
    final can = shops.canBuy(shop);
    Widget buyButton(String label) => SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: ValueKey('shopBuy:${shop.id}'),
        onPressed: can ? () => shops.buy(shop) : null,
        child: Text(label),
      ),
    );
    final cash = shops.game.fleet.state.cash;
    return ColoredBox(
      color: const Color(Tokens.colorUiPill),
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: _cardW,
            margin: const EdgeInsets.all(Tokens.spaceLg),
            padding: const EdgeInsets.all(Tokens.spaceLg),
            decoration: BoxDecoration(
              color: const Color(Tokens.colorUiSheet),
              borderRadius: BorderRadius.circular(Tokens.radiusButton),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The host bust (specs/art.md); without the file the card stays text only.
                if (bust != null)
                  HostBust(path: bust, height: _cardW * hostBustHeight, fallback: const SizedBox.shrink()),
                // The host's skit (context shop / bar): its opening line; a tap opens the dialogue.
                if (beat != null)
                  Material(
                    color: const Color(Tokens.colorNpcBubble),
                    borderRadius: BorderRadius.circular(Tokens.radiusButton),
                    child: InkWell(
                      key: const ValueKey('shopSkit'),
                      borderRadius: BorderRadius.circular(Tokens.radiusButton),
                      onTap: shops.openChat,
                      child: Padding(
                        padding: const EdgeInsets.all(Tokens.spaceMd),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                npcText(beat.npc, locale),
                                style: const TextStyle(color: Color(Tokens.colorNpcBubbleText), height: 1.35),
                              ),
                            ),
                            const SizedBox(width: Tokens.spaceSm),
                            const Icon(Icons.chat_bubble_outline, color: Color(Tokens.colorNpcBubbleText)),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: Tokens.spaceSm),
                Text(
                  shop.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(Tokens.colorUiText),
                    fontSize: Tokens.fontHud,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Tokens.spaceSm),
                if (shop.kind == 'food') ...[
                  _PriceRow(label: l.shopSnack(shops.tuning.shops.snackPct), price: l.cashHud(price)),
                  buyButton(l.shopBuy),
                ] else if (shop.kind == 'souvenir') ...[
                  _PriceRow(label: shop.name, price: l.cashHud(price)),
                  if (shops.owns(shop))
                    Text(l.shopOwned, textAlign: TextAlign.center, style: muted)
                  else
                    buyButton(l.shopBuy),
                ] else ...[
                  _PriceRow(label: l.shopBeer, price: l.cashHud(price)),
                  buyButton(l.shopBuy),
                  const SizedBox(height: Tokens.spaceSm),
                  for (final g in shops.games)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: ValueKey('shopPlay:$g'),
                        onPressed: () => shops.play(shop, g),
                        child: Text(l.shopPlay(_mgName(g))),
                      ),
                    ),
                ],
                if (!can && !shops.owns(shop))
                  Text(l.shopNoCash, textAlign: TextAlign.center, style: muted),
                Text(l.cashHud(cash), textAlign: TextAlign.center, style: muted),
                const SizedBox(height: Tokens.spaceSm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const ValueKey('shopBack'),
                    onPressed: shops.close,
                    child: Text(l.shopBack),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _mgName(String id) {
    final k = LoopController.nameKey(id);
    return k == null ? id : tr(locale, k);
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.price});
  final String label, price;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Color(Tokens.colorUiText)))),
        Text(
          price,
          style: const TextStyle(color: Color(Tokens.colorLoopCash), fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
