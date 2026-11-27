// This is a generated file - do not edit.
//
// Generated from citypack.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use roadClassDescriptor instead')
const RoadClass$json = {
  '1': 'RoadClass',
  '2': [
    {'1': 'ROAD_UNKNOWN', '2': 0},
    {'1': 'MOTORWAY', '2': 1},
    {'1': 'TRUNK', '2': 2},
    {'1': 'PRIMARY', '2': 3},
    {'1': 'SECONDARY', '2': 4},
    {'1': 'TERTIARY', '2': 5},
    {'1': 'RESIDENTIAL', '2': 6},
    {'1': 'SERVICE', '2': 7},
  ],
};

/// Descriptor for `RoadClass`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List roadClassDescriptor = $convert.base64Decode(
    'CglSb2FkQ2xhc3MSEAoMUk9BRF9VTktOT1dOEAASDAoITU9UT1JXQVkQARIJCgVUUlVOSxACEg'
    'sKB1BSSU1BUlkQAxINCglTRUNPTkRBUlkQBBIMCghURVJUSUFSWRAFEg8KC1JFU0lERU5USUFM'
    'EAYSCwoHU0VSVklDRRAH');

@$core.Deprecated('Use waterClassDescriptor instead')
const WaterClass$json = {
  '1': 'WaterClass',
  '2': [
    {'1': 'WATER_NONE', '2': 0},
    {'1': 'WATER_SEA', '2': 1},
    {'1': 'WATER_RIVER', '2': 2},
    {'1': 'WATER_CANAL', '2': 3},
    {'1': 'WATER_LAKE', '2': 4},
    {'1': 'WATER_SMALL', '2': 5},
  ],
};

/// Descriptor for `WaterClass`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List waterClassDescriptor = $convert.base64Decode(
    'CgpXYXRlckNsYXNzEg4KCldBVEVSX05PTkUQABINCglXQVRFUl9TRUEQARIPCgtXQVRFUl9SSV'
    'ZFUhACEg8KC1dBVEVSX0NBTkFMEAMSDgoKV0FURVJfTEFLRRAEEg8KC1dBVEVSX1NNQUxMEAU=');

@$core.Deprecated('Use greenClassDescriptor instead')
const GreenClass$json = {
  '1': 'GreenClass',
  '2': [
    {'1': 'GREEN_NONE', '2': 0},
    {'1': 'GREEN_WOOD', '2': 1},
    {'1': 'GREEN_PARKLAND', '2': 2},
    {'1': 'GREEN_GARDEN', '2': 3},
    {'1': 'GREEN_CEMETERY', '2': 4},
    {'1': 'GREEN_GRASS', '2': 5},
    {'1': 'GREEN_SAND', '2': 6},
  ],
};

/// Descriptor for `GreenClass`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List greenClassDescriptor = $convert.base64Decode(
    'CgpHcmVlbkNsYXNzEg4KCkdSRUVOX05PTkUQABIOCgpHUkVFTl9XT09EEAESEgoOR1JFRU5fUE'
    'FSS0xBTkQQAhIQCgxHUkVFTl9HQVJERU4QAxISCg5HUkVFTl9DRU1FVEVSWRAEEg8KC0dSRUVO'
    'X0dSQVNTEAUSDgoKR1JFRU5fU0FORBAG');

@$core.Deprecated('Use surfaceDescriptor instead')
const Surface$json = {
  '1': 'Surface',
  '2': [
    {'1': 'SURFACE_ASPHALT', '2': 0},
    {'1': 'SURFACE_GRASS', '2': 1},
    {'1': 'SURFACE_SAND', '2': 2},
    {'1': 'SURFACE_DIRT', '2': 3},
    {'1': 'SURFACE_FOREST', '2': 4},
  ],
};

/// Descriptor for `Surface`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List surfaceDescriptor = $convert.base64Decode(
    'CgdTdXJmYWNlEhMKD1NVUkZBQ0VfQVNQSEFMVBAAEhEKDVNVUkZBQ0VfR1JBU1MQARIQCgxTVV'
    'JGQUNFX1NBTkQQAhIQCgxTVVJGQUNFX0RJUlQQAxISCg5TVVJGQUNFX0ZPUkVTVBAE');

@$core.Deprecated('Use groundKindDescriptor instead')
const GroundKind$json = {
  '1': 'GroundKind',
  '2': [
    {'1': 'GROUND_UNKNOWN', '2': 0},
    {'1': 'LAND', '2': 1},
    {'1': 'WATER', '2': 2},
    {'1': 'PARK', '2': 3},
    {'1': 'RAIL', '2': 4},
    {'1': 'PLAZA', '2': 5},
    {'1': 'PEDESTRIAN', '2': 6},
  ],
};

/// Descriptor for `GroundKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List groundKindDescriptor = $convert.base64Decode(
    'CgpHcm91bmRLaW5kEhIKDkdST1VORF9VTktOT1dOEAASCAoETEFORBABEgkKBVdBVEVSEAISCA'
    'oEUEFSSxADEggKBFJBSUwQBBIJCgVQTEFaQRAFEg4KClBFREVTVFJJQU4QBg==');

@$core.Deprecated('Use lodKindDescriptor instead')
const LodKind$json = {
  '1': 'LodKind',
  '2': [
    {'1': 'LOD_BLOCK', '2': 0},
    {'1': 'LOD_WOOD', '2': 1},
    {'1': 'LOD_PARKLAND', '2': 2},
  ],
};

/// Descriptor for `LodKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List lodKindDescriptor = $convert.base64Decode(
    'CgdMb2RLaW5kEg0KCUxPRF9CTE9DSxAAEgwKCExPRF9XT09EEAESEAoMTE9EX1BBUktMQU5EEA'
    'I=');

@$core.Deprecated('Use modelSourceDescriptor instead')
const ModelSource$json = {
  '1': 'ModelSource',
  '2': [
    {'1': 'MODEL_SOURCE_UNKNOWN', '2': 0},
    {'1': 'MODEL_SOURCE_IPR_PRAHA_3D', '2': 1},
    {'1': 'MODEL_SOURCE_NYC_3D', '2': 2},
    {'1': 'MODEL_SOURCE_PLATEAU', '2': 3},
    {'1': 'MODEL_SOURCE_OVERTURE_PARTS', '2': 4},
    {'1': 'MODEL_SOURCE_MANUAL', '2': 5},
  ],
};

/// Descriptor for `ModelSource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelSourceDescriptor = $convert.base64Decode(
    'CgtNb2RlbFNvdXJjZRIYChRNT0RFTF9TT1VSQ0VfVU5LTk9XThAAEh0KGU1PREVMX1NPVVJDRV'
    '9JUFJfUFJBSEFfM0QQARIXChNNT0RFTF9TT1VSQ0VfTllDXzNEEAISGAoUTU9ERUxfU09VUkNF'
    'X1BMQVRFQVUQAxIfChtNT0RFTF9TT1VSQ0VfT1ZFUlRVUkVfUEFSVFMQBBIXChNNT0RFTF9TT1'
    'VSQ0VfTUFOVUFMEAU=');

@$core.Deprecated('Use modelRoleDescriptor instead')
const ModelRole$json = {
  '1': 'ModelRole',
  '2': [
    {'1': 'ROLE_WALL', '2': 0},
    {'1': 'ROLE_ROOF', '2': 1},
    {'1': 'ROLE_COPPER', '2': 2},
    {'1': 'ROLE_STONE', '2': 3},
    {'1': 'ROLE_GLASS', '2': 4},
    {'1': 'ROLE_GOLD', '2': 5},
    {'1': 'ROLE_SLATE', '2': 6},
  ],
};

/// Descriptor for `ModelRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelRoleDescriptor = $convert.base64Decode(
    'CglNb2RlbFJvbGUSDQoJUk9MRV9XQUxMEAASDQoJUk9MRV9ST09GEAESDwoLUk9MRV9DT1BQRV'
    'IQAhIOCgpST0xFX1NUT05FEAMSDgoKUk9MRV9HTEFTUxAEEg0KCVJPTEVfR09MRBAFEg4KClJP'
    'TEVfU0xBVEUQBg==');

@$core.Deprecated('Use modelSurfaceDescriptor instead')
const ModelSurface$json = {
  '1': 'ModelSurface',
  '2': [
    {'1': 'SURFACE_WALL', '2': 0},
    {'1': 'SURFACE_ROOF', '2': 1},
  ],
};

/// Descriptor for `ModelSurface`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelSurfaceDescriptor = $convert.base64Decode(
    'CgxNb2RlbFN1cmZhY2USEAoMU1VSRkFDRV9XQUxMEAASEAoMU1VSRkFDRV9ST09GEAE=');

@$core.Deprecated('Use manifestDescriptor instead')
const Manifest$json = {
  '1': 'Manifest',
  '2': [
    {'1': 'format_version', '3': 1, '4': 1, '5': 13, '10': 'formatVersion'},
    {'1': 'city_id', '3': 2, '4': 1, '5': 9, '10': 'cityId'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
    {'1': 'origin_lat', '3': 4, '4': 1, '5': 1, '10': 'originLat'},
    {'1': 'origin_lon', '3': 5, '4': 1, '5': 1, '10': 'originLon'},
    {'1': 'drive_side', '3': 6, '4': 1, '5': 9, '10': 'driveSide'},
    {'1': 'units', '3': 7, '4': 1, '5': 9, '10': 'units'},
    {'1': 'overture_release', '3': 8, '4': 1, '5': 9, '10': 'overtureRelease'},
    {'1': 'chunk_m', '3': 9, '4': 1, '5': 13, '10': 'chunkM'},
    {
      '1': 'bounds',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.citypack.Rect',
      '10': 'bounds'
    },
    {'1': 'area', '3': 11, '4': 3, '5': 17, '10': 'area'},
    {
      '1': 'chunks',
      '3': 12,
      '4': 3,
      '5': 11,
      '6': '.citypack.ChunkRef',
      '10': 'chunks'
    },
    {
      '1': 'start',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.citypack.Spawn',
      '10': 'start'
    },
    {
      '1': 'districts',
      '3': 14,
      '4': 3,
      '5': 11,
      '6': '.citypack.District',
      '10': 'districts'
    },
    {'1': 'attribution', '3': 15, '4': 3, '5': 9, '10': 'attribution'},
    {'1': 'built_at', '3': 16, '4': 1, '5': 9, '10': 'builtAt'},
    {'1': 'terrain_version', '3': 17, '4': 1, '5': 13, '10': 'terrainVersion'},
    {'1': 'z0_m', '3': 18, '4': 1, '5': 2, '10': 'z0M'},
    {'1': 'exaggeration', '3': 19, '4': 1, '5': 2, '10': 'exaggeration'},
    {'1': 'terrain_grid_m', '3': 20, '4': 1, '5': 13, '10': 'terrainGridM'},
    {'1': 'nature_version', '3': 21, '4': 1, '5': 13, '10': 'natureVersion'},
    {
      '1': 'lods',
      '3': 22,
      '4': 3,
      '5': 11,
      '6': '.citypack.ChunkRef',
      '10': 'lods'
    },
    {'1': 'lod_chunks', '3': 23, '4': 1, '5': 13, '10': 'lodChunks'},
    {'1': 'lod_grid_m', '3': 24, '4': 1, '5': 13, '10': 'lodGridM'},
    {'1': 'models_version', '3': 25, '4': 1, '5': 13, '10': 'modelsVersion'},
  ],
};

/// Descriptor for `Manifest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List manifestDescriptor = $convert.base64Decode(
    'CghNYW5pZmVzdBIlCg5mb3JtYXRfdmVyc2lvbhgBIAEoDVINZm9ybWF0VmVyc2lvbhIXCgdjaX'
    'R5X2lkGAIgASgJUgZjaXR5SWQSEgoEbmFtZRgDIAEoCVIEbmFtZRIdCgpvcmlnaW5fbGF0GAQg'
    'ASgBUglvcmlnaW5MYXQSHQoKb3JpZ2luX2xvbhgFIAEoAVIJb3JpZ2luTG9uEh0KCmRyaXZlX3'
    'NpZGUYBiABKAlSCWRyaXZlU2lkZRIUCgV1bml0cxgHIAEoCVIFdW5pdHMSKQoQb3ZlcnR1cmVf'
    'cmVsZWFzZRgIIAEoCVIPb3ZlcnR1cmVSZWxlYXNlEhcKB2NodW5rX20YCSABKA1SBmNodW5rTR'
    'ImCgZib3VuZHMYCiABKAsyDi5jaXR5cGFjay5SZWN0UgZib3VuZHMSEgoEYXJlYRgLIAMoEVIE'
    'YXJlYRIqCgZjaHVua3MYDCADKAsyEi5jaXR5cGFjay5DaHVua1JlZlIGY2h1bmtzEiUKBXN0YX'
    'J0GA0gASgLMg8uY2l0eXBhY2suU3Bhd25SBXN0YXJ0EjAKCWRpc3RyaWN0cxgOIAMoCzISLmNp'
    'dHlwYWNrLkRpc3RyaWN0UglkaXN0cmljdHMSIAoLYXR0cmlidXRpb24YDyADKAlSC2F0dHJpYn'
    'V0aW9uEhkKCGJ1aWx0X2F0GBAgASgJUgdidWlsdEF0EicKD3RlcnJhaW5fdmVyc2lvbhgRIAEo'
    'DVIOdGVycmFpblZlcnNpb24SEQoEejBfbRgSIAEoAlIDejBNEiIKDGV4YWdnZXJhdGlvbhgTIA'
    'EoAlIMZXhhZ2dlcmF0aW9uEiQKDnRlcnJhaW5fZ3JpZF9tGBQgASgNUgx0ZXJyYWluR3JpZE0S'
    'JQoObmF0dXJlX3ZlcnNpb24YFSABKA1SDW5hdHVyZVZlcnNpb24SJgoEbG9kcxgWIAMoCzISLm'
    'NpdHlwYWNrLkNodW5rUmVmUgRsb2RzEh0KCmxvZF9jaHVua3MYFyABKA1SCWxvZENodW5rcxIc'
    'Cgpsb2RfZ3JpZF9tGBggASgNUghsb2RHcmlkTRIlCg5tb2RlbHNfdmVyc2lvbhgZIAEoDVINbW'
    '9kZWxzVmVyc2lvbg==');

@$core.Deprecated('Use rectDescriptor instead')
const Rect$json = {
  '1': 'Rect',
  '2': [
    {'1': 'min_x', '3': 1, '4': 1, '5': 17, '10': 'minX'},
    {'1': 'min_y', '3': 2, '4': 1, '5': 17, '10': 'minY'},
    {'1': 'max_x', '3': 3, '4': 1, '5': 17, '10': 'maxX'},
    {'1': 'max_y', '3': 4, '4': 1, '5': 17, '10': 'maxY'},
  ],
};

/// Descriptor for `Rect`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rectDescriptor = $convert.base64Decode(
    'CgRSZWN0EhMKBW1pbl94GAEgASgRUgRtaW5YEhMKBW1pbl95GAIgASgRUgRtaW5ZEhMKBW1heF'
    '94GAMgASgRUgRtYXhYEhMKBW1heF95GAQgASgRUgRtYXhZ');

@$core.Deprecated('Use chunkRefDescriptor instead')
const ChunkRef$json = {
  '1': 'ChunkRef',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 17, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 17, '10': 'y'},
    {'1': 'bytes', '3': 3, '4': 1, '5': 13, '10': 'bytes'},
    {'1': 'buildings', '3': 4, '4': 1, '5': 13, '10': 'buildings'},
  ],
};

/// Descriptor for `ChunkRef`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chunkRefDescriptor = $convert.base64Decode(
    'CghDaHVua1JlZhIMCgF4GAEgASgRUgF4EgwKAXkYAiABKBFSAXkSFAoFYnl0ZXMYAyABKA1SBW'
    'J5dGVzEhwKCWJ1aWxkaW5ncxgEIAEoDVIJYnVpbGRpbmdz');

@$core.Deprecated('Use spawnDescriptor instead')
const Spawn$json = {
  '1': 'Spawn',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 17, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 17, '10': 'y'},
    {'1': 'heading_rad', '3': 3, '4': 1, '5': 2, '10': 'headingRad'},
  ],
};

/// Descriptor for `Spawn`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List spawnDescriptor = $convert.base64Decode(
    'CgVTcGF3bhIMCgF4GAEgASgRUgF4EgwKAXkYAiABKBFSAXkSHwoLaGVhZGluZ19yYWQYAyABKA'
    'JSCmhlYWRpbmdSYWQ=');

@$core.Deprecated('Use districtDescriptor instead')
const District$json = {
  '1': 'District',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'ring', '3': 2, '4': 3, '5': 17, '10': 'ring'},
  ],
};

/// Descriptor for `District`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List districtDescriptor = $convert.base64Decode(
    'CghEaXN0cmljdBISCgRuYW1lGAEgASgJUgRuYW1lEhIKBHJpbmcYAiADKBFSBHJpbmc=');

@$core.Deprecated('Use graphDescriptor instead')
const Graph$json = {
  '1': 'Graph',
  '2': [
    {
      '1': 'nodes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.citypack.Node',
      '10': 'nodes'
    },
    {
      '1': 'edges',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.citypack.Edge',
      '10': 'edges'
    },
    {'1': 'names', '3': 3, '4': 3, '5': 9, '10': 'names'},
  ],
};

/// Descriptor for `Graph`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List graphDescriptor = $convert.base64Decode(
    'CgVHcmFwaBIkCgVub2RlcxgBIAMoCzIOLmNpdHlwYWNrLk5vZGVSBW5vZGVzEiQKBWVkZ2VzGA'
    'IgAygLMg4uY2l0eXBhY2suRWRnZVIFZWRnZXMSFAoFbmFtZXMYAyADKAlSBW5hbWVz');

@$core.Deprecated('Use nodeDescriptor instead')
const Node$json = {
  '1': 'Node',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 17, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 17, '10': 'y'},
    {'1': 'border', '3': 3, '4': 1, '5': 8, '10': 'border'},
    {'1': 'z_dm', '3': 4, '4': 1, '5': 17, '10': 'zDm'},
  ],
};

/// Descriptor for `Node`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nodeDescriptor = $convert.base64Decode(
    'CgROb2RlEgwKAXgYASABKBFSAXgSDAoBeRgCIAEoEVIBeRIWCgZib3JkZXIYAyABKAhSBmJvcm'
    'RlchIRCgR6X2RtGAQgASgRUgN6RG0=');

@$core.Deprecated('Use edgeDescriptor instead')
const Edge$json = {
  '1': 'Edge',
  '2': [
    {'1': 'from', '3': 1, '4': 1, '5': 13, '10': 'from'},
    {'1': 'to', '3': 2, '4': 1, '5': 13, '10': 'to'},
    {'1': 'points', '3': 3, '4': 3, '5': 17, '10': 'points'},
    {
      '1': 'class',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.citypack.RoadClass',
      '10': 'class'
    },
    {'1': 'name', '3': 5, '4': 1, '5': 13, '10': 'name'},
    {'1': 'lanes', '3': 6, '4': 1, '5': 13, '10': 'lanes'},
    {'1': 'oneway', '3': 7, '4': 1, '5': 17, '10': 'oneway'},
    {'1': 'layer_from', '3': 8, '4': 1, '5': 17, '10': 'layerFrom'},
    {'1': 'layer_to', '3': 9, '4': 1, '5': 17, '10': 'layerTo'},
    {'1': 'bridge', '3': 10, '4': 1, '5': 8, '10': 'bridge'},
    {'1': 'tunnel', '3': 11, '4': 1, '5': 8, '10': 'tunnel'},
    {'1': 'kept', '3': 12, '4': 1, '5': 8, '10': 'kept'},
    {'1': 'width_m', '3': 13, '4': 1, '5': 2, '10': 'widthM'},
    {'1': 'z_dm', '3': 14, '4': 3, '5': 17, '10': 'zDm'},
    {'1': 'stairs', '3': 15, '4': 1, '5': 8, '10': 'stairs'},
    {'1': 'micro_only', '3': 16, '4': 1, '5': 8, '10': 'microOnly'},
  ],
};

/// Descriptor for `Edge`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List edgeDescriptor = $convert.base64Decode(
    'CgRFZGdlEhIKBGZyb20YASABKA1SBGZyb20SDgoCdG8YAiABKA1SAnRvEhYKBnBvaW50cxgDIA'
    'MoEVIGcG9pbnRzEikKBWNsYXNzGAQgASgOMhMuY2l0eXBhY2suUm9hZENsYXNzUgVjbGFzcxIS'
    'CgRuYW1lGAUgASgNUgRuYW1lEhQKBWxhbmVzGAYgASgNUgVsYW5lcxIWCgZvbmV3YXkYByABKB'
    'FSBm9uZXdheRIdCgpsYXllcl9mcm9tGAggASgRUglsYXllckZyb20SGQoIbGF5ZXJfdG8YCSAB'
    'KBFSB2xheWVyVG8SFgoGYnJpZGdlGAogASgIUgZicmlkZ2USFgoGdHVubmVsGAsgASgIUgZ0dW'
    '5uZWwSEgoEa2VwdBgMIAEoCFIEa2VwdBIXCgd3aWR0aF9tGA0gASgCUgZ3aWR0aE0SEQoEel9k'
    'bRgOIAMoEVIDekRtEhYKBnN0YWlycxgPIAEoCFIGc3RhaXJzEh0KCm1pY3JvX29ubHkYECABKA'
    'hSCW1pY3JvT25seQ==');

@$core.Deprecated('Use chunkDescriptor instead')
const Chunk$json = {
  '1': 'Chunk',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 17, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 17, '10': 'y'},
    {
      '1': 'buildings',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.citypack.Building',
      '10': 'buildings'
    },
    {
      '1': 'ground',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.citypack.Mesh',
      '10': 'ground'
    },
    {
      '1': 'barriers',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.citypack.Barrier',
      '10': 'barriers'
    },
    {'1': 'terrain', '3': 6, '4': 1, '5': 12, '10': 'terrain'},
    {'1': 'shade', '3': 7, '4': 1, '5': 12, '10': 'shade'},
    {'1': 'trees', '3': 8, '4': 1, '5': 12, '10': 'trees'},
    {
      '1': 'shore',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.citypack.Mesh',
      '10': 'shore'
    },
    {
      '1': 'labels',
      '3': 10,
      '4': 3,
      '5': 11,
      '6': '.citypack.Label',
      '10': 'labels'
    },
  ],
};

/// Descriptor for `Chunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chunkDescriptor = $convert.base64Decode(
    'CgVDaHVuaxIMCgF4GAEgASgRUgF4EgwKAXkYAiABKBFSAXkSMAoJYnVpbGRpbmdzGAMgAygLMh'
    'IuY2l0eXBhY2suQnVpbGRpbmdSCWJ1aWxkaW5ncxImCgZncm91bmQYBCADKAsyDi5jaXR5cGFj'
    'ay5NZXNoUgZncm91bmQSLQoIYmFycmllcnMYBSADKAsyES5jaXR5cGFjay5CYXJyaWVyUghiYX'
    'JyaWVycxIYCgd0ZXJyYWluGAYgASgMUgd0ZXJyYWluEhQKBXNoYWRlGAcgASgMUgVzaGFkZRIU'
    'CgV0cmVlcxgIIAEoDFIFdHJlZXMSJAoFc2hvcmUYCSADKAsyDi5jaXR5cGFjay5NZXNoUgVzaG'
    '9yZRInCgZsYWJlbHMYCiADKAsyDy5jaXR5cGFjay5MYWJlbFIGbGFiZWxz');

@$core.Deprecated('Use labelDescriptor instead')
const Label$json = {
  '1': 'Label',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'axis', '3': 2, '4': 3, '5': 17, '10': 'axis'},
    {'1': 'water', '3': 3, '4': 1, '5': 8, '10': 'water'},
    {'1': 'area_m2', '3': 4, '4': 1, '5': 13, '10': 'areaM2'},
  ],
};

/// Descriptor for `Label`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List labelDescriptor = $convert.base64Decode(
    'CgVMYWJlbBISCgRuYW1lGAEgASgJUgRuYW1lEhIKBGF4aXMYAiADKBFSBGF4aXMSFAoFd2F0ZX'
    'IYAyABKAhSBXdhdGVyEhcKB2FyZWFfbTIYBCABKA1SBmFyZWFNMg==');

@$core.Deprecated('Use barrierDescriptor instead')
const Barrier$json = {
  '1': 'Barrier',
  '2': [
    {'1': 'points', '3': 1, '4': 3, '5': 17, '10': 'points'},
  ],
};

/// Descriptor for `Barrier`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List barrierDescriptor =
    $convert.base64Decode('CgdCYXJyaWVyEhYKBnBvaW50cxgBIAMoEVIGcG9pbnRz');

@$core.Deprecated('Use buildingDescriptor instead')
const Building$json = {
  '1': 'Building',
  '2': [
    {'1': 'rings', '3': 1, '4': 3, '5': 17, '10': 'rings'},
    {'1': 'ring_ends', '3': 2, '4': 3, '5': 13, '10': 'ringEnds'},
    {'1': 'roof', '3': 3, '4': 3, '5': 13, '10': 'roof'},
    {'1': 'height_m', '3': 4, '4': 1, '5': 2, '10': 'heightM'},
    {'1': 'min_height_m', '3': 5, '4': 1, '5': 2, '10': 'minHeightM'},
    {'1': 'landmark', '3': 6, '4': 1, '5': 13, '10': 'landmark'},
    {'1': 'collide', '3': 7, '4': 1, '5': 8, '10': 'collide'},
    {'1': 'wall_seed', '3': 8, '4': 1, '5': 13, '10': 'wallSeed'},
    {'1': 'base_z_dm', '3': 9, '4': 1, '5': 17, '10': 'baseZDm'},
  ],
};

/// Descriptor for `Building`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List buildingDescriptor = $convert.base64Decode(
    'CghCdWlsZGluZxIUCgVyaW5ncxgBIAMoEVIFcmluZ3MSGwoJcmluZ19lbmRzGAIgAygNUghyaW'
    '5nRW5kcxISCgRyb29mGAMgAygNUgRyb29mEhkKCGhlaWdodF9tGAQgASgCUgdoZWlnaHRNEiAK'
    'DG1pbl9oZWlnaHRfbRgFIAEoAlIKbWluSGVpZ2h0TRIaCghsYW5kbWFyaxgGIAEoDVIIbGFuZG'
    '1hcmsSGAoHY29sbGlkZRgHIAEoCFIHY29sbGlkZRIbCgl3YWxsX3NlZWQYCCABKA1SCHdhbGxT'
    'ZWVkEhoKCWJhc2Vfel9kbRgJIAEoEVIHYmFzZVpEbQ==');

@$core.Deprecated('Use meshDescriptor instead')
const Mesh$json = {
  '1': 'Mesh',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.citypack.GroundKind',
      '10': 'kind'
    },
    {'1': 'vertices', '3': 2, '4': 3, '5': 17, '10': 'vertices'},
    {'1': 'indices', '3': 3, '4': 3, '5': 13, '10': 'indices'},
    {
      '1': 'water_class',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.citypack.WaterClass',
      '10': 'waterClass'
    },
    {
      '1': 'green_class',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.citypack.GreenClass',
      '10': 'greenClass'
    },
    {
      '1': 'surface',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.citypack.Surface',
      '10': 'surface'
    },
    {'1': 'name', '3': 7, '4': 1, '5': 9, '10': 'name'},
    {'1': 'z_dm', '3': 8, '4': 1, '5': 17, '10': 'zDm'},
  ],
};

/// Descriptor for `Mesh`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List meshDescriptor = $convert.base64Decode(
    'CgRNZXNoEigKBGtpbmQYASABKA4yFC5jaXR5cGFjay5Hcm91bmRLaW5kUgRraW5kEhoKCHZlcn'
    'RpY2VzGAIgAygRUgh2ZXJ0aWNlcxIYCgdpbmRpY2VzGAMgAygNUgdpbmRpY2VzEjUKC3dhdGVy'
    'X2NsYXNzGAQgASgOMhQuY2l0eXBhY2suV2F0ZXJDbGFzc1IKd2F0ZXJDbGFzcxI1CgtncmVlbl'
    '9jbGFzcxgFIAEoDjIULmNpdHlwYWNrLkdyZWVuQ2xhc3NSCmdyZWVuQ2xhc3MSKwoHc3VyZmFj'
    'ZRgGIAEoDjIRLmNpdHlwYWNrLlN1cmZhY2VSB3N1cmZhY2USEgoEbmFtZRgHIAEoCVIEbmFtZR'
    'IRCgR6X2RtGAggASgRUgN6RG0=');

@$core.Deprecated('Use lodDescriptor instead')
const Lod$json = {
  '1': 'Lod',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 17, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 17, '10': 'y'},
    {'1': 'terrain', '3': 3, '4': 1, '5': 12, '10': 'terrain'},
    {
      '1': 'masses',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.citypack.LodMass',
      '10': 'masses'
    },
    {
      '1': 'water',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.citypack.Mesh',
      '10': 'water'
    },
  ],
};

/// Descriptor for `Lod`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lodDescriptor = $convert.base64Decode(
    'CgNMb2QSDAoBeBgBIAEoEVIBeBIMCgF5GAIgASgRUgF5EhgKB3RlcnJhaW4YAyABKAxSB3Rlcn'
    'JhaW4SKQoGbWFzc2VzGAQgAygLMhEuY2l0eXBhY2suTG9kTWFzc1IGbWFzc2VzEiQKBXdhdGVy'
    'GAUgAygLMg4uY2l0eXBhY2suTWVzaFIFd2F0ZXI=');

@$core.Deprecated('Use lodMassDescriptor instead')
const LodMass$json = {
  '1': 'LodMass',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.citypack.LodKind',
      '10': 'kind'
    },
    {'1': 'rings', '3': 2, '4': 3, '5': 17, '10': 'rings'},
    {'1': 'ring_ends', '3': 3, '4': 3, '5': 13, '10': 'ringEnds'},
    {'1': 'roof', '3': 4, '4': 3, '5': 13, '10': 'roof'},
    {'1': 'height_m', '3': 5, '4': 1, '5': 2, '10': 'heightM'},
    {'1': 'base_z_dm', '3': 6, '4': 1, '5': 17, '10': 'baseZDm'},
  ],
};

/// Descriptor for `LodMass`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lodMassDescriptor = $convert.base64Decode(
    'CgdMb2RNYXNzEiUKBGtpbmQYASABKA4yES5jaXR5cGFjay5Mb2RLaW5kUgRraW5kEhQKBXJpbm'
    'dzGAIgAygRUgVyaW5ncxIbCglyaW5nX2VuZHMYAyADKA1SCHJpbmdFbmRzEhIKBHJvb2YYBCAD'
    'KA1SBHJvb2YSGQoIaGVpZ2h0X20YBSABKAJSB2hlaWdodE0SGgoJYmFzZV96X2RtGAYgASgRUg'
    'diYXNlWkRt');

@$core.Deprecated('Use landmarksDescriptor instead')
const Landmarks$json = {
  '1': 'Landmarks',
  '2': [
    {
      '1': 'items',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.citypack.Landmark',
      '10': 'items'
    },
  ],
};

/// Descriptor for `Landmarks`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List landmarksDescriptor = $convert.base64Decode(
    'CglMYW5kbWFya3MSKAoFaXRlbXMYASADKAsyEi5jaXR5cGFjay5MYW5kbWFya1IFaXRlbXM=');

@$core.Deprecated('Use landmarkDescriptor instead')
const Landmark$json = {
  '1': 'Landmark',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'x', '3': 3, '4': 1, '5': 17, '10': 'x'},
    {'1': 'y', '3': 4, '4': 1, '5': 17, '10': 'y'},
    {'1': 'height_m', '3': 5, '4': 1, '5': 2, '10': 'heightM'},
    {'1': 'hero', '3': 6, '4': 1, '5': 8, '10': 'hero'},
    {'1': 'blurb', '3': 7, '4': 1, '5': 9, '10': 'blurb'},
  ],
};

/// Descriptor for `Landmark`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List landmarkDescriptor = $convert.base64Decode(
    'CghMYW5kbWFyaxIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIMCgF4GAMgAS'
    'gRUgF4EgwKAXkYBCABKBFSAXkSGQoIaGVpZ2h0X20YBSABKAJSB2hlaWdodE0SEgoEaGVybxgG'
    'IAEoCFIEaGVybxIUCgVibHVyYhgHIAEoCVIFYmx1cmI=');

@$core.Deprecated('Use spotsDescriptor instead')
const Spots$json = {
  '1': 'Spots',
  '2': [
    {
      '1': 'items',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.citypack.Spot',
      '10': 'items'
    },
  ],
};

/// Descriptor for `Spots`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List spotsDescriptor = $convert.base64Decode(
    'CgVTcG90cxIkCgVpdGVtcxgBIAMoCzIOLmNpdHlwYWNrLlNwb3RSBWl0ZW1z');

@$core.Deprecated('Use spotDescriptor instead')
const Spot$json = {
  '1': 'Spot',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'kind', '3': 2, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
    {'1': 'x', '3': 4, '4': 1, '5': 17, '10': 'x'},
    {'1': 'y', '3': 5, '4': 1, '5': 17, '10': 'y'},
    {'1': 'edge', '3': 6, '4': 1, '5': 13, '10': 'edge'},
    {'1': 'park_x', '3': 7, '4': 1, '5': 17, '10': 'parkX'},
    {'1': 'park_y', '3': 8, '4': 1, '5': 17, '10': 'parkY'},
    {'1': 'park_heading', '3': 9, '4': 1, '5': 2, '10': 'parkHeading'},
    {'1': 'minigame', '3': 10, '4': 1, '5': 9, '10': 'minigame'},
    {'1': 'look_x', '3': 11, '4': 1, '5': 17, '10': 'lookX'},
    {'1': 'look_y', '3': 12, '4': 1, '5': 17, '10': 'lookY'},
    {'1': 'subject_dm', '3': 13, '4': 1, '5': 13, '10': 'subjectDm'},
    {'1': 'area_name', '3': 14, '4': 1, '5': 9, '10': 'areaName'},
    {'1': 'area_water', '3': 15, '4': 1, '5': 8, '10': 'areaWater'},
  ],
};

/// Descriptor for `Spot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List spotDescriptor = $convert.base64Decode(
    'CgRTcG90Eg4KAmlkGAEgASgJUgJpZBISCgRraW5kGAIgASgJUgRraW5kEhIKBG5hbWUYAyABKA'
    'lSBG5hbWUSDAoBeBgEIAEoEVIBeBIMCgF5GAUgASgRUgF5EhIKBGVkZ2UYBiABKA1SBGVkZ2US'
    'FQoGcGFya194GAcgASgRUgVwYXJrWBIVCgZwYXJrX3kYCCABKBFSBXBhcmtZEiEKDHBhcmtfaG'
    'VhZGluZxgJIAEoAlILcGFya0hlYWRpbmcSGgoIbWluaWdhbWUYCiABKAlSCG1pbmlnYW1lEhUK'
    'Bmxvb2tfeBgLIAEoEVIFbG9va1gSFQoGbG9va195GAwgASgRUgVsb29rWRIdCgpzdWJqZWN0X2'
    'RtGA0gASgNUglzdWJqZWN0RG0SGwoJYXJlYV9uYW1lGA4gASgJUghhcmVhTmFtZRIdCgphcmVh'
    'X3dhdGVyGA8gASgIUglhcmVhV2F0ZXI=');

@$core.Deprecated('Use tramGraphDescriptor instead')
const TramGraph$json = {
  '1': 'TramGraph',
  '2': [
    {
      '1': 'nodes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.citypack.Node',
      '10': 'nodes'
    },
    {
      '1': 'edges',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.citypack.TramEdge',
      '10': 'edges'
    },
    {
      '1': 'stops',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.citypack.TramStop',
      '10': 'stops'
    },
  ],
};

/// Descriptor for `TramGraph`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tramGraphDescriptor = $convert.base64Decode(
    'CglUcmFtR3JhcGgSJAoFbm9kZXMYASADKAsyDi5jaXR5cGFjay5Ob2RlUgVub2RlcxIoCgVlZG'
    'dlcxgCIAMoCzISLmNpdHlwYWNrLlRyYW1FZGdlUgVlZGdlcxIoCgVzdG9wcxgDIAMoCzISLmNp'
    'dHlwYWNrLlRyYW1TdG9wUgVzdG9wcw==');

@$core.Deprecated('Use tramEdgeDescriptor instead')
const TramEdge$json = {
  '1': 'TramEdge',
  '2': [
    {'1': 'from', '3': 1, '4': 1, '5': 13, '10': 'from'},
    {'1': 'to', '3': 2, '4': 1, '5': 13, '10': 'to'},
    {'1': 'points', '3': 3, '4': 3, '5': 17, '10': 'points'},
    {'1': 'layer_from', '3': 4, '4': 1, '5': 17, '10': 'layerFrom'},
    {'1': 'layer_to', '3': 5, '4': 1, '5': 17, '10': 'layerTo'},
    {'1': 'bridge', '3': 6, '4': 1, '5': 8, '10': 'bridge'},
    {'1': 'tunnel', '3': 7, '4': 1, '5': 8, '10': 'tunnel'},
  ],
};

/// Descriptor for `TramEdge`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tramEdgeDescriptor = $convert.base64Decode(
    'CghUcmFtRWRnZRISCgRmcm9tGAEgASgNUgRmcm9tEg4KAnRvGAIgASgNUgJ0bxIWCgZwb2ludH'
    'MYAyADKBFSBnBvaW50cxIdCgpsYXllcl9mcm9tGAQgASgRUglsYXllckZyb20SGQoIbGF5ZXJf'
    'dG8YBSABKBFSB2xheWVyVG8SFgoGYnJpZGdlGAYgASgIUgZicmlkZ2USFgoGdHVubmVsGAcgAS'
    'gIUgZ0dW5uZWw=');

@$core.Deprecated('Use tramStopDescriptor instead')
const TramStop$json = {
  '1': 'TramStop',
  '2': [
    {'1': 'edge', '3': 1, '4': 1, '5': 13, '10': 'edge'},
    {'1': 's_m', '3': 2, '4': 1, '5': 2, '10': 'sM'},
  ],
};

/// Descriptor for `TramStop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tramStopDescriptor = $convert.base64Decode(
    'CghUcmFtU3RvcBISCgRlZGdlGAEgASgNUgRlZGdlEg8KA3NfbRgCIAEoAlICc00=');

@$core.Deprecated('Use modelsDescriptor instead')
const Models$json = {
  '1': 'Models',
  '2': [
    {
      '1': 'models',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.citypack.Model',
      '10': 'models'
    },
  ],
};

/// Descriptor for `Models`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelsDescriptor = $convert.base64Decode(
    'CgZNb2RlbHMSJwoGbW9kZWxzGAEgAygLMg8uY2l0eXBhY2suTW9kZWxSBm1vZGVscw==');

@$core.Deprecated('Use modelDescriptor instead')
const Model$json = {
  '1': 'Model',
  '2': [
    {'1': 'landmark_id', '3': 1, '4': 1, '5': 9, '10': 'landmarkId'},
    {
      '1': 'source',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.citypack.ModelSource',
      '10': 'source'
    },
    {
      '1': 'parts',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.citypack.ModelPart',
      '10': 'parts'
    },
    {
      '1': 'replaces',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.citypack.BuildingRef',
      '10': 'replaces'
    },
    {
      '1': 'roof_plan',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.citypack.PlanPoly',
      '10': 'roofPlan'
    },
    {'1': 'tris', '3': 6, '4': 1, '5': 13, '10': 'tris'},
  ],
};

/// Descriptor for `Model`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelDescriptor = $convert.base64Decode(
    'CgVNb2RlbBIfCgtsYW5kbWFya19pZBgBIAEoCVIKbGFuZG1hcmtJZBItCgZzb3VyY2UYAiABKA'
    '4yFS5jaXR5cGFjay5Nb2RlbFNvdXJjZVIGc291cmNlEikKBXBhcnRzGAMgAygLMhMuY2l0eXBh'
    'Y2suTW9kZWxQYXJ0UgVwYXJ0cxIxCghyZXBsYWNlcxgEIAMoCzIVLmNpdHlwYWNrLkJ1aWxkaW'
    '5nUmVmUghyZXBsYWNlcxIvCglyb29mX3BsYW4YBSADKAsyEi5jaXR5cGFjay5QbGFuUG9seVII'
    'cm9vZlBsYW4SEgoEdHJpcxgGIAEoDVIEdHJpcw==');

@$core.Deprecated('Use modelPartDescriptor instead')
const ModelPart$json = {
  '1': 'ModelPart',
  '2': [
    {'1': 'anchor_x', '3': 1, '4': 1, '5': 17, '10': 'anchorX'},
    {'1': 'anchor_y', '3': 2, '4': 1, '5': 17, '10': 'anchorY'},
    {'1': 'base_z_dm', '3': 3, '4': 1, '5': 17, '10': 'baseZDm'},
    {'1': 'positions', '3': 4, '4': 3, '5': 17, '10': 'positions'},
    {'1': 'triangles', '3': 5, '4': 3, '5': 13, '10': 'triangles'},
    {'1': 'roles', '3': 6, '4': 1, '5': 12, '10': 'roles'},
    {'1': 'source_id', '3': 7, '4': 1, '5': 9, '10': 'sourceId'},
    {'1': 'foot', '3': 8, '4': 3, '5': 13, '10': 'foot'},
    {'1': 'surfaces', '3': 9, '4': 1, '5': 12, '10': 'surfaces'},
  ],
};

/// Descriptor for `ModelPart`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelPartDescriptor = $convert.base64Decode(
    'CglNb2RlbFBhcnQSGQoIYW5jaG9yX3gYASABKBFSB2FuY2hvclgSGQoIYW5jaG9yX3kYAiABKB'
    'FSB2FuY2hvclkSGgoJYmFzZV96X2RtGAMgASgRUgdiYXNlWkRtEhwKCXBvc2l0aW9ucxgEIAMo'
    'EVIJcG9zaXRpb25zEhwKCXRyaWFuZ2xlcxgFIAMoDVIJdHJpYW5nbGVzEhQKBXJvbGVzGAYgAS'
    'gMUgVyb2xlcxIbCglzb3VyY2VfaWQYByABKAlSCHNvdXJjZUlkEhIKBGZvb3QYCCADKA1SBGZv'
    'b3QSGgoIc3VyZmFjZXMYCSABKAxSCHN1cmZhY2Vz');

@$core.Deprecated('Use buildingRefDescriptor instead')
const BuildingRef$json = {
  '1': 'BuildingRef',
  '2': [
    {'1': 'chunk_x', '3': 1, '4': 1, '5': 17, '10': 'chunkX'},
    {'1': 'chunk_y', '3': 2, '4': 1, '5': 17, '10': 'chunkY'},
    {'1': 'index', '3': 3, '4': 1, '5': 13, '10': 'index'},
  ],
};

/// Descriptor for `BuildingRef`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List buildingRefDescriptor = $convert.base64Decode(
    'CgtCdWlsZGluZ1JlZhIXCgdjaHVua194GAEgASgRUgZjaHVua1gSFwoHY2h1bmtfeRgCIAEoEV'
    'IGY2h1bmtZEhQKBWluZGV4GAMgASgNUgVpbmRleA==');

@$core.Deprecated('Use planPolyDescriptor instead')
const PlanPoly$json = {
  '1': 'PlanPoly',
  '2': [
    {'1': 'points', '3': 1, '4': 3, '5': 17, '10': 'points'},
    {'1': 'ring_ends', '3': 2, '4': 3, '5': 13, '10': 'ringEnds'},
    {'1': 'triangles', '3': 3, '4': 3, '5': 13, '10': 'triangles'},
    {'1': 'height_m', '3': 4, '4': 1, '5': 2, '10': 'heightM'},
    {'1': 'shade', '3': 5, '4': 1, '5': 13, '10': 'shade'},
    {'1': 'base_z_dm', '3': 6, '4': 1, '5': 17, '10': 'baseZDm'},
  ],
};

/// Descriptor for `PlanPoly`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List planPolyDescriptor = $convert.base64Decode(
    'CghQbGFuUG9seRIWCgZwb2ludHMYASADKBFSBnBvaW50cxIbCglyaW5nX2VuZHMYAiADKA1SCH'
    'JpbmdFbmRzEhwKCXRyaWFuZ2xlcxgDIAMoDVIJdHJpYW5nbGVzEhkKCGhlaWdodF9tGAQgASgC'
    'UgdoZWlnaHRNEhQKBXNoYWRlGAUgASgNUgVzaGFkZRIaCgliYXNlX3pfZG0YBiABKBFSB2Jhc2'
    'VaRG0=');
