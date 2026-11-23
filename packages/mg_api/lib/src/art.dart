import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

// Generated art wiring (specs/art.md v1): what exists comes only from `assets/index.json` written
// by `metro sync`; a file missing from the index does not exist (no probing at run time).

/// Portrait expression of a character with [vibe] (specs/art.md "Výraz podle vibe").
String npcExpression(int vibe, {required int contactMinVibe, required int vibeStart}) {
  if (vibe >= contactMinVibe) return 'happy';
  if (vibe < vibeStart) return 'annoyed';
  return 'neutral';
}

/// The sorted list of generated PNGs (paths relative to `assets/`).
class ArtIndex {
  ArtIndex(Iterable<String> paths) : _paths = paths.toSet();

  /// No art at all (missing or unreadable index.json).
  static final empty = ArtIndex(const []);

  /// Parses index.json (`["npc/maya.png", …]`); anything malformed = no art.
  factory ArtIndex.fromJson(String json) {
    try {
      final v = jsonDecode(json);
      if (v is List) return ArtIndex(v.whereType<String>());
    } catch (_) {}
    return empty;
  }

  final Set<String> _paths;

  bool has(String path) => _paths.contains(path);
  bool get isEmpty => _paths.isEmpty;

  String? _first(List<String> candidates) {
    for (final c in candidates) {
      if (has(c)) return c;
    }
    return null;
  }

  /// Dialogue portrait: `npc/<id>_<expression>.png`, then `npc/<id>.png`, else null (initials).
  String? portrait(String id, [String? expression]) =>
      _first([if (expression != null) 'npc/${id}_$expression.png', 'npc/$id.png']);

  /// Contacts and rival circle: `npc/<id>.png`, else null (initials).
  String? avatar(String id) => portrait(id);

  /// Feed card / booth offer host: `npc/<id>_bust.png`, else null (silhouette).
  String? bust(String id) => _first(['npc/${id}_bust.png']);

  /// Landmark postcard: `postcards/<city>/<id>.png`, else null (placeholder drawing).
  String? postcard(String city, String id) => _first(['postcards/$city/$id.png']);

  /// Souvenir on the Garage shelf (specs/shops.md): `souvenirs/<id>.png`, else null (icon).
  String? souvenir(String id) => _first(['souvenirs/$id.png']);

  /// UI icon (specs/art.md v3 "Ikony UI"): `ui/<id>.png` (phone apps, `wanted_star`,
  /// `weather_<kind>`, `radio`), else null (today's drawing).
  String? uiIcon(String id) => _first(['ui/$id.png']);
}

/// Bundle prefix of the synced art (`metro sync` → app/assets/shared/assets/).
const artAssetRoot = 'assets/shared/assets/';

/// The app-wide index; [ArtIndex.empty] until [loadArtIndex] ran (tests keep the placeholders).
ArtIndex artIndex = ArtIndex.empty;

/// Loads `assets/shared/assets/index.json` once at start; a missing file = no art.
Future<ArtIndex> loadArtIndex(AssetBundle bundle) async {
  try {
    artIndex = ArtIndex.fromJson(await bundle.loadString('${artAssetRoot}index.json', cache: false));
  } catch (_) {
    artIndex = ArtIndex.empty;
  }
  return artIndex;
}

/// Least-recently-used set of decoded art images (specs/art.md "Výkon": 24 pieces). Each key is
/// one decoded size of one file; the oldest is evicted from Flutter's image cache.
class ArtCache {
  ArtCache(this.capacity);
  final int capacity;
  final _keys = <(String, int), ImageProvider>{}; // insertion order = LRU order

  int get length => _keys.length;
  Iterable<(String, int)> get keys => _keys.keys;

  /// The provider of [path] decoded to [width] physical px; marks it as most recently used.
  ImageProvider provider(String path, int width) {
    final k = (path, width);
    final p = _keys.remove(k) ?? ResizeImage(AssetImage('$artAssetRoot$path'), width: width, allowUpscaling: false);
    _keys[k] = p;
    while (_keys.length > capacity) {
      final old = _keys.remove(_keys.keys.first)!;
      old.evict();
    }
    return p;
  }
}

final artCache = ArtCache(24);

/// Decode width for [logical] px on this screen, rounded up to 64 px steps (fewer cache keys).
int artDecodeWidth(BuildContext context, double logical) {
  final px = (logical * MediaQuery.devicePixelRatioOf(context)).ceil();
  return ((px + 63) ~/ 64) * 64;
}

/// One generated image ([path] relative to `assets/`), decoded at its on-screen size, with
/// [fallback] if decoding fails. [decodeWidth] is the logical width the image is drawn at.
class ArtImage extends StatelessWidget {
  const ArtImage({
    super.key,
    required this.path,
    required this.decodeWidth,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String path;
  final double decodeWidth;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Image(
    image: artCache.provider(path, artDecodeWidth(context, decodeWidth)),
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => fallback,
  );
}

/// A UI icon (specs/art.md v3 "Ikony UI"): the white glyph `ui/<id>.png` multiplied by [color]
/// ([BlendMode.modulate]) at [size] × [size], or [fallback] (today's icon) when the file is not in
/// the index or fails to decode. The icon never changes the layout.
class ArtIcon extends StatelessWidget {
  const ArtIcon(this.id, {super.key, required this.size, required this.color, required this.fallback});
  final String id;
  final double size;
  final Color color;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final path = artIndex.uiIcon(id);
    if (path == null) return fallback;
    return SizedBox.square(
      dimension: size,
      child: Image(
        key: ValueKey('artIcon:$id'),
        image: artCache.provider(path, artDecodeWidth(context, size)),
        width: size,
        height: size,
        color: color,
        colorBlendMode: BlendMode.modulate,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// A character in a circle: the portrait art (`cover` crop to a square) or, without it, initials
/// on a token-coloured circle. [expression] picks the dialogue variant (null = contacts / rival).
class NpcAvatar extends StatelessWidget {
  const NpcAvatar({
    super.key,
    required this.id,
    required this.initials,
    required this.index,
    this.size = 56,
    this.expression,
  });

  final String id;

  /// Placeholder text (initials) when there is no art.
  final String initials;

  /// Index into [Tokens.colorNpcPortraits] for the placeholder.
  final int index;
  final double size;
  final String? expression;

  @override
  Widget build(BuildContext context) {
    const colors = Tokens.colorNpcPortraits;
    final placeholder = CircleAvatar(
      radius: size / 2,
      backgroundColor: Color(colors[index % colors.length]),
      child: Text(
        initials,
        style: TextStyle(
          color: const Color(Tokens.colorNpcPortraitText),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
    final path = artIndex.portrait(id, expression);
    if (path == null) return placeholder;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: ColoredBox(
          color: Color(colors[index % colors.length]),
          child: ArtImage(path: path, decodeWidth: size, fallback: placeholder),
        ),
      ),
    );
  }
}

/// Host bust height as a part of its card (specs/art.md "≈ 45 % karty").
const hostBustHeight = 0.45;

/// Bust aspect (768 × 1280, specs/art.md).
const _bustAspect = 768 / 1280;

/// A host bust (`npc/<id>_bust.png`, transparent background) anchored at the bottom of the space
/// it gets, [height] tall at most.
class HostBust extends StatelessWidget {
  const HostBust({super.key, required this.path, required this.height, required this.fallback});
  final String path;
  final double height;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final h = box.hasBoundedHeight ? (height < box.maxHeight ? height : box.maxHeight) : height;
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: h,
          width: h * _bustAspect,
          child: ArtImage(
            path: path,
            decodeWidth: h * _bustAspect,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            fallback: fallback,
          ),
        ),
      );
    },
  );
}
