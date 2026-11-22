import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_gen/shared_gen.dart';

/// Start city (specs/cities.md "Výchozí město"), first valid wins: the parameter (null on F), the
/// last city, the first bundled city.
CityId pickStartCity(String? param, String? last, List<CityId> bundled) {
  CityId? known(String? id) => id == null ? null : bundled.where((c) => c.id == id).firstOrNull;
  return known(param) ?? known(last) ?? bundled.first;
}

/// The city id of a `city.json` text (`{"city": "<id>"}`), or null when it cannot be read.
String? parseLastCity(String text) {
  try {
    final j = jsonDecode(text);
    final c = j is Map ? j['city'] : null;
    return c is String ? c : null;
  } catch (_) {
    return null;
  }
}

/// Where the last played city is kept (F: `city.json` in the app documents directory).
abstract class CityStore {
  /// The raw city id, or null when there is none or it cannot be read.
  Future<String?> read();
  Future<void> write(String cityId);
}

class FileCityStore implements CityStore {
  FileCityStore([Future<Directory> Function()? dir]) : _dir = dir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _dir;

  Future<File> _file() async => File('${(await _dir()).path}/city.json');

  @override
  Future<String?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return parseLastCity(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String cityId) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'city': cityId}), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

/// In-memory store for tests.
class MemoryCityStore implements CityStore {
  String? city;

  @override
  Future<String?> read() async => city;

  @override
  Future<void> write(String cityId) async => city = cityId;
}

/// The data side of a city switch (specs/cities.md "Aplikace Cesty"): the current city is saved the
/// same way as on pause before the next city loads its own save; the caller then replaces the screen.
Future<void> switchCity(CityId from, CityId to, {required Future<void> Function() saveCurrent}) async {
  if (from == to) return;
  await saveCurrent();
}
