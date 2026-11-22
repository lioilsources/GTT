import type { TuningStyle } from '../gen/tuning';
import type { Rgba } from './palette';

/**
 * Risograph look of a city skin (specs/style.md "Risograf"). Pure part: the on/off rule, the
 * uniforms and the fragment shader source; worldView.ts runs it as one post-process pass over the
 * world layer only.
 */

/** `style.risograph.<city>` is true and it is day; unknown cities and the night never get it. */
export function risographOn(style: TuningStyle, cityId: string, night: boolean): boolean {
  if (night) return false;
  if (!Object.prototype.hasOwnProperty.call(style.risograph, cityId)) return false;
  return (style.risograph as unknown as Record<string, unknown>)[cityId] === true;
}

/** Shader uniforms; pixel sizes are physical pixels (tuning px × device pixel ratio). */
export interface RisographUniforms {
  ink: readonly [number, number, number];
  offsetPx: number;
  fringe: number;
  cellPx: number;
  halftoneStrength: number;
  halftoneLow: number;
  halftoneHigh: number;
  grainPx: number;
  grainStrength: number;
}

/** [dpr] = physical pixels per CSS pixel (W: 1 / engine hardware scaling level). */
export function risographUniforms(style: TuningStyle, ink: Rgba, dpr: number): RisographUniforms {
  const s = Math.max(dpr, 1e-3);
  return {
    ink: [ink[0], ink[1], ink[2]],
    offsetPx: style.misregistrationPx * s,
    fringe: style.fringe,
    cellPx: Math.max(style.halftoneCellPx * s, 1),
    halftoneStrength: style.halftoneStrength,
    halftoneLow: style.halftoneLow,
    halftoneHigh: style.halftoneHigh,
    grainPx: Math.max(style.grainSizePx * s, 1),
    grainStrength: style.grainStrength,
  };
}

export const RISOGRAPH_UNIFORMS = [
  'ink', 'offsetPx', 'fringe', 'cellPx', 'halftoneStrength', 'halftoneLow', 'halftoneHigh', 'grainPx', 'grainStrength',
] as const;

/**
 * One pass, two texture reads: (1) misregistration fringe of inks[0] next to luminance edges,
 * (2) halftone dots in the midtones, radius ∝ 1 − lum (lum 0 fills the cell), (3) grain from a
 * hash of the grain cell, fixed to the screen.
 */
export const RISOGRAPH_FRAGMENT = /* glsl */ `
precision highp float;
varying vec2 vUV;
uniform sampler2D textureSampler;
uniform vec2 texelSize;
uniform vec3 ink;
uniform float offsetPx;
uniform float fringe;
uniform float cellPx;
uniform float halftoneStrength;
uniform float halftoneLow;
uniform float halftoneHigh;
uniform float grainPx;
uniform float grainStrength;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash(vec2 p) {
  p = fract(p * vec2(0.1031, 0.1030));
  p += dot(p, p.yx + 33.33);
  return fract((p.x + p.y) * p.x);
}

void main(void) {
  vec3 c = texture2D(textureSampler, vUV).rgb;
  float l0 = lum(c);
  vec3 c2 = texture2D(textureSampler, vUV + vec2(offsetPx, offsetPx * 0.5) * texelSize).rgb;
  float e = min(1.0, abs(lum(c2) - l0) * 4.0);
  c = mix(c, ink, fringe * e);

  vec2 px = gl_FragCoord.xy;
  float l = lum(c);
  if (l >= halftoneLow && l <= halftoneHigh) {
    vec2 q = (fract(px / cellPx) - 0.5) * cellPx;
    float r = (1.0 - l) * cellPx * 0.7071;
    if (dot(q, q) <= r * r) c *= 1.0 - halftoneStrength;
  }

  float n = hash(floor(px / grainPx)) * 2.0 - 1.0;
  c += n * grainStrength;
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
`;

/** Layer masks (specs/style.md "Risograf"): world meshes sit outside Babylon's default mask 0x0FFFFFFF. */
export const WORLD_LAYER = 0x10000000;
export const DEPTH_LAYER = 0x20000000;
export const DYNAMIC_LAYERS = 0x0fffffff;
export const ALL_LAYERS = 0xffffffff;

/** Layer mask of the main camera: only the world under the risograph, otherwise every layer. */
export function mainCameraMask(risograph: boolean): number {
  return risograph ? WORLD_LAYER : ALL_LAYERS;
}
