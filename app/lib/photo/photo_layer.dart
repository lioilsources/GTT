import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../phone/phone_sheet.dart' show phoneText;
import 'photo_controller.dart';

/// Camera HUD over the world (specs/photo.md): the "Foťák" context button (in the place of "Hrát",
/// which yields to it), the verdict toast and, while framing, the drag surface with the hint and
/// "Zpět". Fills the game area so drag positions are game screen pixels.
class PhotoLayer extends StatelessWidget {
  const PhotoLayer({super.key, required this.photo});
  final PhotoController photo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([photo, photo.openable, photo.toast]),
    builder: (context, _) {
      final m = photo.mode;
      final toast = photo.toast.value;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (m != null)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => photo.dragStart(e.pointer, e.localPosition.dx, e.localPosition.dy),
                onPointerMove: (e) => photo.dragMove(e.pointer, e.localPosition.dx, e.localPosition.dy),
                onPointerUp: (e) => photo.dragEnd(e.pointer, e.localPosition.dx, e.localPosition.dy),
                onPointerCancel: (e) => photo.dragCancel(e.pointer),
              ),
            ),
          SafeArea(
            child: Stack(
              children: [
                if (m != null)
                  Positioned(
                    top: Tokens.spaceLg,
                    left: Tokens.spaceMd,
                    right: Tokens.spaceMd,
                    child: IgnorePointer(
                      child: Center(
                        child: _Pill(
                          key: const Key('photo-hint'),
                          text: phoneText(context, MessageKey.photoHint, {'name': m.point.name}),
                        ),
                      ),
                    ),
                  ),
                if (m != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96,
                    child: Center(
                      child: FilledButton(
                        key: const Key('photo-back'),
                        onPressed: photo.close,
                        child: Text(phoneText(context, MessageKey.photoClose)),
                      ),
                    ),
                  ),
                if (m == null && photo.openable.value)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 148,
                    child: Center(
                      child: FilledButton.icon(
                        key: const Key('photo-open'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(Tokens.colorPhotoSpot),
                          foregroundColor: const Color(Tokens.colorUiText),
                        ),
                        icon: const Icon(Icons.photo_camera, size: 18),
                        onPressed: photo.tryOpen,
                        label: Text(phoneText(context, MessageKey.photoOpen)),
                      ),
                    ),
                  ),
                if (toast != null)
                  Align(
                    alignment: const Alignment(0, -0.55),
                    child: IgnorePointer(
                      child: _Pill(text: phoneText(context, toast.key, {'name': toast.name})),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text});
  final String text;

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
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontHudSmall),
      ),
    ),
  );
}

/// The Camera phone app (slot `camera`): opens the framing mode at a photo spot, otherwise says why
/// not (photoNoSpot / photoWanted).
class CameraAppScreen extends StatefulWidget {
  const CameraAppScreen({super.key, required this.photo});
  final PhotoController photo;

  @override
  State<CameraAppScreen> createState() => _CameraAppScreenState();
}

class _CameraAppScreenState extends State<CameraAppScreen> {
  late final MessageKey? _why = widget.photo.appOpen();

  @override
  Widget build(BuildContext context) {
    final why = _why;
    if (why == null) return const SizedBox.expand();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.spaceLg),
        child: Text(
          phoneText(context, why),
          key: const Key('photo-app-why'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(Tokens.colorUiText)),
        ),
      ),
    );
  }
}
