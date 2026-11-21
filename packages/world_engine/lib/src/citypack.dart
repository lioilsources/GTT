import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import 'pb/citypack.pb.dart' as pb;

/// Where citypack files come from (app assets now, a CDN download later).
abstract class PackSource {
  Future<Uint8List> read(String path);
}

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

/// Every citypack file is gzip-compressed protobuf.
Uint8List gunzip(Uint8List bytes) => const GZipDecoder().decodeBytes(bytes);

pb.Manifest decodeManifest(Uint8List gz) => pb.Manifest.fromBuffer(gunzip(gz));
pb.Graph decodeGraph(Uint8List gz) => pb.Graph.fromBuffer(gunzip(gz));
pb.Landmarks decodeLandmarks(Uint8List gz) => pb.Landmarks.fromBuffer(gunzip(gz));
pb.Spots decodeSpots(Uint8List gz) => pb.Spots.fromBuffer(gunzip(gz));
pb.Chunk decodeChunk(Uint8List gz) => pb.Chunk.fromBuffer(gunzip(gz));

String chunkPath(int x, int y) => 'chunks/${x}_$y.pb';
