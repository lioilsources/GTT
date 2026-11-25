import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart' show artAssetRoot;
import 'package:shared_gen/shared_gen.dart';

import '../phone/phone_sheet.dart' show messageKey, phoneText;
import 'app_icon.dart';

/// Asset of a mode's whole icon (1024², `metro sync` copies it from assets/ui/app_icon/).
String appIconAsset(AppIconMode mode) => '${artAssetRoot}ui/app_icon/${mode.name}.png';

/// The Settings app of the phone (specs/appicon.md "Výběr ve hře"): the app icon colour mode as a
/// row of five tiles; a tap selects at once.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.icons});
  final AppIconController icons;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: icons,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      children: [
        Text(
          phoneText(context, MessageKey.appIconTitle),
          style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontHudSmall),
        ),
        const SizedBox(height: Tokens.spaceSm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in AppIconMode.values)
              Expanded(
                child: _Tile(mode: m, selected: m == icons.mode, onTap: () => icons.pick(m)),
              ),
          ],
        ),
        // Android switches the launcher entry only when the app goes to background.
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: Tokens.spaceSm),
          Text(
            phoneText(context, MessageKey.appIconLater),
            style: const TextStyle(color: Color(Tokens.colorUiTextFaint), fontSize: Tokens.fontFaint),
          ),
        ],
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.mode, required this.selected, required this.onTap});
  final AppIconMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = phoneText(context, messageKey('appIcon_${mode.name}'));
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('appIcon_${mode.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceXs),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Color(selected ? Tokens.colorPhoneApp : Tokens.colorPhoneScreen),
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      appIconAsset(mode),
                      cacheWidth: 192,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(color: Color(Tokens.colorPhoneBar)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Tokens.spaceXs),
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(selected ? Tokens.colorUiText : Tokens.colorUiTextMuted),
                  fontSize: Tokens.fontFaint,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
