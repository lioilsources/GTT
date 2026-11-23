import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { MaterialPluginBase } from '@babylonjs/core/Materials/materialPluginBase';
import type { Material } from '@babylonjs/core/Materials/material';
import type { UniformBuffer } from '@babylonjs/core/Materials/uniformBuffer';
import type { SubMesh } from '@babylonjs/core/Meshes/subMesh';
import type { Scene } from '@babylonjs/core/scene';

import { FADE_COVERAGE, FADE_RADIUS_M } from './chase';

/**
 * Occluder fade of the chase camera (specs/terrain.md "Upřesnění T2"): building and bridge deck
 * fragments nearer the camera than the car, within FADE_RADIUS_M of the eye–car segment and not
 * below the car (the deck it drives on stays solid) keep a
 * 4 × 4 Bayer pattern of FADE_COVERAGE (alpha 0.3 without sorting). The test mirrors `occludes`
 * in chase.ts. Always compiled in; `state.on` = 0 (top-down) only skips it, no shader rebuild.
 */

/** Shared per frame by every material carrying the plugin; Babylon coordinates (y up), car = 1 m over its base. */
export interface FadeState {
  on: boolean;
  eye: [number, number, number];
  car: [number, number, number];
}

const GLSL_DEFS = `
uniform vec4 fadeEye;
uniform vec4 fadeCar;
float fadeB2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float fadeB4(vec2 a) { return fadeB2(0.5 * a) * 0.25 + fadeB2(a); }
`;
const GLSL_MAIN = `
if (fadeEye.w > 0.5) {
  vec3 fadeV = fadeCar.xyz - fadeEye.xyz;
  float fadeT = dot(vPositionW - fadeEye.xyz, fadeV) / max(dot(fadeV, fadeV), 1e-4);
  vec3 fadeQ = fadeEye.xyz + fadeV * fadeT - vPositionW;
  if (fadeT > 0.0 && fadeT < 1.0 && vPositionW.y > fadeCar.y - 1.0 && dot(fadeQ, fadeQ) <= fadeCar.w && fadeB4(gl_FragCoord.xy) >= ${FADE_COVERAGE.toFixed(3)}) discard;
}
`;
const WGSL_DEFS = `
uniform fadeEye: vec4f;
uniform fadeCar: vec4f;
fn fadeB2(a0: vec2f) -> f32 { let a = floor(a0); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
fn fadeB4(a: vec2f) -> f32 { return fadeB2(0.5 * a) * 0.25 + fadeB2(a); }
`;
const WGSL_MAIN = `
if (uniforms.fadeEye.w > 0.5) {
  let fadeV = uniforms.fadeCar.xyz - uniforms.fadeEye.xyz;
  let fadeT = dot(fragmentInputs.vPositionW - uniforms.fadeEye.xyz, fadeV) / max(dot(fadeV, fadeV), 1e-4);
  let fadeQ = uniforms.fadeEye.xyz + fadeV * fadeT - fragmentInputs.vPositionW;
  if (fadeT > 0.0 && fadeT < 1.0 && fragmentInputs.vPositionW.y > uniforms.fadeCar.y - 1.0 && dot(fadeQ, fadeQ) <= uniforms.fadeCar.w && fadeB4(fragmentInputs.position.xy) >= ${FADE_COVERAGE.toFixed(3)}) { discard; }
}
`;

export class OccluderFadePlugin extends MaterialPluginBase {
  constructor(material: Material, readonly state: FadeState) {
    super(material, 'OccluderFade', 200, undefined, true, false);
    // hardBindForSubMesh is an "extra" event: registered before the plugin is enabled.
    this.registerForExtraEvents = true;
    this._enable(true);
  }

  override getClassName(): string {
    return 'OccluderFadePlugin';
  }

  override isCompatible(): boolean {
    return true;
  }

  override getUniforms(): { externalUniforms: string[] } {
    return { externalUniforms: ['fadeEye', 'fadeCar'] };
  }

  override hardBindForSubMesh(_u: UniformBuffer, _s: Scene, _e: AbstractEngine, subMesh: SubMesh): void {
    const fx = subMesh.effect;
    if (!fx) return;
    const s = this.state;
    fx.setFloat4('fadeEye', s.eye[0], s.eye[1], s.eye[2], s.on ? 1 : 0);
    fx.setFloat4('fadeCar', s.car[0], s.car[1], s.car[2], FADE_RADIUS_M * FADE_RADIUS_M);
  }

  override getCustomCode(shaderType: string, shaderLanguage?: number): { [pointName: string]: string } | null {
    if (shaderType !== 'fragment') return null;
    return shaderLanguage === 1
      ? { CUSTOM_FRAGMENT_DEFINITIONS: WGSL_DEFS, CUSTOM_FRAGMENT_MAIN_BEGIN: WGSL_MAIN }
      : { CUSTOM_FRAGMENT_DEFINITIONS: GLSL_DEFS, CUSTOM_FRAGMENT_MAIN_BEGIN: GLSL_MAIN };
  }
}
