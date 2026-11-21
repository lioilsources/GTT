/// Car physics, controls, layers and street furniture (METROPOLE_PLAN 7).
///
/// Pure logic: nothing here imports Flutter or dart:ui. Drawing lives in the app.
library;

export 'package:forge2d/forge2d.dart' show initializeForge2D;

export 'src/bench.dart';
export 'src/car.dart';
export 'package:shared_gen/shared_gen.dart' show CarSpec;

export 'src/car_spec.dart';
export 'src/controls.dart';
export 'src/drive_world.dart';
export 'src/gps.dart';
export 'src/pedestrians.dart';
export 'src/props.dart';
