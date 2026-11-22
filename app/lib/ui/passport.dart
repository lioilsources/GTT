import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meta_progress/meta_progress.dart';
import 'package:world_engine/world_engine.dart';

import '../l10n/app_localizations.dart';

/// Plain passport data from a loaded City (specs/passport.md "Katalog razítek").
PassportCity passportCityOf(City c) => passportCityOfPack(c.manifest, c.landmarks, c.spots);

/// The same catalog from the small pack files only (the Travel app reads other cities this way).
PassportCity passportCityOfPack(Manifest m, Landmarks landmarks, Spots spots) => PassportCity(
  landmarks: [
    for (final l in landmarks.items) (id: l.id, name: l.name, x: l.x, y: l.y, heightM: l.heightM, hero: l.hero),
  ],
  districts: [for (final d in m.districts) d.name],
  spotMinigames: [for (final s in spots.items) s.minigame],
);

String _lang(BuildContext context) => Localizations.localeOf(context).languageCode;

/// Text of an `lm_<id>_title` / `_text` key (dynamic keys go through the pure `tr`).
String _lm(BuildContext context, MessageKey? key, String fallback) => key == null ? fallback : tr(_lang(context), key);

/// The placeholder postcard picture; real illustrations come later from ComfyUI (tools/artgen).
class PostcardPicture extends StatelessWidget {
  const PostcardPicture({super.key, required this.id, required this.heightM});
  final String id;
  final double heightM;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: AspectRatio(
      aspectRatio: postcardW / postcardH,
      child: CustomPaint(painter: _PostcardPainter(postcardShapes(id, heightM))),
    ),
  );
}

class _PostcardPainter extends CustomPainter {
  _PostcardPainter(this.shapes);
  final List<PostcardShape> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / postcardW, size.height / postcardH);
    final p = Paint();
    for (final s in shapes) {
      p.color = Color(s.color);
      switch (s) {
        case PostcardRect(:final x, :final y, :final w, :final h):
          canvas.drawRect(Rect.fromLTWH(x, y, w, h), p);
        case PostcardCircle(:final x, :final y, :final r):
          canvas.drawCircle(Offset(x, y), r, p);
        case PostcardPoly(:final pts):
          final path = Path()..moveTo(pts[0], pts[1]);
          for (var i = 2; i < pts.length; i += 2) {
            path.lineTo(pts[i], pts[i + 1]);
          }
          canvas.drawPath(path..close(), p);
      }
    }
  }

  @override
  bool shouldRepaint(_PostcardPainter old) => old.shapes != shapes;
}

/// The postcard card: picture, title, two sentences and the stamp mark.
class PostcardCard extends StatelessWidget {
  const PostcardCard({super.key, required this.landmark, this.onTap});
  final PassportLandmark landmark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const ink = Color(Tokens.colorPassportInk);
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: -0.035,
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(Tokens.spaceMd),
          decoration: BoxDecoration(
            color: const Color(Tokens.colorPassportCard),
            border: Border.all(color: const Color(Tokens.colorPassportCardEdge), width: 2),
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostcardPicture(id: landmark.id, heightM: landmark.heightM),
              const SizedBox(height: Tokens.spaceSm),
              Text(
                _lm(context, postcardTitleKey(landmark.id), landmark.name),
                style: const TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Tokens.spaceXs),
              Text(
                _lm(context, postcardTextKey(landmark.id), ''),
                style: const TextStyle(color: ink, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: Tokens.spaceSm),
              Transform.rotate(
                angle: -0.07,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceSm, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(Tokens.colorPassportStamp), width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l.postcardStamped.toUpperCase(),
                    style: const TextStyle(
                      color: Color(Tokens.colorPassportStamp),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows postcards (landmarks) and stamp labels (districts) as they are stamped.
class PassportOverlay extends StatefulWidget {
  const PassportOverlay({super.key, required this.events, required this.seconds});
  final ValueListenable<StampEvent?> events;
  final double seconds;

  @override
  State<PassportOverlay> createState() => _PassportOverlayState();
}

class _PassportOverlayState extends State<PassportOverlay> {
  PassportLandmark? _card;
  String? _toast;
  Timer? _cardTimer;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    widget.events.addListener(_onEvent);
  }

  @override
  void dispose() {
    widget.events.removeListener(_onEvent);
    _cardTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Duration get _d => Duration(milliseconds: (widget.seconds * 1000).round());

  void _onEvent() {
    final e = widget.events.value;
    if (e == null) return;
    if (e.landmark != null) {
      _cardTimer?.cancel();
      setState(() => _card = e.landmark);
      _cardTimer = Timer(_d, () => mounted ? setState(() => _card = null) : null);
    } else if (e.name != null) {
      _toastTimer?.cancel();
      setState(() => _toast = e.name);
      _toastTimer = Timer(_d, () => mounted ? setState(() => _toast = null) : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: Stack(
        children: [
          if (_toast != null)
            Positioned(
              top: 96,
              left: 24,
              right: 24,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorUiPill),
                      border: Border.all(color: const Color(Tokens.colorPassportStamp)),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: Text(
                      l.passportStampNew(_toast!),
                      style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontNotice),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            left: 0,
            right: 0,
            bottom: _card == null ? -480 : 64,
            child: Center(
              child: _card == null
                  ? const SizedBox(height: 1)
                  : FractionallySizedBox(
                      widthFactor: 0.88,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PostcardCard(landmark: _card!, onTap: () => setState(() => _card = null)),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Passport screen: completion % and a stamp grid per kind. A plain widget, so the phone
/// app (feed_hub) can host it later.
class PassportScreen extends StatelessWidget {
  const PassportScreen({super.key, required this.tracker, required this.cityName, this.about});
  final PassportTracker tracker;
  final String cityName;
  final AboutInfo? about;

  static Future<void> open(BuildContext context, PassportTracker tracker, String cityName, AboutInfo about) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PassportScreen(tracker: tracker, cityName: cityName, about: about),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = tracker.result;
    final sections = {
      'landmark': l.passportLandmarks,
      'district': l.passportDistricts,
      'minigame': l.passportMinigames,
      'photo': l.passportPhotos,
    };
    String name(String kind, String id) => switch (kind) {
      'landmark' => _lm(context, postcardTitleKey(id), id),
      'district' => tracker.districtNames[id] ?? id,
      'minigame' => _lm(context, MessageKey.values.where((k) => k.key == 'mg_$id').firstOrNull, id),
      _ => id,
    };
    return Scaffold(
      backgroundColor: const Color(Tokens.colorUiSheet),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(Tokens.colorUiText),
        title: Text(
          l.passport,
          style: const TextStyle(color: Color(Tokens.colorBrandAccent), fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.spaceMd, 0, Tokens.spaceMd, Tokens.spaceXl),
            children: [
              Text(
                l.passportProgress(cityName, r.percent),
                style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Tokens.spaceSm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: r.percent / 100,
                  minHeight: 8,
                  color: const Color(Tokens.colorPassportProgress),
                  backgroundColor: const Color(Tokens.colorPassportStampEmpty),
                ),
              ),
              for (final kind in stampKinds) ...[
                const SizedBox(height: Tokens.spaceLg),
                Row(
                  children: [
                    Text(
                      sections[kind]!,
                      style: const TextStyle(
                        color: Color(Tokens.colorUiText),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l.passportCount(r.kinds[kind]!.$1, r.kinds[kind]!.$2),
                      style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.spaceSm),
                if (tracker.state.catalog[kind]!.isEmpty)
                  Text(
                    l.passportPhotosLater,
                    style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: 13),
                  )
                else
                  Wrap(
                    spacing: Tokens.spaceSm,
                    runSpacing: Tokens.spaceSm,
                    children: [
                      for (final id in tracker.state.catalog[kind]!)
                        _StampTile(
                          label: name(kind, id),
                          got: tracker.has(kind, id),
                          onTap: kind == 'landmark' && tracker.has(kind, id)
                              ? () => _showPostcard(context, tracker.landmarks.firstWhere((x) => x.id == id))
                              : null,
                        ),
                    ],
                  ),
              ],
              if (about != null) ...[
                const SizedBox(height: Tokens.spaceXl),
                FilledButton.tonal(onPressed: () => AboutMapsScreen.open(context, about!), child: Text(l.aboutTitle)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showPostcard(BuildContext context, PassportLandmark lm) => showDialog<void>(
    context: context,
    builder: (ctx) => Center(
      child: FractionallySizedBox(
        widthFactor: 0.88,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: PostcardCard(landmark: lm, onTap: () => Navigator.of(ctx).pop()),
        ),
      ),
    ),
  );
}

class _StampTile extends StatelessWidget {
  const _StampTile({required this.label, required this.got, this.onTap});
  final String label;
  final bool got;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = got ? const Color(Tokens.colorPassportInk) : const Color(Tokens.colorUiTextFaint);
    return SizedBox(
      width: 104,
      child: Material(
        color: got ? const Color(Tokens.colorPassportCard) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusButton),
          side: BorderSide(
            color: got ? const Color(Tokens.colorPassportStamp) : const Color(Tokens.colorPassportStampEmpty),
            width: got ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusButton),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm, horizontal: Tokens.spaceXs),
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: got ? const Color(Tokens.colorPassportStamp) : fg, width: 2),
                  ),
                  child: got
                      ? const Icon(Icons.star, size: 16, color: Color(Tokens.colorPassportStamp))
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: Tokens.spaceXs),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Values the About screen shows from the city pack manifest.
class AboutInfo {
  const AboutInfo({required this.overtureRelease, required this.builtAt});
  final String overtureRelease;
  final String builtAt;

  factory AboutInfo.of(City c) => AboutInfo(overtureRelease: c.manifest.overtureRelease, builtAt: c.manifest.builtAt);
}

/// About the maps (M1-S12): data sources and licences.
class AboutMapsScreen extends StatelessWidget {
  const AboutMapsScreen({super.key, required this.info});
  final AboutInfo info;

  static Future<void> open(BuildContext context, AboutInfo info) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AboutMapsScreen(info: info)));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const style = TextStyle(color: Color(Tokens.colorUiText), fontSize: 14, height: 1.45);
    Widget p(String s, [TextStyle st = style]) => Padding(
      padding: const EdgeInsets.only(bottom: Tokens.spaceMd),
      child: SelectableText(s, style: st),
    );
    final url = l.aboutRepoUrl;
    return Scaffold(
      backgroundColor: const Color(Tokens.colorUiSheet),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(Tokens.colorUiText),
        title: Text(
          l.aboutTitle,
          style: const TextStyle(color: Color(Tokens.colorBrandAccent), fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(Tokens.spaceMd),
            children: [
              p(l.aboutIntro),
              p(l.aboutOsm),
              p(l.aboutOverture(info.overtureRelease)),
              p(l.aboutOverturePlaces),
              p(l.aboutCityData),
              p(l.aboutShareAlike),
              p(l.aboutPostcards),
              if (info.builtAt.isNotEmpty)
                p(l.aboutPack(info.builtAt), style.copyWith(color: const Color(Tokens.colorUiTextMuted), fontSize: 13)),
              InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                  }
                },
                child: Text(
                  '${l.aboutSource}: $url',
                  style: style.copyWith(color: const Color(Tokens.colorBrandAccent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
