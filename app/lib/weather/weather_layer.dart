import 'package:flutter/material.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import 'weather_controller.dart';

/// Icon of a kind (specs/weather.md "HUD"): clear = sun, rain = drop, fog = waves.
IconData weatherIcon(WeatherKind k) => switch (k) {
  WeatherKind.clear => Icons.wb_sunny,
  WeatherKind.rain => Icons.water_drop,
  WeatherKind.fog => Icons.waves,
};

/// The change toast text of a kind.
String weatherText(AppLocalizations l, WeatherKind k) => switch (k) {
  WeatherKind.clear => l.weatherClear,
  WeatherKind.rain => l.weatherRain,
  WeatherKind.fog => l.weatherFog,
};

/// Weather HUD over the world: the small kind icon next to the other HUD pills and the change toast.
/// Nothing when weather is off in the city.
class WeatherLayer extends StatelessWidget {
  const WeatherLayer({super.key, required this.weather});
  final WeatherController weather;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: Listenable.merge([weather.kind, weather.toast]),
          builder: (context, _) {
            final k = weather.kind.value, t = weather.toast.value;
            if (k == null) return const SizedBox.shrink();
            return Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 52,
                  child: Container(
                    key: const ValueKey('weatherIcon'),
                    padding: const EdgeInsets.all(Tokens.spaceSm),
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorUiPill),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: Icon(
                      weatherIcon(k),
                      key: ValueKey('weatherIcon.${k.name}'),
                      size: Tokens.fontHud,
                      color: const Color(Tokens.colorWeatherIcon),
                    ),
                  ),
                ),
                if (t != null)
                  Align(
                    alignment: const Alignment(0, -0.42),
                    child: DecoratedBox(
                      key: const ValueKey('weatherToast'),
                      decoration: BoxDecoration(
                        color: const Color(Tokens.colorUiPill),
                        borderRadius: BorderRadius.circular(Tokens.radiusPill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              weatherIcon(t),
                              size: Tokens.fontHudSmall,
                              color: const Color(Tokens.colorWeatherIcon),
                            ),
                            const SizedBox(width: Tokens.spaceSm),
                            Text(
                              weatherText(l, t),
                              style: const TextStyle(
                                color: Color(Tokens.colorUiText),
                                fontSize: Tokens.fontHudSmall,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
