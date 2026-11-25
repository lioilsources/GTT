import 'dart:math' as math;

import 'package:feed_hub/feed_hub.dart' hide Navigator;
import 'package:flutter/material.dart';
import 'package:game_loop/game_loop.dart' show opponentIndex;
import 'package:mg_api/mg_api.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';

import 'phone_controller.dart';
import 'phone_sheet.dart';

/// The Feed app (specs/phone.md v5 "Gesta karty"): a [FeedPager] of host cards; gestures map
/// to feed rules actions (specs/feed.md v2).
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late final _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    String tx(MessageKey k, [Map<String, Object> a = const {}]) => phoneText(context, k, a);
    return LayoutBuilder(
      builder: (context, box) => FeedPager(
        state: phone.deck,
        tuning: phone.tuning.phone,
        onAction: phone.act,
        goLabel: tx(MessageKey.feedGo),
        lessLabel: tx(MessageKey.feedLess),
        card: (s, at) => _card(context, s, at, box.maxHeight),
        done: () => _done(context),
      ),
    );
  }

  Widget _done(BuildContext context) {
    String tx(MessageKey k) => phoneText(context, k);
    return ColoredBox(
      color: const Color(Tokens.colorPhoneScreen),
      child: Center(
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
      ),
    );
  }

  Widget _card(BuildContext context, FeedState s, int at, double cardHeight) {
    final phone = widget.phone;
    final c = s.deck[at];
    String tx(MessageKey k, [Map<String, Object> a = const {}]) => phoneText(context, k, a);
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
    final chars = dialogueSession?.pack.characters ?? const [];
    // Host = characters[fnv1a(spotId) mod n], as the minigame rival and the booth host.
    final hi = opponentIndex(c.spot, chars.length);
    final hostId = hi < 0 ? null : chars[hi].id;
    return DecoratedBox(
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
                builder: (context, child) =>
                    Transform.translate(offset: Offset(0, -5 * Curves.easeInOut.transform(_bob.value)), child: child),
                child: _HostPortrait(id: hostId, cardHeight: cardHeight),
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
              // "Jedu" never starts a drag (specs/phone.md v5).
              child: FeedNoDrag(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(Tokens.colorPhoneGo),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    if (phone.deck.at == at && !phone.deck.over) phone.act(FeedOp.accept);
                  },
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
            ),
            const SizedBox(height: Tokens.spaceSm),
            Text(
              '${tx(MessageKey.feedCount, {'n': at + 1, 'total': s.deck.length})} · ${tx(MessageKey.feedHint)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(Tokens.colorUiTextFaint), fontSize: Tokens.fontHudSmall),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- pure gesture maths (specs/phone.md v5, unit-tested)

enum FeedAxis { vertical, horizontal }

/// Axis lock: none until the finger moves `lockPx` in either axis, then the larger component wins.
FeedAxis? feedLockAxis(double dx, double dy, double lockPx) {
  if (math.max(dx.abs(), dy.abs()) < lockPx) return null;
  return dy.abs() >= dx.abs() ? FeedAxis.vertical : FeedAxis.horizontal;
}

/// Release velocity (px/s): travel from the oldest sample within `windowMs` of the last one to the last.
double feedReleaseVelocity(List<({double t, double p})> samples, int windowMs) {
  if (samples.isEmpty) return 0;
  final last = samples.last;
  final first = samples.firstWhere((x) => x.t >= last.t - windowMs);
  final dt = last.t - first.t;
  return dt > 0 ? (last.p - first.p) * 1000 / dt : 0;
}

/// Strip offset for a vertical drag: 1:1 towards an existing page, rubber band otherwise.
double feedStripOffset(double dy, bool hasPrev, bool hasNext, TuningPhone ph) {
  final exists = dy < 0 ? hasNext : (dy > 0 ? hasPrev : true);
  return exists ? dy : dy * ph.feedRubber;
}

/// Vertical release: the action to commit ([FeedOp.next] up, [FeedOp.prev] down) or null.
FeedOp? feedVerticalRelease(double dy, double v, double h, bool hasPrev, bool hasNext, TuningPhone ph) {
  if (dy == 0 || !(dy < 0 ? hasNext : hasPrev)) return null;
  final along = dy < 0 ? -v : v;
  final far = dy.abs() > h * ph.feedCommitPct / 100;
  return far || along > ph.feedFlickPxS ? (dy < 0 ? FeedOp.next : FeedOp.prev) : null;
}

/// Sideways release: [FeedOp.accept] (right), [FeedOp.less] (left) or null to return.
FeedOp? feedSideRelease(double dx, double v, TuningPhone ph) {
  if (dx == 0) return null;
  final along = dx < 0 ? -v : v;
  return dx.abs() > ph.swipePx || along > ph.feedFlickPxS ? (dx > 0 ? FeedOp.accept : FeedOp.less) : null;
}

/// Card tilt (degrees) around its bottom edge centre for a sideways drag over a `w` wide feed.
double feedTiltDeg(double dx, double w, TuningPhone ph) => w > 0 ? ph.feedTiltDeg * dx / w : 0;

/// Opacity of the sideways action hint.
double feedHintOpacity(double dx, TuningPhone ph) => math.min(1, dx.abs() / ph.swipePx);

// ---------- pager

/// Marks a child (the "Jedu" button) whose touches never start a feed drag.
class FeedNoDrag extends StatelessWidget {
  const FeedNoDrag({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    // Child listeners see the pointer before the pager's own listener.
    onPointerDown: (e) => context.findAncestorStateOfType<_FeedPagerState>()?._ignored.add(e.pointer),
    child: child,
  );
}

/// TikTok-like vertical strip of pages (previous card, current card, next card or feedDone):
/// dragging only changes transforms; the pages are rebuilt only when [state] changes.
class FeedPager extends StatefulWidget {
  const FeedPager({
    super.key,
    required this.state,
    required this.tuning,
    required this.onAction,
    required this.card,
    required this.done,
    required this.goLabel,
    required this.lessLabel,
  });

  final FeedState state;
  final TuningPhone tuning;
  final void Function(FeedOp op) onAction;
  final Widget Function(FeedState s, int at) card;
  final Widget Function() done;
  final String goLabel, lessLabel;

  @override
  State<FeedPager> createState() => _FeedPagerState();
}

class _FeedPagerState extends State<FeedPager> with SingleTickerProviderStateMixin {
  late final _snap = AnimationController(vsync: this);

  /// Strip offset (y) and sideways card offset (x).
  final _offset = ValueNotifier(Offset.zero);
  final _ignored = <int>{};
  int? _pointer;
  Offset _start = Offset.zero;
  FeedAxis? _axis;
  double _d = 0;
  final _samples = <({double t, double p})>[];
  Duration _lastTap = const Duration(days: -1);
  FeedState? _builtFor;
  List<Widget> _pages = const [];
  Size _size = Size.zero;

  TuningPhone get _ph => widget.tuning;
  bool get _hasNext => !widget.state.over && widget.state.card != null;
  bool get _hasPrev => _hasNext && widget.state.at > 0;
  bool get _busy => _snap.isAnimating;

  @override
  void didUpdateWidget(FeedPager old) {
    super.didUpdateWidget(old);
    if (!identical(old.state, widget.state)) {
      // The committed page is now the current one: re-centre without a jump.
      _snap.stop();
      _offset.value = Offset.zero;
    }
  }

  @override
  void dispose() {
    _snap.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _tween(Offset to, [VoidCallback? done]) {
    final from = _offset.value;
    final ms = _ph.feedSnapMs;
    if (ms <= 0) {
      _offset.value = to;
      done?.call();
      return;
    }
    final anim = CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic);
    void tick() => _offset.value = Offset.lerp(from, to, anim.value)!;
    _snap
      ..duration = Duration(milliseconds: ms)
      ..value = 0;
    _snap.addListener(tick);
    _snap.forward().whenCompleteOrCancel(() {
      _snap.removeListener(tick);
      anim.dispose();
      // Stopped by a new state (didUpdateWidget) or dispose: no action.
      if (!mounted || _snap.status != AnimationStatus.completed) return;
      final before = widget.state;
      done?.call();
      // An action that changed nothing (should not happen) must not leave the strip off-centre.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(before, widget.state) && done != null) _offset.value = Offset.zero;
      });
    });
  }

  void _down(PointerDownEvent e) {
    if (_ignored.remove(e.pointer) || _busy || _pointer != null) return;
    _pointer = e.pointer;
    _start = e.localPosition;
    _axis = null;
    _d = 0;
    _samples.clear();
  }

  void _track(PointerEvent e) {
    final dx = e.localPosition.dx - _start.dx, dy = e.localPosition.dy - _start.dy;
    _axis ??= feedLockAxis(dx, dy, _ph.feedAxisLockPx);
    final axis = _axis;
    if (axis == null) return;
    _d = axis == FeedAxis.vertical ? dy : dx;
    final t = e.timeStamp.inMicroseconds / 1000;
    _samples.add((t: t, p: _d));
    while (_samples.length > 2 && _samples[1].t < t - _ph.feedVelocityMs) {
      _samples.removeAt(0);
    }
    if (axis == FeedAxis.vertical) {
      _offset.value = Offset(0, feedStripOffset(_d, _hasPrev, _hasNext, _ph));
    } else if (_hasNext) {
      _offset.value = Offset(_d, 0);
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer == _pointer) _track(e);
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _track(e);
    _pointer = null;
    final axis = _axis;
    if (axis == null) {
      // A tap: two within double_tap_ms = like.
      if (_hasNext && (e.timeStamp - _lastTap).inMilliseconds <= _ph.doubleTapMs) {
        _lastTap = const Duration(days: -1);
        widget.onAction(FeedOp.like);
      } else {
        _lastTap = e.timeStamp;
      }
      return;
    }
    final v = feedReleaseVelocity(_samples, _ph.feedVelocityMs);
    if (axis == FeedAxis.vertical) {
      final op = feedVerticalRelease(_d, v, _size.height, _hasPrev, _hasNext, _ph);
      if (op == null) return _tween(Offset.zero);
      _tween(Offset(0, op == FeedOp.next ? -_size.height : _size.height), () => widget.onAction(op));
      return;
    }
    if (!_hasNext) return;
    final op = feedSideRelease(_d, v, _ph);
    if (op == null) return _tween(Offset.zero);
    _tween(Offset((op == FeedOp.accept ? 1 : -1) * _size.width * 1.5, 0), () => widget.onAction(op));
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_axis != null) _tween(Offset.zero);
  }

  /// The three neighbouring pages, rebuilt only for a new state: (k, page) with k = −1, 0, +1.
  List<Widget> _buildPages() {
    final s = widget.state;
    if (identical(_builtFor, s)) return _pages;
    _builtFor = s;
    final c = s.card;
    if (s.over || c == null) return _pages = [_Page(k: 0, key: const ValueKey('done'), child: widget.done())];
    return _pages = [
      if (s.at > 0) _Page(k: -1, key: ValueKey(s.at - 1), child: widget.card(s, s.at - 1)),
      _Page(
        k: 0,
        key: ValueKey(s.at),
        current: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.card(s, s.at),
            _Hint(label: widget.goLabel, go: true),
            _Hint(label: widget.lessLabel, go: false),
          ],
        ),
      ),
      if (s.at + 1 < s.deck.length)
        _Page(k: 1, key: ValueKey(s.at + 1), child: widget.card(s, s.at + 1))
      else
        _Page(k: 1, key: const ValueKey('done'), child: widget.done()),
    ];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _size = box.biggest;
      final pages = _buildPages();
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: ClipRect(
          child: _FeedOffset(
            offset: _offset,
            size: _size,
            tuning: _ph,
            child: Stack(fit: StackFit.expand, children: pages),
          ),
        ),
      );
    },
  );
}

/// Shares the drag offset with the pages without rebuilding them.
class _FeedOffset extends InheritedWidget {
  const _FeedOffset({required this.offset, required this.size, required this.tuning, required super.child});
  final ValueNotifier<Offset> offset;
  final Size size;
  final TuningPhone tuning;

  static _FeedOffset of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_FeedOffset>()!;

  @override
  bool updateShouldNotify(_FeedOffset old) => old.offset != offset || old.size != size || old.tuning != tuning;
}

/// One page of the strip at k × height; the current page also follows sideways drags.
class _Page extends StatelessWidget {
  const _Page({super.key, required this.k, required this.child, this.current = false});
  final int k;
  final bool current;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final f = _FeedOffset.of(context);
    final content = RepaintBoundary(child: child);
    return ValueListenableBuilder<Offset>(
      valueListenable: f.offset,
      child: content,
      builder: (context, o, content) {
        final y = k * f.size.height + o.dy;
        Widget w = content!;
        if (current && o.dx != 0) {
          w = Transform.translate(
            offset: Offset(o.dx, 0),
            child: Transform.rotate(
              angle: feedTiltDeg(o.dx, f.size.width, f.tuning) * math.pi / 180,
              alignment: Alignment.bottomCenter,
              child: w,
            ),
          );
        }
        return Transform.translate(offset: Offset(0, y), child: w);
      },
    );
  }
}

/// Sideways action hint on the current card, faded in by the drag.
class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.go});
  final String label;
  final bool go;

  @override
  Widget build(BuildContext context) {
    final f = _FeedOffset.of(context);
    return Positioned(
      top: Tokens.spaceXl,
      left: go ? Tokens.spaceLg : null,
      right: go ? null : Tokens.spaceLg,
      child: IgnorePointer(
        child: ValueListenableBuilder<Offset>(
          valueListenable: f.offset,
          builder: (context, o, child) =>
              Opacity(opacity: (go ? o.dx > 0 : o.dx < 0) ? feedHintOpacity(o.dx, f.tuning) : 0, child: child),
          child: Transform.rotate(
            angle: (go ? -12 : 12) * math.pi / 180,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceXs),
              decoration: BoxDecoration(
                color: Color(go ? Tokens.colorPhoneGo : Tokens.colorPhoneAppOff),
                borderRadius: BorderRadius.circular(Tokens.radiusPill),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(Tokens.colorUiText),
                  fontSize: Tokens.fontSpeed,
                  fontWeight: FontWeight.w800,
                ),
              ),
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

/// The host (specs/phone.md, specs/art.md): the bust `<id>_bust.png` of the current city (v4:
/// `npc/<city>/` first, then the shared `npc/`) anchored at the bottom, about [hostBustHeight] of
/// the card tall; without the file a soft silhouette (head and shoulders).
class _HostPortrait extends StatelessWidget {
  const _HostPortrait({required this.id, required this.cardHeight});
  final String? id;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final silhouette = CustomPaint(painter: _HostPainter(), child: const SizedBox.expand());
    final path = id == null ? null : artIndex.bust(id!);
    if (path == null) return silhouette;
    return HostBust(path: path, height: cardHeight * hostBustHeight, fallback: silhouette);
  }
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
