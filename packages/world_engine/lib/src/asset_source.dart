import 'package:flutter/services.dart';

import 'citypack.dart';

/// Reads a citypack bundled as Flutter assets.
class AssetPackSource implements PackSource {
  AssetPackSource(this.root, {AssetBundle? bundle}) : bundle = bundle ?? rootBundle;

  /// e.g. `assets/cities/nyc/`
  final String root;
  final AssetBundle bundle;

  @override
  Future<Uint8List> read(String path) async {
    final data = await bundle.load('$root$path');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
