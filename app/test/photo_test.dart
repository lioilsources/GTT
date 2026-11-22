import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:metropole/game/metropole_game.dart';
import 'package:metropole/game/pause.dart';
import 'package:metropole/loop/loop_controller.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:metropole/phone/phone_controller.dart';
import 'package:metropole/phone/phone_sheet.dart';
import 'package:metropole/photo/photo_controller.dart';
import 'package:world_engine/world_engine.dart';

// Port of web/test/photo.test.ts, the client part (specs/photo.md P1): the CameraRig inverse and the
// whole Camera feature in the NYC pack (button, phone app, framing mode, shots, Passport, save).

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

class _MemStore implements SaveStore {
  final Map<String, Map<String, Object?>> saves = {};
  int writes = 0;
  @override
  Future<Object?> read(String cityId) async => saves[cityId];
  @override
  Future<void> write(String cityId, Map<String, Object?> save) async {
    writes++;
    saves[cityId] = save;
  }
}

typedef _W = ({MetropoleGame g, PhoneController phone, LoopController loop, PhotoController photo, _MemStore store});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());

  test('screenToWorld inverts CameraRig.toScreen; rigForCentre puts a point mid-screen', () {
    final rig = CameraRig()
      ..x = 120
      ..y = -40
      ..heading = 1.1
      ..viewWidth = 180;
    const size = Size(400, 800);
    RigPose pose() => (x: rig.x, y: rig.y, heading: rig.heading, viewWidth: rig.viewWidth);
    for (final (x, y) in [(0.0, 0.0), (130.0, -20.0), (-300.0, 250.0)]) {
      final s = rig.toScreen(x, y, size, tuning);
      final back = screenToWorld(pose(), s.dx, s.dy, size.width, size.height, tuning);
      expect(back.x, closeTo(x, 1e-6));
      expect(back.y, closeTo(y, 1e-6));
    }
    final at = rigForCentre(55, 66, rig.heading, rig.viewWidth, size.width, size.height, tuning);
    rig
      ..x = at.x
      ..y = at.y;
    final c = rig.toScreen(55, 66, size, tuning);
    expect(c.dx, closeTo(200, 1e-6));
    expect(c.dy, closeTo(400, 1e-6));
  });

  test('the Camera app sits in the phone grid (slot camera)', () {
    expect(PhoneAppId.values.map((a) => a.name), contains('camera'));
  });

  group('photo spots and the Camera in the game (NYC pack)', () {
    const root = '../build/packs/nyc/';
    final has = File('${root}manifest.pb').existsSync();
    late GameAssets assets;
    setUpAll(() async {
      if (!has) return;
      await initializeForge2D();
      final src = _FilePack(root);
      final cars = {
        for (final f in Directory('../content/cars').listSync().whereType<File>())
          for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
      };
      assets = GameAssets(
        city: await City.load(src),
        source: src,
        tuning: tuning,
        car: cars[tuning.cars.startCar]!,
        cars: cars,
        textures: await FacadeTextures.create(),
      );
    });

    Future<_W> start({Object? saved}) async {
      final g = MetropoleGame(assets)..onGameResize(Vector2(400, 800));
      await g.preload();
      final phone = PhoneController(g, feedSeed: 1);
      final store = _MemStore();
      final loop = LoopController(
        g,
        phone,
        store: store,
        npc: null,
        saved: saved,
        settingsGet: () => (scheme: 'a', night: false),
        settingsSet: (_) {},
      );
      final photo = PhotoController(g, phone, loop);
      return (g: g, phone: phone, loop: loop, photo: photo, store: store);
    }

    void stop(_W w) {
      w.photo.dispose();
      w.loop.dispose();
      w.phone.dispose();
      w.g.onRemove();
    }

    void park(MetropoleGame g, PhotoPoint p) {
      g.drive.spawn(p.x, p.y, p.heading);
      g.camera.snap(p.x, p.y, p.heading, tuning);
    }

    /// Real frames through the game (paused or not), enough for the glide.
    void frames(MetropoleGame g, double seconds) {
      for (var t = 0.0; t < seconds + 0.1; t += 1 / 30) {
        g.update(1 / 30);
      }
    }

    test('photo spots from the pack; the Passport catalog photo = their ids in spots.pb order', () async {
      final w = await start();
      final pts = w.photo.points;
      expect(pts, isNotEmpty);
      expect(w.g.passport.state.catalog['photo'], [
        for (final s in w.g.city.spots.items)
          if (s.kind == 'photo') s.id,
      ]);
      expect(w.g.passport.photoNames[pts.first.id], pts.first.name);
      expect(phoneApps.containsKey(PhoneAppId.camera), isTrue);
      final dots = w.phone.mapPoints.expand((f) => f()).where((e) => e.color == Tokens.colorPhotoSpot);
      expect(dots.length, pts.length);
      stop(w);
      expect(phoneApps.containsKey(PhoneAppId.camera), isFalse);
    }, skip: !has);

    test('"Foťák" at a photo spot takes over "Hrát" and the car button; not while wanted', () async {
      final w = await start();
      final p = w.photo.points.first;
      park(w.g, p);
      w.photo.tick();
      expect(w.photo.openable.value, isTrue);
      expect(w.loop.yieldTo!(), isTrue);
      expect(w.g.carActionYield!(), isTrue);
      // Wanted: no button, the app says why.
      w.g.police.state.level = 1;
      w.photo.tick();
      expect(w.photo.openable.value, isFalse);
      expect(w.photo.appOpen(), MessageKey.photoWanted);
      w.g.police.state.level = 0;
      // The phone open hides the button.
      w.phone.open();
      w.photo.tick();
      expect(w.photo.openable.value, isFalse);
      w.phone.close();
      // Away from every photo spot: nothing, the app shows photoNoSpot.
      w.g.drive.spawn(p.x + 500, p.y + 500, 0);
      w.photo.tick();
      expect(w.photo.openable.value, isFalse);
      expect(w.loop.yieldTo!(), isFalse);
      expect(w.photo.appOpen(), MessageKey.photoNoSpot);
      stop(w);
    }, skip: !has);

    test('framing: pause kind photo, glide to the midpoint view, cut, ok (stamp, save, close), glide back', () async {
      final w = await start();
      final g = w.g, photo = w.photo, p = photo.points.first;
      park(g, p);
      final heading = g.camera.heading;
      expect(photo.tryOpen(), isTrue);
      expect(photo.active, isTrue);
      expect(g.pauseOverlays.isOpen(GameOverlay.photo), isTrue);
      expect(g.worldPaused, isTrue);
      frames(g, tuning.photo.zoomS);
      // The car–look midpoint is mid-screen, heading unchanged, the framing width.
      final c = g.drive.car, size = g.viewSize;
      final mid = g.camera.toScreen((c.x + p.lookX) / 2, (c.y + p.lookY) / 2, size, tuning);
      expect(mid.dx, closeTo(size.width / 2, 1e-6));
      expect(mid.dy, closeTo(size.height / 2, 1e-6));
      expect(g.camera.heading, heading);
      expect(g.camera.viewWidth, closeTo(photoViewWidth(tuning, p.subjectM), 1e-9));

      // A tap = 1 dm frame → cut; the mode stays.
      expect(photo.shoot(10, 10, 10, 10), 'cut');
      expect(photo.toast.value?.key, MessageKey.photoCut);
      expect(photo.active, isTrue);
      expect(photo.flashS, 0);
      // The whole screen on the view: loose when the view is small, never ok for a tight limit.
      // A frame on the look at 1.2 × the view radius fits.
      final look = g.camera.toScreen(p.lookX, p.lookY, size, tuning);
      final r = p.subjectM * g.camera.pixelsPerMetre(size) * 1.2;
      photo.dragStart(1, look.dx - r, look.dy - r);
      photo.dragMove(1, look.dx + r, look.dy + r);
      expect(photo.mode!.drag, isNotNull);
      final writes = w.store.writes;
      expect(photo.dragEnd(1, look.dx + r, look.dy + r), 'ok');
      expect(photo.toast.value, (key: MessageKey.photoTaken, name: p.name));
      expect(g.passport.has('photo', p.id), isTrue);
      expect(photo.world!.isTaken(p.id), isTrue);
      expect(photo.flashS, tuning.photo.flashS);
      expect(photo.active, isFalse);
      expect(g.worldPaused, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(w.store.writes, writes + 1);
      expect(w.store.saves['nyc']!['stamps'], contains('photo:${p.id}'));
      // Glide back to the car at the slow view width, then the rig follows again.
      expect(g.cameraHook!(tuning.photo.zoomS), isTrue);
      expect(photo.flashS, 0);
      expect(g.camera.viewWidth, closeTo(tuning.viewWidthM.slow, 1e-6));
      expect((g.camera.x, g.camera.y), (g.drive.car.x, g.drive.car.y));
      expect(g.cameraHook!(0), isFalse);

      // Again: flash and photoAgain, no new stamp; "Zpět" closes without a shot.
      final stamps = g.passport.stamps.length;
      expect(photo.tryOpen(), isTrue);
      frames(g, tuning.photo.zoomS);
      final look2 = g.camera.toScreen(p.lookX, p.lookY, size, tuning);
      expect(photo.shoot(look2.dx - r, look2.dy - r, look2.dx + r, look2.dy + r), 'again');
      expect(photo.toast.value?.key, MessageKey.photoAgain);
      expect(photo.flashS, greaterThan(0));
      expect(photo.active, isTrue);
      expect(g.passport.stamps.length, stamps);
      photo.close();
      expect(photo.active, isFalse);
      expect(g.pauseOverlays.isOpen(GameOverlay.photo), isFalse);

      // The photo module comes back from the Passport stamps of the save.
      final saved = w.store.saves['nyc'];
      stop(w);
      final again = await start(saved: saved);
      expect(again.photo.world!.state.taken, [p.id]);
      stop(again);
    }, skip: !has);

    test('a loose frame and the phone app opening the mode (the phone closes, back to home)', () async {
      final w = await start();
      final g = w.g, photo = w.photo, p = photo.points.first;
      park(g, p);
      w.phone.open(PhoneAppId.camera);
      expect(photo.appOpen(), isNull);
      // Tests pump no frames: open as the scheduled post-frame callback does (a second call is a no-op).
      photo.open(p);
      expect(photo.active, isTrue);
      expect(w.phone.isOpen, isFalse);
      expect(w.phone.app, isNull);
      frames(g, tuning.photo.zoomS);
      final look = g.camera.toScreen(p.lookX, p.lookY, g.viewSize, tuning);
      final ppm = g.camera.pixelsPerMetre(g.viewSize);
      final r = p.subjectM * ppm * (tuning.photo.loosePct / 100 + 0.5);
      expect(photo.shoot(look.dx - r, look.dy - r, look.dx + r, look.dy + r), 'loose');
      expect(photo.toast.value?.key, MessageKey.photoLoose);
      expect(photo.flashS, 0);
      expect(photo.active, isTrue);
      expect(g.passport.has('photo', p.id), isFalse);
      photo.close();
      stop(w);
    }, skip: !has);
  });
}
