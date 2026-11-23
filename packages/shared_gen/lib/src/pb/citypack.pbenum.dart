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

class RoadClass extends $pb.ProtobufEnum {
  static const RoadClass ROAD_UNKNOWN =
      RoadClass._(0, _omitEnumNames ? '' : 'ROAD_UNKNOWN');
  static const RoadClass MOTORWAY =
      RoadClass._(1, _omitEnumNames ? '' : 'MOTORWAY');
  static const RoadClass TRUNK = RoadClass._(2, _omitEnumNames ? '' : 'TRUNK');
  static const RoadClass PRIMARY =
      RoadClass._(3, _omitEnumNames ? '' : 'PRIMARY');
  static const RoadClass SECONDARY =
      RoadClass._(4, _omitEnumNames ? '' : 'SECONDARY');
  static const RoadClass TERTIARY =
      RoadClass._(5, _omitEnumNames ? '' : 'TERTIARY');
  static const RoadClass RESIDENTIAL =
      RoadClass._(6, _omitEnumNames ? '' : 'RESIDENTIAL');
  static const RoadClass SERVICE =
      RoadClass._(7, _omitEnumNames ? '' : 'SERVICE');

  static const $core.List<RoadClass> values = <RoadClass>[
    ROAD_UNKNOWN,
    MOTORWAY,
    TRUNK,
    PRIMARY,
    SECONDARY,
    TERTIARY,
    RESIDENTIAL,
    SERVICE,
  ];

  static final $core.List<RoadClass?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static RoadClass? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RoadClass._(super.value, super.name);
}

class WaterClass extends $pb.ProtobufEnum {
  static const WaterClass WATER_NONE =
      WaterClass._(0, _omitEnumNames ? '' : 'WATER_NONE');
  static const WaterClass WATER_SEA =
      WaterClass._(1, _omitEnumNames ? '' : 'WATER_SEA');
  static const WaterClass WATER_RIVER =
      WaterClass._(2, _omitEnumNames ? '' : 'WATER_RIVER');
  static const WaterClass WATER_CANAL =
      WaterClass._(3, _omitEnumNames ? '' : 'WATER_CANAL');
  static const WaterClass WATER_LAKE =
      WaterClass._(4, _omitEnumNames ? '' : 'WATER_LAKE');
  static const WaterClass WATER_SMALL =
      WaterClass._(5, _omitEnumNames ? '' : 'WATER_SMALL');

  static const $core.List<WaterClass> values = <WaterClass>[
    WATER_NONE,
    WATER_SEA,
    WATER_RIVER,
    WATER_CANAL,
    WATER_LAKE,
    WATER_SMALL,
  ];

  static final $core.List<WaterClass?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static WaterClass? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const WaterClass._(super.value, super.name);
}

class GreenClass extends $pb.ProtobufEnum {
  static const GreenClass GREEN_NONE =
      GreenClass._(0, _omitEnumNames ? '' : 'GREEN_NONE');
  static const GreenClass GREEN_WOOD =
      GreenClass._(1, _omitEnumNames ? '' : 'GREEN_WOOD');
  static const GreenClass GREEN_PARKLAND =
      GreenClass._(2, _omitEnumNames ? '' : 'GREEN_PARKLAND');
  static const GreenClass GREEN_GARDEN =
      GreenClass._(3, _omitEnumNames ? '' : 'GREEN_GARDEN');
  static const GreenClass GREEN_CEMETERY =
      GreenClass._(4, _omitEnumNames ? '' : 'GREEN_CEMETERY');
  static const GreenClass GREEN_GRASS =
      GreenClass._(5, _omitEnumNames ? '' : 'GREEN_GRASS');
  static const GreenClass GREEN_SAND =
      GreenClass._(6, _omitEnumNames ? '' : 'GREEN_SAND');

  static const $core.List<GreenClass> values = <GreenClass>[
    GREEN_NONE,
    GREEN_WOOD,
    GREEN_PARKLAND,
    GREEN_GARDEN,
    GREEN_CEMETERY,
    GREEN_GRASS,
    GREEN_SAND,
  ];

  static final $core.List<GreenClass?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static GreenClass? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GreenClass._(super.value, super.name);
}

class Surface extends $pb.ProtobufEnum {
  static const Surface SURFACE_ASPHALT =
      Surface._(0, _omitEnumNames ? '' : 'SURFACE_ASPHALT');
  static const Surface SURFACE_GRASS =
      Surface._(1, _omitEnumNames ? '' : 'SURFACE_GRASS');
  static const Surface SURFACE_SAND =
      Surface._(2, _omitEnumNames ? '' : 'SURFACE_SAND');
  static const Surface SURFACE_DIRT =
      Surface._(3, _omitEnumNames ? '' : 'SURFACE_DIRT');
  static const Surface SURFACE_FOREST =
      Surface._(4, _omitEnumNames ? '' : 'SURFACE_FOREST');

  static const $core.List<Surface> values = <Surface>[
    SURFACE_ASPHALT,
    SURFACE_GRASS,
    SURFACE_SAND,
    SURFACE_DIRT,
    SURFACE_FOREST,
  ];

  static final $core.List<Surface?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static Surface? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Surface._(super.value, super.name);
}

class GroundKind extends $pb.ProtobufEnum {
  static const GroundKind GROUND_UNKNOWN =
      GroundKind._(0, _omitEnumNames ? '' : 'GROUND_UNKNOWN');
  static const GroundKind LAND = GroundKind._(1, _omitEnumNames ? '' : 'LAND');
  static const GroundKind WATER =
      GroundKind._(2, _omitEnumNames ? '' : 'WATER');
  static const GroundKind PARK = GroundKind._(3, _omitEnumNames ? '' : 'PARK');
  static const GroundKind RAIL = GroundKind._(4, _omitEnumNames ? '' : 'RAIL');
  static const GroundKind PLAZA =
      GroundKind._(5, _omitEnumNames ? '' : 'PLAZA');
  static const GroundKind PEDESTRIAN =
      GroundKind._(6, _omitEnumNames ? '' : 'PEDESTRIAN');

  static const $core.List<GroundKind> values = <GroundKind>[
    GROUND_UNKNOWN,
    LAND,
    WATER,
    PARK,
    RAIL,
    PLAZA,
    PEDESTRIAN,
  ];

  static final $core.List<GroundKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static GroundKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GroundKind._(super.value, super.name);
}

class LodKind extends $pb.ProtobufEnum {
  static const LodKind LOD_BLOCK =
      LodKind._(0, _omitEnumNames ? '' : 'LOD_BLOCK');
  static const LodKind LOD_WOOD =
      LodKind._(1, _omitEnumNames ? '' : 'LOD_WOOD');
  static const LodKind LOD_PARKLAND =
      LodKind._(2, _omitEnumNames ? '' : 'LOD_PARKLAND');

  static const $core.List<LodKind> values = <LodKind>[
    LOD_BLOCK,
    LOD_WOOD,
    LOD_PARKLAND,
  ];

  static final $core.List<LodKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static LodKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LodKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
