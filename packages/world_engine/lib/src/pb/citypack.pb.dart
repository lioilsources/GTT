// This is a generated file - do not edit.
//
// Generated from citypack.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'citypack.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'citypack.pbenum.dart';

/// manifest.pb
class Manifest extends $pb.GeneratedMessage {
  factory Manifest({
    $core.int? formatVersion,
    $core.String? cityId,
    $core.String? name,
    $core.double? originLat,
    $core.double? originLon,
    $core.String? driveSide,
    $core.String? units,
    $core.String? overtureRelease,
    $core.int? chunkM,
    Rect? bounds,
    $core.Iterable<$core.int>? area,
    $core.Iterable<ChunkRef>? chunks,
    Spawn? start,
    $core.Iterable<District>? districts,
    $core.Iterable<$core.String>? attribution,
    $core.String? builtAt,
  }) {
    final result = Manifest._();
    if (formatVersion != null) result.formatVersion = formatVersion;
    if (cityId != null) result.cityId = cityId;
    if (name != null) result.name = name;
    if (originLat != null) result.originLat = originLat;
    if (originLon != null) result.originLon = originLon;
    if (driveSide != null) result.driveSide = driveSide;
    if (units != null) result.units = units;
    if (overtureRelease != null) result.overtureRelease = overtureRelease;
    if (chunkM != null) result.chunkM = chunkM;
    if (bounds != null) result.bounds = bounds;
    if (area != null) result.area.addAll(area);
    if (chunks != null) result.chunks.addAll(chunks);
    if (start != null) result.start = start;
    if (districts != null) result.districts.addAll(districts);
    if (attribution != null) result.attribution.addAll(attribution);
    if (builtAt != null) result.builtAt = builtAt;
    return result;
  }

  Manifest._();

  factory Manifest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Manifest()..mergeFromBuffer(data, registry);
  factory Manifest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Manifest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Manifest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Manifest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'formatVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'cityId')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aD(4, _omitFieldNames ? '' : 'originLat')
    ..aD(5, _omitFieldNames ? '' : 'originLon')
    ..aOS(6, _omitFieldNames ? '' : 'driveSide')
    ..aOS(7, _omitFieldNames ? '' : 'units')
    ..aOS(8, _omitFieldNames ? '' : 'overtureRelease')
    ..aI(9, _omitFieldNames ? '' : 'chunkM', fieldType: $pb.PbFieldType.OU3)
    ..aOM<Rect>(10, _omitFieldNames ? '' : 'bounds',
        subBuilder: Rect.$_createMessage)
    ..p<$core.int>(11, _omitFieldNames ? '' : 'area', $pb.PbFieldType.KS3)
    ..pPM<ChunkRef>(12, _omitFieldNames ? '' : 'chunks',
        subBuilder: ChunkRef.$_createMessage)
    ..aOM<Spawn>(13, _omitFieldNames ? '' : 'start',
        subBuilder: Spawn.$_createMessage)
    ..pPM<District>(14, _omitFieldNames ? '' : 'districts',
        subBuilder: District.$_createMessage)
    ..pPS(15, _omitFieldNames ? '' : 'attribution')
    ..aOS(16, _omitFieldNames ? '' : 'builtAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Manifest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Manifest copyWith(void Function(Manifest) updates) =>
      super.copyWith((message) => updates(message as Manifest)) as Manifest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Manifest() / Manifest.new instead')
  static Manifest create() => Manifest._();
  static $pb.GeneratedMessage $_createMessage() => Manifest._();
  @$core.override
  Manifest createEmptyInstance() => Manifest._();
  @$core.pragma('dart2js:noInline')
  static Manifest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Manifest>(Manifest.$_createMessage);
  static Manifest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get formatVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set formatVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFormatVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormatVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get cityId => $_getSZ(1);
  @$pb.TagNumber(2)
  set cityId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCityId() => $_has(1);
  @$pb.TagNumber(2)
  void clearCityId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get originLat => $_getN(3);
  @$pb.TagNumber(4)
  set originLat($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOriginLat() => $_has(3);
  @$pb.TagNumber(4)
  void clearOriginLat() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get originLon => $_getN(4);
  @$pb.TagNumber(5)
  set originLon($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOriginLon() => $_has(4);
  @$pb.TagNumber(5)
  void clearOriginLon() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get driveSide => $_getSZ(5);
  @$pb.TagNumber(6)
  set driveSide($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDriveSide() => $_has(5);
  @$pb.TagNumber(6)
  void clearDriveSide() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get units => $_getSZ(6);
  @$pb.TagNumber(7)
  set units($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasUnits() => $_has(6);
  @$pb.TagNumber(7)
  void clearUnits() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get overtureRelease => $_getSZ(7);
  @$pb.TagNumber(8)
  set overtureRelease($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasOvertureRelease() => $_has(7);
  @$pb.TagNumber(8)
  void clearOvertureRelease() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get chunkM => $_getIZ(8);
  @$pb.TagNumber(9)
  set chunkM($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasChunkM() => $_has(8);
  @$pb.TagNumber(9)
  void clearChunkM() => $_clearField(9);

  @$pb.TagNumber(10)
  Rect get bounds => $_getN(9);
  @$pb.TagNumber(10)
  set bounds(Rect value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasBounds() => $_has(9);
  @$pb.TagNumber(10)
  void clearBounds() => $_clearField(10);
  @$pb.TagNumber(10)
  Rect ensureBounds() => $_ensure(9);

  @$pb.TagNumber(11)
  $pb.PbList<$core.int> get area => $_getList(10);

  @$pb.TagNumber(12)
  $pb.PbList<ChunkRef> get chunks => $_getList(11);

  @$pb.TagNumber(13)
  Spawn get start => $_getN(12);
  @$pb.TagNumber(13)
  set start(Spawn value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasStart() => $_has(12);
  @$pb.TagNumber(13)
  void clearStart() => $_clearField(13);
  @$pb.TagNumber(13)
  Spawn ensureStart() => $_ensure(12);

  @$pb.TagNumber(14)
  $pb.PbList<District> get districts => $_getList(13);

  @$pb.TagNumber(15)
  $pb.PbList<$core.String> get attribution => $_getList(14);

  @$pb.TagNumber(16)
  $core.String get builtAt => $_getSZ(15);
  @$pb.TagNumber(16)
  set builtAt($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasBuiltAt() => $_has(15);
  @$pb.TagNumber(16)
  void clearBuiltAt() => $_clearField(16);
}

class Rect extends $pb.GeneratedMessage {
  factory Rect({
    $core.int? minX,
    $core.int? minY,
    $core.int? maxX,
    $core.int? maxY,
  }) {
    final result = Rect._();
    if (minX != null) result.minX = minX;
    if (minY != null) result.minY = minY;
    if (maxX != null) result.maxX = maxX;
    if (maxY != null) result.maxY = maxY;
    return result;
  }

  Rect._();

  factory Rect.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Rect()..mergeFromBuffer(data, registry);
  factory Rect.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Rect()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Rect',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Rect.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'minX', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'minY', fieldType: $pb.PbFieldType.OS3)
    ..aI(3, _omitFieldNames ? '' : 'maxX', fieldType: $pb.PbFieldType.OS3)
    ..aI(4, _omitFieldNames ? '' : 'maxY', fieldType: $pb.PbFieldType.OS3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Rect clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Rect copyWith(void Function(Rect) updates) =>
      super.copyWith((message) => updates(message as Rect)) as Rect;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Rect() / Rect.new instead')
  static Rect create() => Rect._();
  static $pb.GeneratedMessage $_createMessage() => Rect._();
  @$core.override
  Rect createEmptyInstance() => Rect._();
  @$core.pragma('dart2js:noInline')
  static Rect getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Rect>(Rect.$_createMessage);
  static Rect? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get minX => $_getIZ(0);
  @$pb.TagNumber(1)
  set minX($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMinX() => $_has(0);
  @$pb.TagNumber(1)
  void clearMinX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get minY => $_getIZ(1);
  @$pb.TagNumber(2)
  set minY($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinY() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxX => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxX($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxX() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxX() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxY => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxY($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxY() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxY() => $_clearField(4);
}

/// Chunk (x, y) covers [x*chunk_m, (x+1)*chunk_m) × [y*chunk_m, (y+1)*chunk_m) in metres.
class ChunkRef extends $pb.GeneratedMessage {
  factory ChunkRef({
    $core.int? x,
    $core.int? y,
    $core.int? bytes,
    $core.int? buildings,
  }) {
    final result = ChunkRef._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (bytes != null) result.bytes = bytes;
    if (buildings != null) result.buildings = buildings;
    return result;
  }

  ChunkRef._();

  factory ChunkRef.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChunkRef()..mergeFromBuffer(data, registry);
  factory ChunkRef.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChunkRef()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChunkRef',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: ChunkRef.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OS3)
    ..aI(3, _omitFieldNames ? '' : 'bytes', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'buildings', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChunkRef clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChunkRef copyWith(void Function(ChunkRef) updates) =>
      super.copyWith((message) => updates(message as ChunkRef)) as ChunkRef;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChunkRef() / ChunkRef.new instead')
  static ChunkRef create() => ChunkRef._();
  static $pb.GeneratedMessage $_createMessage() => ChunkRef._();
  @$core.override
  ChunkRef createEmptyInstance() => ChunkRef._();
  @$core.pragma('dart2js:noInline')
  static ChunkRef getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChunkRef>(ChunkRef.$_createMessage);
  static ChunkRef? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get x => $_getIZ(0);
  @$pb.TagNumber(1)
  set x($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get y => $_getIZ(1);
  @$pb.TagNumber(2)
  set y($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get bytes => $_getIZ(2);
  @$pb.TagNumber(3)
  set bytes($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get buildings => $_getIZ(3);
  @$pb.TagNumber(4)
  set buildings($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBuildings() => $_has(3);
  @$pb.TagNumber(4)
  void clearBuildings() => $_clearField(4);
}

class Spawn extends $pb.GeneratedMessage {
  factory Spawn({
    $core.int? x,
    $core.int? y,
    $core.double? headingRad,
  }) {
    final result = Spawn._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (headingRad != null) result.headingRad = headingRad;
    return result;
  }

  Spawn._();

  factory Spawn.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Spawn()..mergeFromBuffer(data, registry);
  factory Spawn.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Spawn()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Spawn',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Spawn.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OS3)
    ..aD(3, _omitFieldNames ? '' : 'headingRad', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Spawn clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Spawn copyWith(void Function(Spawn) updates) =>
      super.copyWith((message) => updates(message as Spawn)) as Spawn;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Spawn() / Spawn.new instead')
  static Spawn create() => Spawn._();
  static $pb.GeneratedMessage $_createMessage() => Spawn._();
  @$core.override
  Spawn createEmptyInstance() => Spawn._();
  @$core.pragma('dart2js:noInline')
  static Spawn getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Spawn>(Spawn.$_createMessage);
  static Spawn? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get x => $_getIZ(0);
  @$pb.TagNumber(1)
  set x($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get y => $_getIZ(1);
  @$pb.TagNumber(2)
  set y($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get headingRad => $_getN(2);
  @$pb.TagNumber(3)
  set headingRad($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeadingRad() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeadingRad() => $_clearField(3);
}

class District extends $pb.GeneratedMessage {
  factory District({
    $core.String? name,
    $core.Iterable<$core.int>? ring,
  }) {
    final result = District._();
    if (name != null) result.name = name;
    if (ring != null) result.ring.addAll(ring);
    return result;
  }

  District._();

  factory District.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      District()..mergeFromBuffer(data, registry);
  factory District.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      District()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'District',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: District.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..p<$core.int>(2, _omitFieldNames ? '' : 'ring', $pb.PbFieldType.KS3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  District clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  District copyWith(void Function(District) updates) =>
      super.copyWith((message) => updates(message as District)) as District;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use District() / District.new instead')
  static District create() => District._();
  static $pb.GeneratedMessage $_createMessage() => District._();
  @$core.override
  District createEmptyInstance() => District._();
  @$core.pragma('dart2js:noInline')
  static District getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<District>(District.$_createMessage);
  static District? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get ring => $_getList(1);
}

/// graph.pb
class Graph extends $pb.GeneratedMessage {
  factory Graph({
    $core.Iterable<Node>? nodes,
    $core.Iterable<Edge>? edges,
    $core.Iterable<$core.String>? names,
  }) {
    final result = Graph._();
    if (nodes != null) result.nodes.addAll(nodes);
    if (edges != null) result.edges.addAll(edges);
    if (names != null) result.names.addAll(names);
    return result;
  }

  Graph._();

  factory Graph.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Graph()..mergeFromBuffer(data, registry);
  factory Graph.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Graph()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Graph',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Graph.$_createMessage)
    ..pPM<Node>(1, _omitFieldNames ? '' : 'nodes',
        subBuilder: Node.$_createMessage)
    ..pPM<Edge>(2, _omitFieldNames ? '' : 'edges',
        subBuilder: Edge.$_createMessage)
    ..pPS(3, _omitFieldNames ? '' : 'names')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Graph clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Graph copyWith(void Function(Graph) updates) =>
      super.copyWith((message) => updates(message as Graph)) as Graph;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Graph() / Graph.new instead')
  static Graph create() => Graph._();
  static $pb.GeneratedMessage $_createMessage() => Graph._();
  @$core.override
  Graph createEmptyInstance() => Graph._();
  @$core.pragma('dart2js:noInline')
  static Graph getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Graph>(Graph.$_createMessage);
  static Graph? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Node> get nodes => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<Edge> get edges => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get names => $_getList(2);
}

class Node extends $pb.GeneratedMessage {
  factory Node({
    $core.int? x,
    $core.int? y,
    $core.bool? border,
  }) {
    final result = Node._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (border != null) result.border = border;
    return result;
  }

  Node._();

  factory Node.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Node()..mergeFromBuffer(data, registry);
  factory Node.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Node()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Node',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Node.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OS3)
    ..aOB(3, _omitFieldNames ? '' : 'border')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Node clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Node copyWith(void Function(Node) updates) =>
      super.copyWith((message) => updates(message as Node)) as Node;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Node() / Node.new instead')
  static Node create() => Node._();
  static $pb.GeneratedMessage $_createMessage() => Node._();
  @$core.override
  Node createEmptyInstance() => Node._();
  @$core.pragma('dart2js:noInline')
  static Node getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Node>(Node.$_createMessage);
  static Node? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get x => $_getIZ(0);
  @$pb.TagNumber(1)
  set x($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get y => $_getIZ(1);
  @$pb.TagNumber(2)
  set y($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get border => $_getBF(2);
  @$pb.TagNumber(3)
  set border($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBorder() => $_has(2);
  @$pb.TagNumber(3)
  void clearBorder() => $_clearField(3);
}

class Edge extends $pb.GeneratedMessage {
  factory Edge({
    $core.int? from,
    $core.int? to,
    $core.Iterable<$core.int>? points,
    RoadClass? class_4,
    $core.int? name,
    $core.int? lanes,
    $core.int? oneway,
    $core.int? layerFrom,
    $core.int? layerTo,
    $core.bool? bridge,
    $core.bool? tunnel,
    $core.bool? kept,
    $core.double? widthM,
  }) {
    final result = Edge._();
    if (from != null) result.from = from;
    if (to != null) result.to = to;
    if (points != null) result.points.addAll(points);
    if (class_4 != null) result.class_4 = class_4;
    if (name != null) result.name = name;
    if (lanes != null) result.lanes = lanes;
    if (oneway != null) result.oneway = oneway;
    if (layerFrom != null) result.layerFrom = layerFrom;
    if (layerTo != null) result.layerTo = layerTo;
    if (bridge != null) result.bridge = bridge;
    if (tunnel != null) result.tunnel = tunnel;
    if (kept != null) result.kept = kept;
    if (widthM != null) result.widthM = widthM;
    return result;
  }

  Edge._();

  factory Edge.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Edge()..mergeFromBuffer(data, registry);
  factory Edge.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Edge()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Edge',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Edge.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'from', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'to', fieldType: $pb.PbFieldType.OU3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'points', $pb.PbFieldType.KS3)
    ..aE<RoadClass>(4, _omitFieldNames ? '' : 'class',
        enumValues: RoadClass.values)
    ..aI(5, _omitFieldNames ? '' : 'name', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'lanes', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'oneway', fieldType: $pb.PbFieldType.OS3)
    ..aI(8, _omitFieldNames ? '' : 'layerFrom', fieldType: $pb.PbFieldType.OS3)
    ..aI(9, _omitFieldNames ? '' : 'layerTo', fieldType: $pb.PbFieldType.OS3)
    ..aOB(10, _omitFieldNames ? '' : 'bridge')
    ..aOB(11, _omitFieldNames ? '' : 'tunnel')
    ..aOB(12, _omitFieldNames ? '' : 'kept')
    ..aD(13, _omitFieldNames ? '' : 'widthM', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Edge clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Edge copyWith(void Function(Edge) updates) =>
      super.copyWith((message) => updates(message as Edge)) as Edge;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Edge() / Edge.new instead')
  static Edge create() => Edge._();
  static $pb.GeneratedMessage $_createMessage() => Edge._();
  @$core.override
  Edge createEmptyInstance() => Edge._();
  @$core.pragma('dart2js:noInline')
  static Edge getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Edge>(Edge.$_createMessage);
  static Edge? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get from => $_getIZ(0);
  @$pb.TagNumber(1)
  set from($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrom() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get to => $_getIZ(1);
  @$pb.TagNumber(2)
  set to($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTo() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.int> get points => $_getList(2);

  @$pb.TagNumber(4)
  RoadClass get class_4 => $_getN(3);
  @$pb.TagNumber(4)
  set class_4(RoadClass value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasClass_4() => $_has(3);
  @$pb.TagNumber(4)
  void clearClass_4() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get name => $_getIZ(4);
  @$pb.TagNumber(5)
  set name($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasName() => $_has(4);
  @$pb.TagNumber(5)
  void clearName() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get lanes => $_getIZ(5);
  @$pb.TagNumber(6)
  set lanes($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLanes() => $_has(5);
  @$pb.TagNumber(6)
  void clearLanes() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get oneway => $_getIZ(6);
  @$pb.TagNumber(7)
  set oneway($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasOneway() => $_has(6);
  @$pb.TagNumber(7)
  void clearOneway() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get layerFrom => $_getIZ(7);
  @$pb.TagNumber(8)
  set layerFrom($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLayerFrom() => $_has(7);
  @$pb.TagNumber(8)
  void clearLayerFrom() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get layerTo => $_getIZ(8);
  @$pb.TagNumber(9)
  set layerTo($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLayerTo() => $_has(8);
  @$pb.TagNumber(9)
  void clearLayerTo() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get bridge => $_getBF(9);
  @$pb.TagNumber(10)
  set bridge($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasBridge() => $_has(9);
  @$pb.TagNumber(10)
  void clearBridge() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get tunnel => $_getBF(10);
  @$pb.TagNumber(11)
  set tunnel($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTunnel() => $_has(10);
  @$pb.TagNumber(11)
  void clearTunnel() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.bool get kept => $_getBF(11);
  @$pb.TagNumber(12)
  set kept($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasKept() => $_has(11);
  @$pb.TagNumber(12)
  void clearKept() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.double get widthM => $_getN(12);
  @$pb.TagNumber(13)
  set widthM($core.double value) => $_setFloat(12, value);
  @$pb.TagNumber(13)
  $core.bool hasWidthM() => $_has(12);
  @$pb.TagNumber(13)
  void clearWidthM() => $_clearField(13);
}

/// chunks/{x}_{y}.pb
class Chunk extends $pb.GeneratedMessage {
  factory Chunk({
    $core.int? x,
    $core.int? y,
    $core.Iterable<Building>? buildings,
    $core.Iterable<Mesh>? ground,
  }) {
    final result = Chunk._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (buildings != null) result.buildings.addAll(buildings);
    if (ground != null) result.ground.addAll(ground);
    return result;
  }

  Chunk._();

  factory Chunk.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Chunk()..mergeFromBuffer(data, registry);
  factory Chunk.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Chunk()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Chunk',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Chunk.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OS3)
    ..pPM<Building>(3, _omitFieldNames ? '' : 'buildings',
        subBuilder: Building.$_createMessage)
    ..pPM<Mesh>(4, _omitFieldNames ? '' : 'ground',
        subBuilder: Mesh.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Chunk clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Chunk copyWith(void Function(Chunk) updates) =>
      super.copyWith((message) => updates(message as Chunk)) as Chunk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Chunk() / Chunk.new instead')
  static Chunk create() => Chunk._();
  static $pb.GeneratedMessage $_createMessage() => Chunk._();
  @$core.override
  Chunk createEmptyInstance() => Chunk._();
  @$core.pragma('dart2js:noInline')
  static Chunk getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Chunk>(Chunk.$_createMessage);
  static Chunk? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get x => $_getIZ(0);
  @$pb.TagNumber(1)
  set x($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get y => $_getIZ(1);
  @$pb.TagNumber(2)
  set y($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<Building> get buildings => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<Mesh> get ground => $_getList(3);
}

class Building extends $pb.GeneratedMessage {
  factory Building({
    $core.Iterable<$core.int>? rings,
    $core.Iterable<$core.int>? ringEnds,
    $core.Iterable<$core.int>? roof,
    $core.double? heightM,
    $core.double? minHeightM,
    $core.int? landmark,
    $core.bool? collide,
    $core.int? wallSeed,
  }) {
    final result = Building._();
    if (rings != null) result.rings.addAll(rings);
    if (ringEnds != null) result.ringEnds.addAll(ringEnds);
    if (roof != null) result.roof.addAll(roof);
    if (heightM != null) result.heightM = heightM;
    if (minHeightM != null) result.minHeightM = minHeightM;
    if (landmark != null) result.landmark = landmark;
    if (collide != null) result.collide = collide;
    if (wallSeed != null) result.wallSeed = wallSeed;
    return result;
  }

  Building._();

  factory Building.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Building()..mergeFromBuffer(data, registry);
  factory Building.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Building()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Building',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Building.$_createMessage)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'rings', $pb.PbFieldType.KS3)
    ..p<$core.int>(2, _omitFieldNames ? '' : 'ringEnds', $pb.PbFieldType.KU3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'roof', $pb.PbFieldType.KU3)
    ..aD(4, _omitFieldNames ? '' : 'heightM', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'minHeightM', fieldType: $pb.PbFieldType.OF)
    ..aI(6, _omitFieldNames ? '' : 'landmark', fieldType: $pb.PbFieldType.OU3)
    ..aOB(7, _omitFieldNames ? '' : 'collide')
    ..aI(8, _omitFieldNames ? '' : 'wallSeed', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Building clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Building copyWith(void Function(Building) updates) =>
      super.copyWith((message) => updates(message as Building)) as Building;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Building() / Building.new instead')
  static Building create() => Building._();
  static $pb.GeneratedMessage $_createMessage() => Building._();
  @$core.override
  Building createEmptyInstance() => Building._();
  @$core.pragma('dart2js:noInline')
  static Building getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Building>(Building.$_createMessage);
  static Building? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get rings => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get ringEnds => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.int> get roof => $_getList(2);

  @$pb.TagNumber(4)
  $core.double get heightM => $_getN(3);
  @$pb.TagNumber(4)
  set heightM($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeightM() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeightM() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get minHeightM => $_getN(4);
  @$pb.TagNumber(5)
  set minHeightM($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMinHeightM() => $_has(4);
  @$pb.TagNumber(5)
  void clearMinHeightM() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get landmark => $_getIZ(5);
  @$pb.TagNumber(6)
  set landmark($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLandmark() => $_has(5);
  @$pb.TagNumber(6)
  void clearLandmark() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get collide => $_getBF(6);
  @$pb.TagNumber(7)
  set collide($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCollide() => $_has(6);
  @$pb.TagNumber(7)
  void clearCollide() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get wallSeed => $_getIZ(7);
  @$pb.TagNumber(8)
  set wallSeed($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasWallSeed() => $_has(7);
  @$pb.TagNumber(8)
  void clearWallSeed() => $_clearField(8);
}

class Mesh extends $pb.GeneratedMessage {
  factory Mesh({
    GroundKind? kind,
    $core.Iterable<$core.int>? vertices,
    $core.Iterable<$core.int>? indices,
  }) {
    final result = Mesh._();
    if (kind != null) result.kind = kind;
    if (vertices != null) result.vertices.addAll(vertices);
    if (indices != null) result.indices.addAll(indices);
    return result;
  }

  Mesh._();

  factory Mesh.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Mesh()..mergeFromBuffer(data, registry);
  factory Mesh.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Mesh()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Mesh',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Mesh.$_createMessage)
    ..aE<GroundKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: GroundKind.values)
    ..p<$core.int>(2, _omitFieldNames ? '' : 'vertices', $pb.PbFieldType.KS3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'indices', $pb.PbFieldType.KU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mesh clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mesh copyWith(void Function(Mesh) updates) =>
      super.copyWith((message) => updates(message as Mesh)) as Mesh;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Mesh() / Mesh.new instead')
  static Mesh create() => Mesh._();
  static $pb.GeneratedMessage $_createMessage() => Mesh._();
  @$core.override
  Mesh createEmptyInstance() => Mesh._();
  @$core.pragma('dart2js:noInline')
  static Mesh getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Mesh>(Mesh.$_createMessage);
  static Mesh? _defaultInstance;

  @$pb.TagNumber(1)
  GroundKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(GroundKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get vertices => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.int> get indices => $_getList(2);
}

/// landmarks.pb
class Landmarks extends $pb.GeneratedMessage {
  factory Landmarks({
    $core.Iterable<Landmark>? items,
  }) {
    final result = Landmarks._();
    if (items != null) result.items.addAll(items);
    return result;
  }

  Landmarks._();

  factory Landmarks.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Landmarks()..mergeFromBuffer(data, registry);
  factory Landmarks.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Landmarks()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Landmarks',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Landmarks.$_createMessage)
    ..pPM<Landmark>(1, _omitFieldNames ? '' : 'items',
        subBuilder: Landmark.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Landmarks clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Landmarks copyWith(void Function(Landmarks) updates) =>
      super.copyWith((message) => updates(message as Landmarks)) as Landmarks;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Landmarks() / Landmarks.new instead')
  static Landmarks create() => Landmarks._();
  static $pb.GeneratedMessage $_createMessage() => Landmarks._();
  @$core.override
  Landmarks createEmptyInstance() => Landmarks._();
  @$core.pragma('dart2js:noInline')
  static Landmarks getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Landmarks>(Landmarks.$_createMessage);
  static Landmarks? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Landmark> get items => $_getList(0);
}

class Landmark extends $pb.GeneratedMessage {
  factory Landmark({
    $core.String? id,
    $core.String? name,
    $core.int? x,
    $core.int? y,
    $core.double? heightM,
    $core.bool? hero,
    $core.String? blurb,
  }) {
    final result = Landmark._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (heightM != null) result.heightM = heightM;
    if (hero != null) result.hero = hero;
    if (blurb != null) result.blurb = blurb;
    return result;
  }

  Landmark._();

  factory Landmark.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Landmark()..mergeFromBuffer(data, registry);
  factory Landmark.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Landmark()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Landmark',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Landmark.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aI(3, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OS3)
    ..aI(4, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OS3)
    ..aD(5, _omitFieldNames ? '' : 'heightM', fieldType: $pb.PbFieldType.OF)
    ..aOB(6, _omitFieldNames ? '' : 'hero')
    ..aOS(7, _omitFieldNames ? '' : 'blurb')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Landmark clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Landmark copyWith(void Function(Landmark) updates) =>
      super.copyWith((message) => updates(message as Landmark)) as Landmark;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Landmark() / Landmark.new instead')
  static Landmark create() => Landmark._();
  static $pb.GeneratedMessage $_createMessage() => Landmark._();
  @$core.override
  Landmark createEmptyInstance() => Landmark._();
  @$core.pragma('dart2js:noInline')
  static Landmark getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Landmark>(Landmark.$_createMessage);
  static Landmark? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get x => $_getIZ(2);
  @$pb.TagNumber(3)
  set x($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX() => $_has(2);
  @$pb.TagNumber(3)
  void clearX() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get y => $_getIZ(3);
  @$pb.TagNumber(4)
  set y($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasY() => $_has(3);
  @$pb.TagNumber(4)
  void clearY() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get heightM => $_getN(4);
  @$pb.TagNumber(5)
  set heightM($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeightM() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeightM() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get hero => $_getBF(5);
  @$pb.TagNumber(6)
  set hero($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHero() => $_has(5);
  @$pb.TagNumber(6)
  void clearHero() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get blurb => $_getSZ(6);
  @$pb.TagNumber(7)
  set blurb($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasBlurb() => $_has(6);
  @$pb.TagNumber(7)
  void clearBlurb() => $_clearField(7);
}

/// spots.pb
class Spots extends $pb.GeneratedMessage {
  factory Spots({
    $core.Iterable<Spot>? items,
  }) {
    final result = Spots._();
    if (items != null) result.items.addAll(items);
    return result;
  }

  Spots._();

  factory Spots.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Spots()..mergeFromBuffer(data, registry);
  factory Spots.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Spots()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Spots',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Spots.$_createMessage)
    ..pPM<Spot>(1, _omitFieldNames ? '' : 'items',
        subBuilder: Spot.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Spots clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Spots copyWith(void Function(Spots) updates) =>
      super.copyWith((message) => updates(message as Spots)) as Spots;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Spots() / Spots.new instead')
  static Spots create() => Spots._();
  static $pb.GeneratedMessage $_createMessage() => Spots._();
  @$core.override
  Spots createEmptyInstance() => Spots._();
  @$core.pragma('dart2js:noInline')
  static Spots getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Spots>(Spots.$_createMessage);
  static Spots? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Spot> get items => $_getList(0);
}

class Spot extends $pb.GeneratedMessage {
  factory Spot({
    $core.String? id,
    $core.String? kind,
    $core.String? name,
    $core.int? x,
    $core.int? y,
    $core.int? edge,
    $core.int? parkX,
    $core.int? parkY,
    $core.double? parkHeading,
  }) {
    final result = Spot._();
    if (id != null) result.id = id;
    if (kind != null) result.kind = kind;
    if (name != null) result.name = name;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (edge != null) result.edge = edge;
    if (parkX != null) result.parkX = parkX;
    if (parkY != null) result.parkY = parkY;
    if (parkHeading != null) result.parkHeading = parkHeading;
    return result;
  }

  Spot._();

  factory Spot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Spot()..mergeFromBuffer(data, registry);
  factory Spot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Spot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Spot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Spot.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'kind')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aI(4, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OS3)
    ..aI(5, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OS3)
    ..aI(6, _omitFieldNames ? '' : 'edge', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'parkX', fieldType: $pb.PbFieldType.OS3)
    ..aI(8, _omitFieldNames ? '' : 'parkY', fieldType: $pb.PbFieldType.OS3)
    ..aD(9, _omitFieldNames ? '' : 'parkHeading', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Spot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Spot copyWith(void Function(Spot) updates) =>
      super.copyWith((message) => updates(message as Spot)) as Spot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Spot() / Spot.new instead')
  static Spot create() => Spot._();
  static $pb.GeneratedMessage $_createMessage() => Spot._();
  @$core.override
  Spot createEmptyInstance() => Spot._();
  @$core.pragma('dart2js:noInline')
  static Spot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Spot>(Spot.$_createMessage);
  static Spot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get kind => $_getSZ(1);
  @$pb.TagNumber(2)
  set kind($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get x => $_getIZ(3);
  @$pb.TagNumber(4)
  set x($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasX() => $_has(3);
  @$pb.TagNumber(4)
  void clearX() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get y => $_getIZ(4);
  @$pb.TagNumber(5)
  set y($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasY() => $_has(4);
  @$pb.TagNumber(5)
  void clearY() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get edge => $_getIZ(5);
  @$pb.TagNumber(6)
  set edge($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEdge() => $_has(5);
  @$pb.TagNumber(6)
  void clearEdge() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get parkX => $_getIZ(6);
  @$pb.TagNumber(7)
  set parkX($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasParkX() => $_has(6);
  @$pb.TagNumber(7)
  void clearParkX() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get parkY => $_getIZ(7);
  @$pb.TagNumber(8)
  set parkY($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasParkY() => $_has(7);
  @$pb.TagNumber(8)
  void clearParkY() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get parkHeading => $_getN(8);
  @$pb.TagNumber(9)
  set parkHeading($core.double value) => $_setFloat(8, value);
  @$pb.TagNumber(9)
  $core.bool hasParkHeading() => $_has(8);
  @$pb.TagNumber(9)
  void clearParkHeading() => $_clearField(9);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
