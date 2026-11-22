import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// specs/style.md "Risograf": MetropoleGame._risographFilter writes floats 2..13 after uSize.
void main() {
  test('risograph shader compiles and has uSize + 12 float uniforms', () async {
    final program = await ui.FragmentProgram.fromAsset('shaders/risograph.frag');
    final sh = program.fragmentShader();
    for (var i = 0; i < 14; i++) {
      sh.setFloat(i, 0);
    }
    expect(() => sh.setFloat(14, 0), throwsA(anything));
  });
}
