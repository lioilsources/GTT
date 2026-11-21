import 'package:feed_hub/feed_hub.dart' hide Navigator;
import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import 'phone_controller.dart';
import 'phone_sheet.dart';

/// Navigation pill `routeTo` (place · distance) with cancel, and the arrival / no-route toast.
class NavHud extends StatelessWidget {
  const NavHud({super.key, required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          ValueListenableBuilder<NavHudState?>(
            valueListenable: phone.navHud,
            builder: (context, s, _) {
              if (s == null || !phone.nav.active) return const SizedBox.shrink();
              final d = formatDistance(s.remainingM, phone.game.city.imperial, phone.tuning.nav);
              final text = phoneText(context, MessageKey.routeTo, {
                'place': s.place,
                'distance': phoneText(context, d.key, d.args),
              });
              return Positioned(
                top: 96,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.only(left: 14, right: 4),
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorUiPill),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(Tokens.colorUiRouteArrow),
                              fontSize: Tokens.fontHud,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: phoneText(context, MessageKey.routeCancel),
                          icon: const Icon(Icons.close, size: 18, color: Color(Tokens.colorUiTextMuted)),
                          onPressed: phone.cancelNav,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<MessageKey?>(
            valueListenable: phone.toast,
            builder: (context, k, _) {
              if (k == null) return const SizedBox.shrink();
              return Align(
                alignment: const Alignment(0, -0.25),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(Tokens.colorPhoneToast),
                    borderRadius: BorderRadius.circular(Tokens.radiusPill),
                  ),
                  child: Text(
                    phoneText(context, k),
                    style: const TextStyle(
                      color: Color(Tokens.colorUiText),
                      fontSize: Tokens.fontHud,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
