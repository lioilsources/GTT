#version 460 core
// Risograph pass over the world layer (specs/style.md v1 "Risograf"). Used as
// ImageFilter.shader on a saveLayer, so the engine sets uSize and uTexture.
// Lengths arrive in logical px and are scaled by uDpr here (FlutterFragCoord is physical px).
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uDpr;
uniform float uMisreg;       // style.misregistration_px
uniform float uFringe;       // style.fringe
uniform float uGrainStrength;
uniform float uGrainSize;    // style.grain_size_px
uniform float uCell;         // style.halftone_cell_px
uniform float uHtStrength;
uniform float uHtLow;
uniform float uHtHigh;
uniform vec3 uInk;           // color.city.<id>.inks[0]
uniform sampler2D uTexture;

out vec4 fragColor;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec4 sampleAt(vec2 p) {
  vec2 uv = p / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, uv);
}

// Deterministic hash of a cell, -1..1 (stable between frames, stuck to the screen).
float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y) * 2.0 - 1.0;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec4 src = sampleAt(p);
  if (src.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 c = src.rgb / src.a;

  // 1. Misregistration: a thin fringe of the first ink next to contours. Premultiplied luminance,
  // so a building edge against the empty part of its layer counts as a contour too.
  float o = uMisreg * uDpr;
  float e = min(1.0, abs(lum(sampleAt(p + vec2(o, o * 0.5)).rgb) - lum(src.rgb)) * 4.0);
  c = mix(c, uInk, uFringe * e);

  // 2. Halftone: dot radius proportional to 1 - lum, midtones only.
  float cell = max(1.0, uCell * uDpr);
  float l = lum(c);
  if (l >= uHtLow && l <= uHtHigh) {
    vec2 d = (fract(p / cell) - 0.5) * cell;
    if (length(d) <= (1.0 - l) * cell * 0.7071) c *= 1.0 - uHtStrength;
  }

  // 3. Grain.
  float n = hash(floor(p / max(1.0, uGrainSize * uDpr)));
  c = clamp(c + n * uGrainStrength, 0.0, 1.0);

  fragColor = vec4(c * src.a, src.a);
}
