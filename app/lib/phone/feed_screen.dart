import 'package:feed_hub/feed_hub.dart' hide Navigator;
import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import 'phone_controller.dart';
import 'phone_sheet.dart';

/// The Feed app (specs/phone.md "Feed"): one card, gestures map to feed rules actions.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late final _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);
  Offset _drag = Offset.zero;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  void _end() {
    final d = _drag, sw = widget.phone.tuning.phone.swipePx;
    setState(() => _drag = Offset.zero);
    if (-d.dy > sw && -d.dy > d.dx.abs()) {
      widget.phone.act(FeedOp.next);
    } else if (d.dx > sw) {
      widget.phone.act(FeedOp.accept);
    } else if (d.dx < -sw) {
      widget.phone.act(FeedOp.less);
    }
  }

  void _tap() {
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds <= widget.phone.tuning.phone.doubleTapMs) {
      _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      widget.phone.act(FeedOp.like);
    } else {
      _lastTap = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final s = phone.deck;
    final c = s.card;
    String tx(MessageKey k, [Map<String, Object> a = const {}]) => phoneText(context, k, a);
    if (s.over || c == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tx(MessageKey.feedDone),
              style: const TextStyle(
                color: Color(Tokens.colorUiText),
                fontSize: Tokens.fontSpeed,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Tokens.spaceSm),
            Text(tx(MessageKey.feedDoneHint), style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
          ],
        ),
      );
    }
    final d = formatDistance(c.distDm / 10, phone.game.city.imperial, phone.tuning.nav);
    final name = c.game == 'challenge' ? tx(MessageKey.feedChallenge) : tx(messageKey('mg_${c.game}'));
    final liked = s.liked.contains(c.spot);
    final tags = [
      (tx(messageKey('engine_${c.engine}')), false),
      if (c.local) (tx(MessageKey.feedLocal), true),
      ([phone.spotName(c.spot), if (c.district.isNotEmpty) c.district].join(' · '), false),
      ('${tx(d.key, d.args)} · ${tx(MessageKey.feedDriveMin, {'min': driveMinutes(c.driveS)})}', false),
      (tx(MessageKey.feedReward, {'cash': c.reward}), false),
      (tx(MessageKey.difficulty, {'level': c.difficulty}), false),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (u) => setState(() => _drag += u.delta),
      onPanEnd: (_) => _end(),
      onPanCancel: () => setState(() => _drag = Offset.zero),
      onTapUp: (_) => _tap(),
      child: Transform.translate(
        offset: Offset(_drag.dx * 0.5, (_drag.dy < 0 ? _drag.dy : 0) * 0.5),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(Tokens.colorPhoneCardTop), Color(Tokens.colorPhoneCard)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Tokens.spaceLg),
            child: Column(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: _bob,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, -5 * Curves.easeInOut.transform(_bob.value)),
                      child: child,
                    ),
                    child: const _HostPortrait(),
                  ),
                ),
                const SizedBox(height: Tokens.spaceSm),
                Text(
                  tx(messageKey('feedHost${c.host + 1}')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(Tokens.colorUiText),
                    fontSize: Tokens.fontHud,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: Tokens.spaceXs),
                Text.rich(
                  TextSpan(
                    text: name,
                    children: [
                      if (liked)
                        TextSpan(
                          text: '  ♥ ${tx(MessageKey.feedLiked)}',
                          style: const TextStyle(color: Color(Tokens.colorPhoneLiked), fontSize: Tokens.fontHudSmall),
                        ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(Tokens.colorUiText),
                    fontSize: Tokens.fontSpeed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: Tokens.spaceSm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: Tokens.spaceXs,
                  runSpacing: Tokens.spaceXs,
                  children: [for (final (text, local) in tags) _Tag(text: text, local: local)],
                ),
                const SizedBox(height: Tokens.spaceMd),
                FractionallySizedBox(
                  widthFactor: 0.7,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(Tokens.colorPhoneGo),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => phone.act(FeedOp.accept),
                    child: Text(
                      tx(MessageKey.feedGo),
                      style: const TextStyle(
                        color: Color(Tokens.colorUiText),
                        fontSize: Tokens.fontHud,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Tokens.spaceSm),
                Text(
                  '${tx(MessageKey.feedCount, {'n': s.at + 1, 'total': s.deck.length})} · ${tx(MessageKey.feedHint)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(Tokens.colorUiTextFaint), fontSize: Tokens.fontHudSmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.local});
  final String text;
  final bool local;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceSm, vertical: Tokens.spaceXs),
    decoration: BoxDecoration(
      color: Color(local ? Tokens.colorPhoneTagLocal : Tokens.colorPhoneTag),
      borderRadius: BorderRadius.circular(Tokens.radiusPill),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontFaint),
    ),
  );
}

/// M1 placeholder host: a soft silhouette (head and shoulders) until manga portraits exist.
class _HostPortrait extends StatelessWidget {
  const _HostPortrait();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _HostPainter(), child: const SizedBox.expand());
}

class _HostPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height.clamp(0.0, 260.0), w = h * 0.5, cx = size.width / 2, top = (size.height - h) / 2;
    final body = Paint()..color = const Color(Tokens.colorPhoneHost);
    final shade = Paint()..color = const Color(Tokens.colorPhoneHostShade);
    final head = Rect.fromCenter(center: Offset(cx, top + h * 0.3), width: w * 0.5, height: h * 0.32);
    final torso = RRect.fromRectAndCorners(
      Rect.fromLTWH(cx - w / 2, top + h * 0.48, w, h * 0.52),
      topLeft: Radius.circular(w * 0.45),
      topRight: Radius.circular(w * 0.45),
      bottomLeft: const Radius.circular(12),
      bottomRight: const Radius.circular(12),
    );
    canvas
      ..drawRRect(torso, body)
      ..drawRRect(torso.shift(Offset(w * 0.06, 0)).deflate(w * 0.06), shade)
      ..drawOval(head, body)
      ..drawOval(head.deflate(head.width * 0.1).shift(Offset(head.width * 0.08, 0)), shade);
  }

  @override
  bool shouldRepaint(_HostPainter old) => false;
}
