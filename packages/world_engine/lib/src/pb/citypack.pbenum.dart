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

  static const $core.List<GroundKind> values = <GroundKind>[
    GROUND_UNKNOWN,
    LAND,
    WATER,
    PARK,
    RAIL,
    PLAZA,
  ];

  static final $core.List<GroundKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static GroundKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GroundKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
