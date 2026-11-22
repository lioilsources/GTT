import 'package:flutter/services.dart';
import 'package:game_loop/game_loop.dart';
import 'package:meta_progress/meta_progress.dart';
import 'package:world_engine/world_engine.dart';

import '../game/metropole_game.dart' show GameAssets;
import '../loop/save_store.dart';
import '../ui/passport.dart' show passportCityOfPack;

/// Passport completion of a city from its save (specs/cities.md "Aplikace Cesty"): the save holds
/// only stamps, the catalog comes from that city's small pack files. No save = 0 %.
Future<int> cityPassportPercent(CityId city, SaveStore saves, Tuning tuning, {AssetBundle? bundle}) async {
  final raw = await saves.read(city.id);
  if (raw == null) return 0;
  final cfg = SaveConfig.fromTuning(tuning, city.id, CarId.values.map((c) => c.id));
  final stamps = saveOf(normalizeSave(cfg, raw)).stamps;
  if (stamps.isEmpty) return 0;
  final src = AssetPackSource('${GameAssets.shared}packs/${city.id}/', bundle: bundle);
  final f = await Future.wait([src.read('manifest.pb'), src.read('landmarks.pb'), src.read('spots.pb')]);
  final catalog = passportCityOfPack(decodeManifest(f[0]), decodeLandmarks(f[1]), decodeSpots(f[2]));
  return PassportTracker(catalog, tuning.passport, stamps).result.percent;
}
