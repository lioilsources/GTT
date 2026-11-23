/// Car physics, controls, layers and street furniture (METROPOLE_PLAN 7).
///
/// Pure logic: nothing here imports Flutter or dart:ui. Drawing lives in the app.
library;

export 'package:forge2d/forge2d.dart' show initializeForge2D;

export 'src/bench.dart';
export 'src/car.dart';
export 'package:shared_gen/shared_gen.dart' show CarSpec;

export 'src/car_spec.dart';
export 'src/cars_rules.dart';
export 'src/fleet.dart';
export 'src/flow.dart';
export 'src/parked.dart';
export 'src/boost_hint.dart';
export 'src/controls.dart';
export 'src/drive_world.dart';
export 'src/gps.dart';
export 'src/hop.dart';
export 'src/pedestrians.dart';
export 'src/police/police.dart';
export 'src/police/roadblock.dart';
export 'src/police/rules.dart';
export 'src/police/sense.dart';
export 'src/props.dart';
export 'src/traffic/road_rules.dart';
export 'src/traffic/traffic.dart';
export 'src/trams/tram_rules.dart';
export 'src/trams/trams.dart';
export 'src/world_hits.dart';
export 'src/zones.dart';
