import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import 'feed_screen.dart';
import 'map_screen.dart';
import 'phone_controller.dart';
import 'travel_screen.dart';

/// Shared i18n lookup for the phone (keys are built from ids, e.g. `app_feed`, `engine_cards`).
String phoneText(BuildContext context, MessageKey key, [Map<String, Object> args = const {}]) =>
    tr(Localizations.localeOf(context).languageCode, key, args);

/// Message key by its i18n key (e.g. `app_feed`); the enum names are camel case (`appFeed`).
MessageKey messageKey(String key) => MessageKey.values.firstWhere((k) => k.key == key);

typedef PhoneAppBuilder = Widget Function(BuildContext context, PhoneController phone);

/// The slot other features use to bring their app to life; unregistered apps are greyed out.
final Map<PhoneAppId, PhoneAppBuilder> phoneApps = {
  PhoneAppId.feed: (context, phone) => FeedScreen(phone: phone),
  PhoneAppId.map: (context, phone) => MapScreen(phone: phone),
  PhoneAppId.travel: (context, phone) => TravelScreen(phone: phone),
};

void registerPhoneApp(PhoneAppId id, PhoneAppBuilder builder) => phoneApps[id] = builder;

const _icons = {
  PhoneAppId.feed: Icons.dynamic_feed,
  PhoneAppId.map: Icons.map,
  PhoneAppId.taxi: Icons.local_taxi,
  PhoneAppId.garage: Icons.garage,
  PhoneAppId.passport: Icons.badge,
  PhoneAppId.camera: Icons.photo_camera,
  PhoneAppId.contacts: Icons.contacts,
  PhoneAppId.wallet: Icons.account_balance_wallet,
  PhoneAppId.travel: Icons.flight_takeoff,
  PhoneAppId.settings: Icons.settings,
};

/// Bottom-edge grab zone plus the phone sheet (specs/phone.md "Telefon").
class PhoneLayer extends StatelessWidget {
  const PhoneLayer({super.key, required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final t = phone.tuning.phone;
    return ListenableBuilder(
      listenable: phone,
      builder: (context, _) => Stack(
        children: [
          if (!phone.isOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: t.edgePx + MediaQuery.paddingOf(context).bottom,
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: _Swipe(
                    onSwipe: (dy) => dy < -t.pullPx ? phone.open() : null,
                    child: Align(
                      alignment: const Alignment(0, 0.4),
                      child: Container(
                        width: 56,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(Tokens.colorPhoneHandle),
                          borderRadius: BorderRadius.circular(Tokens.radiusPill),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (phone.isOpen)
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: t.heightPct / 100,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _Sheet(phone: phone),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Swipe extends StatefulWidget {
  const _Swipe({required this.onSwipe, required this.child});
  final void Function(double dy) onSwipe;
  final Widget child;

  @override
  State<_Swipe> createState() => _SwipeState();
}

class _SwipeState extends State<_Swipe> {
  double _dy = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: (_) => _dy = 0,
    onVerticalDragUpdate: (d) => _dy += d.delta.dy,
    onVerticalDragEnd: (_) => widget.onSwipe(_dy),
    child: widget.child,
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final app = phone.app;
    final builder = app == null ? null : phoneApps[app];
    final title = app == null ? MessageKey.phone : messageKey('app_${app.name}');
    return Container(
      decoration: const BoxDecoration(
        color: Color(Tokens.colorPhoneBody),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          _Swipe(
            onSwipe: (dy) => dy > phone.tuning.phone.pullPx ? phone.close() : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.spaceMd, Tokens.spaceSm, Tokens.spaceMd, Tokens.spaceSm),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorPhoneHandle),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                  ),
                  const SizedBox(height: Tokens.spaceSm),
                  Row(
                    children: [
                      Opacity(
                        opacity: app == null ? 0 : 1,
                        child: _BarButton(
                          icon: Icons.chevron_left,
                          onTap: app == null ? null : () => phone.launch(null),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          phoneText(context, title),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(Tokens.colorUiText),
                            fontSize: Tokens.fontHud,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _BarButton(icon: Icons.close, onTap: phone.close),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.spaceSm, 0, Tokens.spaceSm, Tokens.spaceSm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: const Color(Tokens.colorPhoneScreen),
                  child: builder == null ? _Home(phone: phone) : builder(context, phone),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(Tokens.colorPhoneBar),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: const Color(Tokens.colorUiText), size: 22),
      ),
    ),
  );
}

class _Home extends StatelessWidget {
  const _Home({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cell = math.min(80.0, box.maxWidth / 4);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Tokens.spaceXl, horizontal: Tokens.spaceSm),
        child: Wrap(
          runSpacing: Tokens.spaceLg,
          children: [
            for (final id in PhoneAppId.values)
              SizedBox(
                width: (box.maxWidth - 2 * Tokens.spaceSm) / 4,
                child: _AppIcon(
                  icon: _icons[id]!,
                  size: cell * 0.7,
                  label: phoneText(context, messageKey('app_${id.name}')),
                  onTap: phoneApps.containsKey(id) ? () => phone.launch(id) : null,
                ),
              ),
            if (phone.onToRoad case final toRoad?)
              SizedBox(
                width: box.maxWidth - 2 * Tokens.spaceSm,
                child: Center(
                  child: FilledButton.icon(
                    key: const ValueKey('phoneToRoad'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(Tokens.colorPhoneApp),
                      foregroundColor: const Color(Tokens.colorPhoneAppText),
                    ),
                    icon: const Icon(Icons.add_road),
                    label: Text(phoneText(context, MessageKey.flowToRoad)),
                    onPressed: () {
                      // Close the phone first: the move then plays in the running game.
                      phone.close();
                      toRoad();
                    },
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon, required this.size, required this.label, required this.onTap});
  final IconData icon;
  final double size;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Color(on ? Tokens.colorPhoneApp : Tokens.colorPhoneAppOff),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: size * 0.5, color: Color(on ? Tokens.colorPhoneAppText : Tokens.colorUiTextFaint)),
          ),
          const SizedBox(height: Tokens.spaceXs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(on ? Tokens.colorUiText : Tokens.colorUiTextFaint),
              fontSize: Tokens.fontFaint,
            ),
          ),
        ],
      ),
    );
  }
}
