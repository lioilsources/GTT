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
    $core.int? terrainVersion,
    $core.double? z0M,
    $core.double? exaggeration,
    $core.int? terrainGridM,
    $core.int? natureVersion,
    $core.Iterable<ChunkRef>? lods,
    $core.int? lodChunks,
    $core.int? lodGridM,
    $core.int? modelsVersion,
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
    if (terrainVersion != null) result.terrainVersion = terrainVersion;
    if (z0M != null) result.z0M = z0M;
    if (exaggeration != null) result.exaggeration = exaggeration;
    if (terrainGridM != null) result.terrainGridM = terrainGridM;
    if (natureVersion != null) result.natureVersion = natureVersion;
    if (lods != null) result.lods.addAll(lods);
    if (lodChunks != null) result.lodChunks = lodChunks;
    if (lodGridM != null) result.lodGridM = lodGridM;
    if (modelsVersion != null) result.modelsVersion = modelsVersion;
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
    ..aI(17, _omitFieldNames ? '' : 'terrainVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(18, _omitFieldNames ? '' : 'z0M', fieldType: $pb.PbFieldType.OF)
    ..aD(19, _omitFieldNames ? '' : 'exaggeration',
        fieldType: $pb.PbFieldType.OF)
    ..aI(20, _omitFieldNames ? '' : 'terrainGridM',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(21, _omitFieldNames ? '' : 'natureVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<ChunkRef>(22, _omitFieldNames ? '' : 'lods',
        subBuilder: ChunkRef.$_createMessage)
    ..aI(23, _omitFieldNames ? '' : 'lodChunks', fieldType: $pb.PbFieldType.OU3)
    ..aI(24, _omitFieldNames ? '' : 'lodGridM', fieldType: $pb.PbFieldType.OU3)
    ..aI(25, _omitFieldNames ? '' : 'modelsVersion',
        fieldType: $pb.PbFieldType.OU3)
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

  /// Terrain (specs/terrain.md, citypack v4). 0 or missing = flat pack: z = 0 everywhere.
  @$pb.TagNumber(17)
  $core.int get terrainVersion => $_getIZ(16);
  @$pb.TagNumber(17)
  set terrainVersion($core.int value) => $_setUnsignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasTerrainVersion() => $_has(16);
  @$pb.TagNumber(17)
  void clearTerrainVersion() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.double get z0M => $_getN(17);
  @$pb.TagNumber(18)
  set z0M($core.double value) => $_setFloat(17, value);
  @$pb.TagNumber(18)
  $core.bool hasZ0M() => $_has(17);
  @$pb.TagNumber(18)
  void clearZ0M() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.double get exaggeration => $_getN(18);
  @$pb.TagNumber(19)
  set exaggeration($core.double value) => $_setFloat(18, value);
  @$pb.TagNumber(19)
  $core.bool hasExaggeration() => $_has(18);
  @$pb.TagNumber(19)
  void clearExaggeration() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.int get terrainGridM => $_getIZ(19);
  @$pb.TagNumber(20)
  set terrainGridM($core.int value) => $_setUnsignedInt32(19, value);
  @$pb.TagNumber(20)
  $core.bool hasTerrainGridM() => $_has(19);
  @$pb.TagNumber(20)
  void clearTerrainGridM() => $_clearField(20);

  /// Nature (specs/nature.md, citypack v4). 0 or missing = ground meshes carry no classes, no trees.
  @$pb.TagNumber(21)
  $core.int get natureVersion => $_getIZ(20);
  @$pb.TagNumber(21)
  set natureVersion($core.int value) => $_setUnsignedInt32(20, value);
  @$pb.TagNumber(21)
  $core.bool hasNatureVersion() => $_has(20);
  @$pb.TagNumber(21)
  void clearNatureVersion() => $_clearField(21);

  @$pb.TagNumber(22)
  $pb.PbList<ChunkRef> get lods => $_getList(21);

  @$pb.TagNumber(23)
  $core.int get lodChunks => $_getIZ(22);
  @$pb.TagNumber(23)
  set lodChunks($core.int value) => $_setUnsignedInt32(22, value);
  @$pb.TagNumber(23)
  $core.bool hasLodChunks() => $_has(22);
  @$pb.TagNumber(23)
  void clearLodChunks() => $_clearField(23);

  @$pb.TagNumber(24)
  $core.int get lodGridM => $_getIZ(23);
  @$pb.TagNumber(24)
  set lodGridM($core.int value) => $_setUnsignedInt32(23, value);
  @$pb.TagNumber(24)
  $core.bool hasLodGridM() => $_has(23);
  @$pb.TagNumber(24)
  void clearLodGridM() => $_clearField(24);

  /// Landmark models (specs/models.md). 0 or missing = no models.pb: landmarks stay footprints.
  @$pb.TagNumber(25)
  $core.int get modelsVersion => $_getIZ(24);
  @$pb.TagNumber(25)
  set modelsVersion($core.int value) => $_setUnsignedInt32(24, value);
  @$pb.TagNumber(25)
  $core.bool hasModelsVersion() => $_has(24);
  @$pb.TagNumber(25)
  void clearModelsVersion() => $_clearField(25);
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
    $core.int? zDm,
  }) {
    final result = Node._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (border != null) result.border = border;
    if (zDm != null) result.zDm = zDm;
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
    ..aI(4, _omitFieldNames ? '' : 'zDm', fieldType: $pb.PbFieldType.OS3)
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

  @$pb.TagNumber(4)
  $core.int get zDm => $_getIZ(3);
  @$pb.TagNumber(4)
  set zDm($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasZDm() => $_has(3);
  @$pb.TagNumber(4)
  void clearZDm() => $_clearField(4);
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
    $core.Iterable<$core.int>? zDm,
    $core.bool? stairs,
    $core.bool? microOnly,
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
    if (zDm != null) result.zDm.addAll(zDm);
    if (stairs != null) result.stairs = stairs;
    if (microOnly != null) result.microOnly = microOnly;
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
    ..p<$core.int>(14, _omitFieldNames ? '' : 'zDm', $pb.PbFieldType.KS3)
    ..aOB(15, _omitFieldNames ? '' : 'stairs')
    ..aOB(16, _omitFieldNames ? '' : 'microOnly')
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

  /// Terrain: game height per vertex of `points` (same count); edges with relief are densified to
  /// segments of at most 16 m. Empty in a flat pack.
  @$pb.TagNumber(14)
  $pb.PbList<$core.int> get zDm => $_getList(13);

  @$pb.TagNumber(15)
  $core.bool get stairs => $_getBF(14);
  @$pb.TagNumber(15)
  set stairs($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(15)
  $core.bool hasStairs() => $_has(14);
  @$pb.TagNumber(15)
  void clearStairs() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.bool get microOnly => $_getBF(15);
  @$pb.TagNumber(16)
  set microOnly($core.bool value) => $_setBool(15, value);
  @$pb.TagNumber(16)
  $core.bool hasMicroOnly() => $_has(15);
  @$pb.TagNumber(16)
  void clearMicroOnly() => $_clearField(16);
}

/// chunks/{x}_{y}.pb
class Chunk extends $pb.GeneratedMessage {
  factory Chunk({
    $core.int? x,
    $core.int? y,
    $core.Iterable<Building>? buildings,
    $core.Iterable<Mesh>? ground,
    $core.Iterable<Barrier>? barriers,
    $core.List<$core.int>? terrain,
    $core.List<$core.int>? shade,
    $core.List<$core.int>? trees,
    $core.Iterable<Mesh>? shore,
    $core.Iterable<Label>? labels,
  }) {
    final result = Chunk._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (buildings != null) result.buildings.addAll(buildings);
    if (ground != null) result.ground.addAll(ground);
    if (barriers != null) result.barriers.addAll(barriers);
    if (terrain != null) result.terrain = terrain;
    if (shade != null) result.shade = shade;
    if (trees != null) result.trees = trees;
    if (shore != null) result.shore.addAll(shore);
    if (labels != null) result.labels.addAll(labels);
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
    ..pPM<Barrier>(5, _omitFieldNames ? '' : 'barriers',
        subBuilder: Barrier.$_createMessage)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'terrain', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'shade', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        8, _omitFieldNames ? '' : 'trees', $pb.PbFieldType.OY)
    ..pPM<Mesh>(9, _omitFieldNames ? '' : 'shore',
        subBuilder: Mesh.$_createMessage)
    ..pPM<Label>(10, _omitFieldNames ? '' : 'labels',
        subBuilder: Label.$_createMessage)
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

  @$pb.TagNumber(5)
  $pb.PbList<Barrier> get barriers => $_getList(4);

  /// Terrain: 33 × 33 int16 little-endian game heights in dm, rows from the south, sample (i, j) at
  /// (x·chunk_m + i·grid_m, y·chunk_m + j·grid_m); edges are shared with the neighbours.
  @$pb.TagNumber(6)
  $core.List<$core.int> get terrain => $_getN(5);
  @$pb.TagNumber(6)
  set terrain($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTerrain() => $_has(5);
  @$pb.TagNumber(6)
  void clearTerrain() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get shade => $_getN(6);
  @$pb.TagNumber(7)
  set shade($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasShade() => $_has(6);
  @$pb.TagNumber(7)
  void clearShade() => $_clearField(7);

  /// Nature: 3 bytes per tree: x, y (uint8, metres from the chunk's south-west corner), then
  /// size (low 2 bits: 0 S, 1 M, 2 L) | colour jitter << 2. Order = tree key index (specs/flow.md).
  @$pb.TagNumber(8)
  $core.List<$core.int> get trees => $_getN(7);
  @$pb.TagNumber(8)
  set trees($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTrees() => $_has(7);
  @$pb.TagNumber(8)
  void clearTrees() => $_clearField(8);

  @$pb.TagNumber(9)
  $pb.PbList<Mesh> get shore => $_getList(8);

  @$pb.TagNumber(10)
  $pb.PbList<Label> get labels => $_getList(9);
}

/// A name drawn along an axis (water) or at a point (green: axis of one vertex).
class Label extends $pb.GeneratedMessage {
  factory Label({
    $core.String? name,
    $core.Iterable<$core.int>? axis,
    $core.bool? water,
    $core.int? areaM2,
  }) {
    final result = Label._();
    if (name != null) result.name = name;
    if (axis != null) result.axis.addAll(axis);
    if (water != null) result.water = water;
    if (areaM2 != null) result.areaM2 = areaM2;
    return result;
  }

  Label._();

  factory Label.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Label()..mergeFromBuffer(data, registry);
  factory Label.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Label()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Label',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Label.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..p<$core.int>(2, _omitFieldNames ? '' : 'axis', $pb.PbFieldType.KS3)
    ..aOB(3, _omitFieldNames ? '' : 'water')
    ..aI(4, _omitFieldNames ? '' : 'areaM2', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Label clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Label copyWith(void Function(Label) updates) =>
      super.copyWith((message) => updates(message as Label)) as Label;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Label() / Label.new instead')
  static Label create() => Label._();
  static $pb.GeneratedMessage $_createMessage() => Label._();
  @$core.override
  Label createEmptyInstance() => Label._();
  @$core.pragma('dart2js:noInline')
  static Label getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Label>(Label.$_createMessage);
  static Label? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get axis => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get water => $_getBF(2);
  @$pb.TagNumber(3)
  set water($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWater() => $_has(2);
  @$pb.TagNumber(3)
  void clearWater() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get areaM2 => $_getIZ(3);
  @$pb.TagNumber(4)
  set areaM2($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAreaM2() => $_has(3);
  @$pb.TagNumber(4)
  void clearAreaM2() => $_clearField(4);
}

/// A bollard line: cars (not micro vehicles) collide with it as with a wall.
class Barrier extends $pb.GeneratedMessage {
  factory Barrier({
    $core.Iterable<$core.int>? points,
  }) {
    final result = Barrier._();
    if (points != null) result.points.addAll(points);
    return result;
  }

  Barrier._();

  factory Barrier.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Barrier()..mergeFromBuffer(data, registry);
  factory Barrier.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Barrier()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Barrier',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Barrier.$_createMessage)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'points', $pb.PbFieldType.KS3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Barrier clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Barrier copyWith(void Function(Barrier) updates) =>
      super.copyWith((message) => updates(message as Barrier)) as Barrier;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Barrier() / Barrier.new instead')
  static Barrier create() => Barrier._();
  static $pb.GeneratedMessage $_createMessage() => Barrier._();
  @$core.override
  Barrier createEmptyInstance() => Barrier._();
  @$core.pragma('dart2js:noInline')
  static Barrier getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Barrier>(Barrier.$_createMessage);
  static Barrier? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get points => $_getList(0);
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
    $core.int? baseZDm,
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
    if (baseZDm != null) result.baseZDm = baseZDm;
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
    ..aI(9, _omitFieldNames ? '' : 'baseZDm', fieldType: $pb.PbFieldType.OS3)
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

  @$pb.TagNumber(9)
  $core.int get baseZDm => $_getIZ(8);
  @$pb.TagNumber(9)
  set baseZDm($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBaseZDm() => $_has(8);
  @$pb.TagNumber(9)
  void clearBaseZDm() => $_clearField(9);
}

class Mesh extends $pb.GeneratedMessage {
  factory Mesh({
    GroundKind? kind,
    $core.Iterable<$core.int>? vertices,
    $core.Iterable<$core.int>? indices,
    WaterClass? waterClass,
    GreenClass? greenClass,
    Surface? surface,
    $core.String? name,
    $core.int? zDm,
  }) {
    final result = Mesh._();
    if (kind != null) result.kind = kind;
    if (vertices != null) result.vertices.addAll(vertices);
    if (indices != null) result.indices.addAll(indices);
    if (waterClass != null) result.waterClass = waterClass;
    if (greenClass != null) result.greenClass = greenClass;
    if (surface != null) result.surface = surface;
    if (name != null) result.name = name;
    if (zDm != null) result.zDm = zDm;
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
    ..aE<WaterClass>(4, _omitFieldNames ? '' : 'waterClass',
        enumValues: WaterClass.values)
    ..aE<GreenClass>(5, _omitFieldNames ? '' : 'greenClass',
        enumValues: GreenClass.values)
    ..aE<Surface>(6, _omitFieldNames ? '' : 'surface',
        enumValues: Surface.values)
    ..aOS(7, _omitFieldNames ? '' : 'name')
    ..aI(8, _omitFieldNames ? '' : 'zDm', fieldType: $pb.PbFieldType.OS3)
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

  /// Nature (specs/nature.md): WATER meshes carry a class, PARK meshes a green class and surface.
  @$pb.TagNumber(4)
  WaterClass get waterClass => $_getN(3);
  @$pb.TagNumber(4)
  set waterClass(WaterClass value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasWaterClass() => $_has(3);
  @$pb.TagNumber(4)
  void clearWaterClass() => $_clearField(4);

  @$pb.TagNumber(5)
  GreenClass get greenClass => $_getN(4);
  @$pb.TagNumber(5)
  set greenClass(GreenClass value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasGreenClass() => $_has(4);
  @$pb.TagNumber(5)
  void clearGreenClass() => $_clearField(5);

  @$pb.TagNumber(6)
  Surface get surface => $_getN(5);
  @$pb.TagNumber(6)
  set surface(Surface value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSurface() => $_has(5);
  @$pb.TagNumber(6)
  void clearSurface() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get name => $_getSZ(6);
  @$pb.TagNumber(7)
  set name($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasName() => $_has(6);
  @$pb.TagNumber(7)
  void clearName() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get zDm => $_getIZ(7);
  @$pb.TagNumber(8)
  set zDm($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasZDm() => $_has(7);
  @$pb.TagNumber(8)
  void clearZDm() => $_clearField(8);
}

/// lod/{x}_{y}.pb: the far ring of the chase camera (specs/terrain.md, specs/nature.md).
class Lod extends $pb.GeneratedMessage {
  factory Lod({
    $core.int? x,
    $core.int? y,
    $core.List<$core.int>? terrain,
    $core.Iterable<LodMass>? masses,
    $core.Iterable<Mesh>? water,
  }) {
    final result = Lod._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (terrain != null) result.terrain = terrain;
    if (masses != null) result.masses.addAll(masses);
    if (water != null) result.water.addAll(water);
    return result;
  }

  Lod._();

  factory Lod.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Lod()..mergeFromBuffer(data, registry);
  factory Lod.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Lod()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Lod',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Lod.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OS3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'terrain', $pb.PbFieldType.OY)
    ..pPM<LodMass>(4, _omitFieldNames ? '' : 'masses',
        subBuilder: LodMass.$_createMessage)
    ..pPM<Mesh>(5, _omitFieldNames ? '' : 'water',
        subBuilder: Mesh.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Lod clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Lod copyWith(void Function(Lod) updates) =>
      super.copyWith((message) => updates(message as Lod)) as Lod;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Lod() / Lod.new instead')
  static Lod create() => Lod._();
  static $pb.GeneratedMessage $_createMessage() => Lod._();
  @$core.override
  Lod createEmptyInstance() => Lod._();
  @$core.pragma('dart2js:noInline')
  static Lod getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Lod>(Lod.$_createMessage);
  static Lod? _defaultInstance;

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
  $core.List<$core.int> get terrain => $_getN(2);
  @$pb.TagNumber(3)
  set terrain($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTerrain() => $_has(2);
  @$pb.TagNumber(3)
  void clearTerrain() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<LodMass> get masses => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<Mesh> get water => $_getList(4);
}

class LodMass extends $pb.GeneratedMessage {
  factory LodMass({
    LodKind? kind,
    $core.Iterable<$core.int>? rings,
    $core.Iterable<$core.int>? ringEnds,
    $core.Iterable<$core.int>? roof,
    $core.double? heightM,
    $core.int? baseZDm,
  }) {
    final result = LodMass._();
    if (kind != null) result.kind = kind;
    if (rings != null) result.rings.addAll(rings);
    if (ringEnds != null) result.ringEnds.addAll(ringEnds);
    if (roof != null) result.roof.addAll(roof);
    if (heightM != null) result.heightM = heightM;
    if (baseZDm != null) result.baseZDm = baseZDm;
    return result;
  }

  LodMass._();

  factory LodMass.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LodMass()..mergeFromBuffer(data, registry);
  factory LodMass.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LodMass()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LodMass',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: LodMass.$_createMessage)
    ..aE<LodKind>(1, _omitFieldNames ? '' : 'kind', enumValues: LodKind.values)
    ..p<$core.int>(2, _omitFieldNames ? '' : 'rings', $pb.PbFieldType.KS3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'ringEnds', $pb.PbFieldType.KU3)
    ..p<$core.int>(4, _omitFieldNames ? '' : 'roof', $pb.PbFieldType.KU3)
    ..aD(5, _omitFieldNames ? '' : 'heightM', fieldType: $pb.PbFieldType.OF)
    ..aI(6, _omitFieldNames ? '' : 'baseZDm', fieldType: $pb.PbFieldType.OS3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LodMass clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LodMass copyWith(void Function(LodMass) updates) =>
      super.copyWith((message) => updates(message as LodMass)) as LodMass;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LodMass() / LodMass.new instead')
  static LodMass create() => LodMass._();
  static $pb.GeneratedMessage $_createMessage() => LodMass._();
  @$core.override
  LodMass createEmptyInstance() => LodMass._();
  @$core.pragma('dart2js:noInline')
  static LodMass getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LodMass>(LodMass.$_createMessage);
  static LodMass? _defaultInstance;

  @$pb.TagNumber(1)
  LodKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(LodKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get rings => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.int> get ringEnds => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.int> get roof => $_getList(3);

  @$pb.TagNumber(5)
  $core.double get heightM => $_getN(4);
  @$pb.TagNumber(5)
  set heightM($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeightM() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeightM() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get baseZDm => $_getIZ(5);
  @$pb.TagNumber(6)
  set baseZDm($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBaseZDm() => $_has(5);
  @$pb.TagNumber(6)
  void clearBaseZDm() => $_clearField(6);
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
    $core.String? minigame,
    $core.int? lookX,
    $core.int? lookY,
    $core.int? subjectDm,
    $core.String? areaName,
    $core.bool? areaWater,
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
    if (minigame != null) result.minigame = minigame;
    if (lookX != null) result.lookX = lookX;
    if (lookY != null) result.lookY = lookY;
    if (subjectDm != null) result.subjectDm = subjectDm;
    if (areaName != null) result.areaName = areaName;
    if (areaWater != null) result.areaWater = areaWater;
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
    ..aOS(10, _omitFieldNames ? '' : 'minigame')
    ..aI(11, _omitFieldNames ? '' : 'lookX', fieldType: $pb.PbFieldType.OS3)
    ..aI(12, _omitFieldNames ? '' : 'lookY', fieldType: $pb.PbFieldType.OS3)
    ..aI(13, _omitFieldNames ? '' : 'subjectDm', fieldType: $pb.PbFieldType.OU3)
    ..aOS(14, _omitFieldNames ? '' : 'areaName')
    ..aOB(15, _omitFieldNames ? '' : 'areaWater')
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

  @$pb.TagNumber(10)
  $core.String get minigame => $_getSZ(9);
  @$pb.TagNumber(10)
  set minigame($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasMinigame() => $_has(9);
  @$pb.TagNumber(10)
  void clearMinigame() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get lookX => $_getIZ(10);
  @$pb.TagNumber(11)
  set lookX($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLookX() => $_has(10);
  @$pb.TagNumber(11)
  void clearLookX() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get lookY => $_getIZ(11);
  @$pb.TagNumber(12)
  set lookY($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasLookY() => $_has(11);
  @$pb.TagNumber(12)
  void clearLookY() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get subjectDm => $_getIZ(12);
  @$pb.TagNumber(13)
  set subjectDm($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasSubjectDm() => $_has(12);
  @$pb.TagNumber(13)
  void clearSubjectDm() => $_clearField(13);

  /// Nature: the park the spot is in, or the water within 150 m ("" = none); clients phrase
  /// water as "by …" through i18n.
  @$pb.TagNumber(14)
  $core.String get areaName => $_getSZ(13);
  @$pb.TagNumber(14)
  set areaName($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasAreaName() => $_has(13);
  @$pb.TagNumber(14)
  void clearAreaName() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.bool get areaWater => $_getBF(14);
  @$pb.TagNumber(15)
  set areaWater($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(15)
  $core.bool hasAreaWater() => $_has(14);
  @$pb.TagNumber(15)
  void clearAreaWater() => $_clearField(15);
}

/// trams.pb (specs/trams.md): tram tracks as their own graph, always two-way, plus generated stops.
/// A city without trams has an empty TramGraph (the file always exists from citypack v2 on).
class TramGraph extends $pb.GeneratedMessage {
  factory TramGraph({
    $core.Iterable<Node>? nodes,
    $core.Iterable<TramEdge>? edges,
    $core.Iterable<TramStop>? stops,
  }) {
    final result = TramGraph._();
    if (nodes != null) result.nodes.addAll(nodes);
    if (edges != null) result.edges.addAll(edges);
    if (stops != null) result.stops.addAll(stops);
    return result;
  }

  TramGraph._();

  factory TramGraph.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TramGraph()..mergeFromBuffer(data, registry);
  factory TramGraph.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TramGraph()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TramGraph',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: TramGraph.$_createMessage)
    ..pPM<Node>(1, _omitFieldNames ? '' : 'nodes',
        subBuilder: Node.$_createMessage)
    ..pPM<TramEdge>(2, _omitFieldNames ? '' : 'edges',
        subBuilder: TramEdge.$_createMessage)
    ..pPM<TramStop>(3, _omitFieldNames ? '' : 'stops',
        subBuilder: TramStop.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TramGraph clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TramGraph copyWith(void Function(TramGraph) updates) =>
      super.copyWith((message) => updates(message as TramGraph)) as TramGraph;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TramGraph() / TramGraph.new instead')
  static TramGraph create() => TramGraph._();
  static $pb.GeneratedMessage $_createMessage() => TramGraph._();
  @$core.override
  TramGraph createEmptyInstance() => TramGraph._();
  @$core.pragma('dart2js:noInline')
  static TramGraph getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TramGraph>(TramGraph.$_createMessage);
  static TramGraph? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Node> get nodes => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<TramEdge> get edges => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<TramStop> get stops => $_getList(2);
}

class TramEdge extends $pb.GeneratedMessage {
  factory TramEdge({
    $core.int? from,
    $core.int? to,
    $core.Iterable<$core.int>? points,
    $core.int? layerFrom,
    $core.int? layerTo,
    $core.bool? bridge,
    $core.bool? tunnel,
  }) {
    final result = TramEdge._();
    if (from != null) result.from = from;
    if (to != null) result.to = to;
    if (points != null) result.points.addAll(points);
    if (layerFrom != null) result.layerFrom = layerFrom;
    if (layerTo != null) result.layerTo = layerTo;
    if (bridge != null) result.bridge = bridge;
    if (tunnel != null) result.tunnel = tunnel;
    return result;
  }

  TramEdge._();

  factory TramEdge.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TramEdge()..mergeFromBuffer(data, registry);
  factory TramEdge.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TramEdge()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TramEdge',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: TramEdge.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'from', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'to', fieldType: $pb.PbFieldType.OU3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'points', $pb.PbFieldType.KS3)
    ..aI(4, _omitFieldNames ? '' : 'layerFrom', fieldType: $pb.PbFieldType.OS3)
    ..aI(5, _omitFieldNames ? '' : 'layerTo', fieldType: $pb.PbFieldType.OS3)
    ..aOB(6, _omitFieldNames ? '' : 'bridge')
    ..aOB(7, _omitFieldNames ? '' : 'tunnel')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TramEdge clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TramEdge copyWith(void Function(TramEdge) updates) =>
      super.copyWith((message) => updates(message as TramEdge)) as TramEdge;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TramEdge() / TramEdge.new instead')
  static TramEdge create() => TramEdge._();
  static $pb.GeneratedMessage $_createMessage() => TramEdge._();
  @$core.override
  TramEdge createEmptyInstance() => TramEdge._();
  @$core.pragma('dart2js:noInline')
  static TramEdge getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TramEdge>(TramEdge.$_createMessage);
  static TramEdge? _defaultInstance;

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
  $core.int get layerFrom => $_getIZ(3);
  @$pb.TagNumber(4)
  set layerFrom($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLayerFrom() => $_has(3);
  @$pb.TagNumber(4)
  void clearLayerFrom() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get layerTo => $_getIZ(4);
  @$pb.TagNumber(5)
  set layerTo($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLayerTo() => $_has(4);
  @$pb.TagNumber(5)
  void clearLayerTo() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get bridge => $_getBF(5);
  @$pb.TagNumber(6)
  set bridge($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBridge() => $_has(5);
  @$pb.TagNumber(6)
  void clearBridge() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get tunnel => $_getBF(6);
  @$pb.TagNumber(7)
  set tunnel($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTunnel() => $_has(6);
  @$pb.TagNumber(7)
  void clearTunnel() => $_clearField(7);
}

class TramStop extends $pb.GeneratedMessage {
  factory TramStop({
    $core.int? edge,
    $core.double? sM,
  }) {
    final result = TramStop._();
    if (edge != null) result.edge = edge;
    if (sM != null) result.sM = sM;
    return result;
  }

  TramStop._();

  factory TramStop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TramStop()..mergeFromBuffer(data, registry);
  factory TramStop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TramStop()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TramStop',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: TramStop.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'edge', fieldType: $pb.PbFieldType.OU3)
    ..aD(2, _omitFieldNames ? '' : 'sM', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TramStop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TramStop copyWith(void Function(TramStop) updates) =>
      super.copyWith((message) => updates(message as TramStop)) as TramStop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TramStop() / TramStop.new instead')
  static TramStop create() => TramStop._();
  static $pb.GeneratedMessage $_createMessage() => TramStop._();
  @$core.override
  TramStop createEmptyInstance() => TramStop._();
  @$core.pragma('dart2js:noInline')
  static TramStop getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TramStop>(TramStop.$_createMessage);
  static TramStop? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get edge => $_getIZ(0);
  @$pb.TagNumber(1)
  set edge($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEdge() => $_has(0);
  @$pb.TagNumber(1)
  void clearEdge() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get sM => $_getN(1);
  @$pb.TagNumber(2)
  set sM($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSM() => $_has(1);
  @$pb.TagNumber(2)
  void clearSM() => $_clearField(2);
}

/// models.pb (specs/models.md): shapes of hero landmarks. Additive: a pack without it still works,
/// collisions stay with the layer-0 footprints in the chunks. Heights are real metres (the client
/// applies the building display height); z is never exaggerated inside a part.
class Models extends $pb.GeneratedMessage {
  factory Models({
    $core.Iterable<Model>? models,
  }) {
    final result = Models._();
    if (models != null) result.models.addAll(models);
    return result;
  }

  Models._();

  factory Models.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Models()..mergeFromBuffer(data, registry);
  factory Models.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Models()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Models',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Models.$_createMessage)
    ..pPM<Model>(1, _omitFieldNames ? '' : 'models',
        subBuilder: Model.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Models clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Models copyWith(void Function(Models) updates) =>
      super.copyWith((message) => updates(message as Models)) as Models;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Models() / Models.new instead')
  static Models create() => Models._();
  static $pb.GeneratedMessage $_createMessage() => Models._();
  @$core.override
  Models createEmptyInstance() => Models._();
  @$core.pragma('dart2js:noInline')
  static Models getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Models>(Models.$_createMessage);
  static Models? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Model> get models => $_getList(0);
}

class Model extends $pb.GeneratedMessage {
  factory Model({
    $core.String? landmarkId,
    ModelSource? source,
    $core.Iterable<ModelPart>? parts,
    $core.Iterable<BuildingRef>? replaces,
    $core.Iterable<PlanPoly>? roofPlan,
    $core.int? tris,
  }) {
    final result = Model._();
    if (landmarkId != null) result.landmarkId = landmarkId;
    if (source != null) result.source = source;
    if (parts != null) result.parts.addAll(parts);
    if (replaces != null) result.replaces.addAll(replaces);
    if (roofPlan != null) result.roofPlan.addAll(roofPlan);
    if (tris != null) result.tris = tris;
    return result;
  }

  Model._();

  factory Model.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Model()..mergeFromBuffer(data, registry);
  factory Model.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Model()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Model',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: Model.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'landmarkId')
    ..aE<ModelSource>(2, _omitFieldNames ? '' : 'source',
        enumValues: ModelSource.values)
    ..pPM<ModelPart>(3, _omitFieldNames ? '' : 'parts',
        subBuilder: ModelPart.$_createMessage)
    ..pPM<BuildingRef>(4, _omitFieldNames ? '' : 'replaces',
        subBuilder: BuildingRef.$_createMessage)
    ..pPM<PlanPoly>(5, _omitFieldNames ? '' : 'roofPlan',
        subBuilder: PlanPoly.$_createMessage)
    ..aI(6, _omitFieldNames ? '' : 'tris', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Model clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Model copyWith(void Function(Model) updates) =>
      super.copyWith((message) => updates(message as Model)) as Model;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Model() / Model.new instead')
  static Model create() => Model._();
  static $pb.GeneratedMessage $_createMessage() => Model._();
  @$core.override
  Model createEmptyInstance() => Model._();
  @$core.pragma('dart2js:noInline')
  static Model getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Model>(Model.$_createMessage);
  static Model? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get landmarkId => $_getSZ(0);
  @$pb.TagNumber(1)
  set landmarkId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLandmarkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLandmarkId() => $_clearField(1);

  @$pb.TagNumber(2)
  ModelSource get source => $_getN(1);
  @$pb.TagNumber(2)
  set source(ModelSource value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<ModelPart> get parts => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<BuildingRef> get replaces => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<PlanPoly> get roofPlan => $_getList(4);

  @$pb.TagNumber(6)
  $core.int get tris => $_getIZ(5);
  @$pb.TagNumber(6)
  set tris($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTris() => $_has(5);
  @$pb.TagNumber(6)
  void clearTris() => $_clearField(6);
}

/// One source building standing on the terrain on its own (specs/models.md: parts).
class ModelPart extends $pb.GeneratedMessage {
  factory ModelPart({
    $core.int? anchorX,
    $core.int? anchorY,
    $core.int? baseZDm,
    $core.Iterable<$core.int>? positions,
    $core.Iterable<$core.int>? triangles,
    $core.List<$core.int>? roles,
    $core.String? sourceId,
    $core.Iterable<$core.int>? foot,
  }) {
    final result = ModelPart._();
    if (anchorX != null) result.anchorX = anchorX;
    if (anchorY != null) result.anchorY = anchorY;
    if (baseZDm != null) result.baseZDm = baseZDm;
    if (positions != null) result.positions.addAll(positions);
    if (triangles != null) result.triangles.addAll(triangles);
    if (roles != null) result.roles = roles;
    if (sourceId != null) result.sourceId = sourceId;
    if (foot != null) result.foot.addAll(foot);
    return result;
  }

  ModelPart._();

  factory ModelPart.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ModelPart()..mergeFromBuffer(data, registry);
  factory ModelPart.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ModelPart()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelPart',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: ModelPart.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'anchorX', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'anchorY', fieldType: $pb.PbFieldType.OS3)
    ..aI(3, _omitFieldNames ? '' : 'baseZDm', fieldType: $pb.PbFieldType.OS3)
    ..p<$core.int>(4, _omitFieldNames ? '' : 'positions', $pb.PbFieldType.KS3)
    ..p<$core.int>(5, _omitFieldNames ? '' : 'triangles', $pb.PbFieldType.KU3)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'roles', $pb.PbFieldType.OY)
    ..aOS(7, _omitFieldNames ? '' : 'sourceId')
    ..p<$core.int>(8, _omitFieldNames ? '' : 'foot', $pb.PbFieldType.KU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelPart clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelPart copyWith(void Function(ModelPart) updates) =>
      super.copyWith((message) => updates(message as ModelPart)) as ModelPart;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ModelPart() / ModelPart.new instead')
  static ModelPart create() => ModelPart._();
  static $pb.GeneratedMessage $_createMessage() => ModelPart._();
  @$core.override
  ModelPart createEmptyInstance() => ModelPart._();
  @$core.pragma('dart2js:noInline')
  static ModelPart getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelPart>(ModelPart.$_createMessage);
  static ModelPart? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get anchorX => $_getIZ(0);
  @$pb.TagNumber(1)
  set anchorX($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAnchorX() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnchorX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get anchorY => $_getIZ(1);
  @$pb.TagNumber(2)
  set anchorY($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAnchorY() => $_has(1);
  @$pb.TagNumber(2)
  void clearAnchorY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get baseZDm => $_getIZ(2);
  @$pb.TagNumber(3)
  set baseZDm($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBaseZDm() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseZDm() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.int> get positions => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.int> get triangles => $_getList(4);

  @$pb.TagNumber(6)
  $core.List<$core.int> get roles => $_getN(5);
  @$pb.TagNumber(6)
  set roles($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRoles() => $_has(5);
  @$pb.TagNumber(6)
  void clearRoles() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get sourceId => $_getSZ(6);
  @$pb.TagNumber(7)
  set sourceId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSourceId() => $_has(6);
  @$pb.TagNumber(7)
  void clearSourceId() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<$core.int> get foot => $_getList(7);
}

class BuildingRef extends $pb.GeneratedMessage {
  factory BuildingRef({
    $core.int? chunkX,
    $core.int? chunkY,
    $core.int? index,
  }) {
    final result = BuildingRef._();
    if (chunkX != null) result.chunkX = chunkX;
    if (chunkY != null) result.chunkY = chunkY;
    if (index != null) result.index = index;
    return result;
  }

  BuildingRef._();

  factory BuildingRef.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BuildingRef()..mergeFromBuffer(data, registry);
  factory BuildingRef.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BuildingRef()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BuildingRef',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: BuildingRef.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'chunkX', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'chunkY', fieldType: $pb.PbFieldType.OS3)
    ..aI(3, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildingRef clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildingRef copyWith(void Function(BuildingRef) updates) =>
      super.copyWith((message) => updates(message as BuildingRef))
          as BuildingRef;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BuildingRef() / BuildingRef.new instead')
  static BuildingRef create() => BuildingRef._();
  static $pb.GeneratedMessage $_createMessage() => BuildingRef._();
  @$core.override
  BuildingRef createEmptyInstance() => BuildingRef._();
  @$core.pragma('dart2js:noInline')
  static BuildingRef getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BuildingRef>(
          BuildingRef.$_createMessage);
  static BuildingRef? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get chunkX => $_getIZ(0);
  @$pb.TagNumber(1)
  set chunkX($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChunkX() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunkX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get chunkY => $_getIZ(1);
  @$pb.TagNumber(2)
  set chunkY($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChunkY() => $_has(1);
  @$pb.TagNumber(2)
  void clearChunkY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get index => $_getIZ(2);
  @$pb.TagNumber(3)
  set index($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearIndex() => $_clearField(3);
}

/// A roof-plan polygon: rings like Building, pretriangulated, drawn as a prism from base_z to height_m.
class PlanPoly extends $pb.GeneratedMessage {
  factory PlanPoly({
    $core.Iterable<$core.int>? points,
    $core.Iterable<$core.int>? ringEnds,
    $core.Iterable<$core.int>? triangles,
    $core.double? heightM,
    $core.int? shade,
    $core.int? baseZDm,
  }) {
    final result = PlanPoly._();
    if (points != null) result.points.addAll(points);
    if (ringEnds != null) result.ringEnds.addAll(ringEnds);
    if (triangles != null) result.triangles.addAll(triangles);
    if (heightM != null) result.heightM = heightM;
    if (shade != null) result.shade = shade;
    if (baseZDm != null) result.baseZDm = baseZDm;
    return result;
  }

  PlanPoly._();

  factory PlanPoly.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlanPoly()..mergeFromBuffer(data, registry);
  factory PlanPoly.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlanPoly()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlanPoly',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'citypack'),
      createEmptyInstance: PlanPoly.$_createMessage)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'points', $pb.PbFieldType.KS3)
    ..p<$core.int>(2, _omitFieldNames ? '' : 'ringEnds', $pb.PbFieldType.KU3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'triangles', $pb.PbFieldType.KU3)
    ..aD(4, _omitFieldNames ? '' : 'heightM', fieldType: $pb.PbFieldType.OF)
    ..aI(5, _omitFieldNames ? '' : 'shade', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'baseZDm', fieldType: $pb.PbFieldType.OS3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlanPoly clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlanPoly copyWith(void Function(PlanPoly) updates) =>
      super.copyWith((message) => updates(message as PlanPoly)) as PlanPoly;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PlanPoly() / PlanPoly.new instead')
  static PlanPoly create() => PlanPoly._();
  static $pb.GeneratedMessage $_createMessage() => PlanPoly._();
  @$core.override
  PlanPoly createEmptyInstance() => PlanPoly._();
  @$core.pragma('dart2js:noInline')
  static PlanPoly getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlanPoly>(PlanPoly.$_createMessage);
  static PlanPoly? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get points => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get ringEnds => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.int> get triangles => $_getList(2);

  @$pb.TagNumber(4)
  $core.double get heightM => $_getN(3);
  @$pb.TagNumber(4)
  set heightM($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeightM() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeightM() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get shade => $_getIZ(4);
  @$pb.TagNumber(5)
  set shade($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasShade() => $_has(4);
  @$pb.TagNumber(5)
  void clearShade() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get baseZDm => $_getIZ(5);
  @$pb.TagNumber(6)
  set baseZDm($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBaseZDm() => $_has(5);
  @$pb.TagNumber(6)
  void clearBaseZDm() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
