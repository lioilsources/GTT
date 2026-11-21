import 'package:archive/archive.dart';
import 'dart:typed_data';

import 'package:shared_gen/citypack_pb.dart' as pb;

/// Where citypack files come from (app assets now, a CDN download later).
abstract class PackSource {
  Future<Uint8List> read(String path);
}

/// Every citypack file is gzip-compressed protobuf.
Uint8List gunzip(Uint8List bytes) => const GZipDecoder().decodeBytes(bytes);

pb.Manifest decodeManifest(Uint8List gz) => pb.Manifest.fromBuffer(gunzip(gz));
pb.Graph decodeGraph(Uint8List gz) => pb.Graph.fromBuffer(gunzip(gz));
pb.Landmarks decodeLandmarks(Uint8List gz) => pb.Landmarks.fromBuffer(gunzip(gz));
pb.Spots decodeSpots(Uint8List gz) => pb.Spots.fromBuffer(gunzip(gz));
pb.Chunk decodeChunk(Uint8List gz) => pb.Chunk.fromBuffer(gunzip(gz));

String chunkPath(int x, int y) => 'chunks/${x}_$y.pb';
