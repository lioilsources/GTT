import { Constants } from '@babylonjs/core/Engines/constants';
import { ShaderStore } from '@babylonjs/core/Engines/shaderStore';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';
import { Color4 } from '@babylonjs/core/Maths/math.color';
import { Vector2 } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import type { Scene } from '@babylonjs/core/scene';

import { tokens } from '../gen/tokens';
import type { TuningWeather } from '../gen/tuning';
import { rgba } from './palette';
import { DYNAMIC_LAYERS } from './risograph';

/**
 * Rain and fog of specs/weather.md as one full-screen pass: a clip-space quad in the last
 * rendering group, on the dynamic layers, so it lands over the world and the cars (and over the
 * risograph, which only post-processes the world layer) but under the overlay canvas and the DOM
 * HUD. Rain streaks are procedural (one streak per screen cell, hashed position, scrolling along
 * the fall direction), so no instance buffer and no per-frame allocation.
 */

/** Cell size (physical pixels) for `drops` streaks of length `lenPx` over a w × h screen. */
export function rainCells(w: number, h: number, drops: number, lenPx: number): { cw: number; ch: number } {
  const area = (Math.max(w, 1) * Math.max(h, 1)) / Math.max(drops, 1);
  const ch = Math.max(lenPx * 2.5, Math.sqrt(area * 3));
  return { cw: Math.max(area / ch, 2), ch };
}

export const WEATHER_VERTEX = /* glsl */ `
precision highp float;
attribute vec3 position;
void main(void) {
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`;

export const WEATHER_FRAGMENT = /* glsl */ `
precision highp float;
uniform vec2 resolution;
uniform float dpr;
uniform float rain;
uniform float fog;
uniform vec4 rainColor;
uniform vec4 fogColor;
uniform float fogCenter;
uniform float fogEdge;
uniform float fogInner;
uniform float rainLen;
uniform float rainScroll;
uniform float rainSin;
uniform float rainCos;
uniform float cellW;
uniform float cellH;

vec2 hash2(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yzx + 33.33);
  return fract((q.xx + q.yz) * q.zy);
}

void main(void) {
  vec2 p = gl_FragCoord.xy;
  float ra = 0.0;
  if (rain > 0.0) {
    // Fall direction (sin a, −cos a) becomes −y; the pattern scrolls up so the streaks fall.
    vec2 q = vec2(rainCos * p.x + rainSin * p.y, -rainSin * p.x + rainCos * p.y);
    q.y += rainScroll;
    vec2 cell = floor(q / vec2(cellW, cellH));
    vec2 h = hash2(cell);
    float cx = (cell.x + 0.2 + 0.6 * h.x) * cellW;
    float y0 = (cell.y + h.y * (1.0 - rainLen / cellH)) * cellH;
    float along = (q.y - y0) / rainLen;
    float halfW = 0.6 * dpr;
    float dx = abs(q.x - cx);
    float line = 1.0 - smoothstep(halfW, halfW + 1.0, dx);
    float inside = step(0.0, along) * step(along, 1.0);
    // Head at the bottom (leading edge), tail fading upwards.
    ra = rainColor.a * line * inside * (1.0 - 0.7 * along) * rain;
  }
  float fa = 0.0;
  if (fog > 0.0) {
    float d = length(p - 0.5 * resolution) / (0.5 * length(resolution));
    fa = mix(fogCenter, fogEdge, smoothstep(fogInner, 1.0, d)) * fogColor.a * fog;
  }
  float a = ra + fa * (1.0 - ra);
  if (a <= 0.0) discard;
  vec3 c = (rainColor.rgb * ra + fogColor.rgb * fa * (1.0 - ra)) / a;
  gl_FragColor = vec4(c, a);
}
`;

ShaderStore.ShadersStore['weatherVertexShader'] = WEATHER_VERTEX;
ShaderStore.ShadersStore['weatherFragmentShader'] = WEATHER_FRAGMENT;

const FLOATS = [
  'dpr', 'rain', 'fog', 'fogCenter', 'fogEdge', 'fogInner', 'rainLen', 'rainScroll', 'rainSin', 'rainCos', 'cellW', 'cellH',
] as const;

export class WeatherView {
  private readonly mesh: Mesh;
  private readonly mat: ShaderMaterial;
  private readonly res = new Vector2(1, 1);
  private scroll = 0;
  /** Cell size for the last render size (recomputed only when the size changes). */
  private cells = { w: 0, h: 0, dpr: 0, cw: 1, ch: 1 };

  constructor(scene: Scene, readonly t: TuningWeather) {
    const mat = (this.mat = new ShaderMaterial('weather', scene, 'weather', {
      attributes: ['position'],
      uniforms: ['resolution', 'rainColor', 'fogColor', ...FLOATS],
      needAlphaBlending: true,
    }));
    mat.backFaceCulling = false;
    mat.disableDepthWrite = true;
    mat.depthFunction = Constants.ALWAYS;
    mat.alphaMode = Constants.ALPHA_COMBINE;
    const rc = rgba(tokens.colorWeatherRain), fc = rgba(tokens.colorWeatherFog);
    mat.setColor4('rainColor', new Color4(rc[0], rc[1], rc[2], rc[3]));
    mat.setColor4('fogColor', new Color4(fc[0], fc[1], fc[2], fc[3]));
    mat.setVector2('resolution', this.res);
    const a = (t.rainAngleDeg * Math.PI) / 180;
    mat.setFloat('rainSin', Math.sin(a));
    mat.setFloat('rainCos', Math.cos(a));
    mat.setFloat('fogCenter', t.fogCenterAlpha);
    mat.setFloat('fogEdge', t.fogEdgeAlpha);
    mat.setFloat('fogInner', t.fogInner);
    for (const k of FLOATS) if (!['rainSin', 'rainCos', 'fogCenter', 'fogEdge', 'fogInner'].includes(k)) mat.setFloat(k, 0);

    const m = (this.mesh = new Mesh('weather', scene));
    const vd = new VertexData();
    vd.positions = new Float32Array([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]);
    vd.indices = new Uint16Array([0, 1, 2, 0, 2, 3]);
    vd.applyToMesh(m, false);
    m.material = mat;
    m.isPickable = false;
    m.alwaysSelectAsActiveMesh = true;
    m.doNotSyncBoundingInfo = true;
    m.freezeWorldMatrix();
    // Last group: after the world, cars, peds, trams and patrols. Dynamic layers: the top camera
    // draws it when the risograph is on (the main camera then sees only the world layer).
    m.renderingGroupId = 3;
    m.layerMask = DYNAMIC_LAYERS;
    m.setEnabled(false);
  }

  /**
   * Per frame: weights 0..1 of rain and fog, frame dt (s), render size in physical pixels and the
   * device pixel ratio. Clear (both 0) disables the quad, so clear weather costs no draw call.
   */
  update(rain: number, fog: number, dt: number, w: number, h: number, dpr: number): void {
    const on = rain > 0 || fog > 0;
    if (this.mesh.isEnabled() !== on) this.mesh.setEnabled(on);
    if (!on) return;
    const t = this.t, mat = this.mat;
    const len = t.rainLenPx * dpr;
    const c = this.cells;
    if (c.w !== w || c.h !== h || c.dpr !== dpr) {
      const r = rainCells(w, h, t.rainDrops, len);
      Object.assign(c, { w, h, dpr, cw: r.cw, ch: r.ch });
    }
    const cw = c.cw, ch = c.ch;
    // Wrapped scroll keeps float precision; every 1024 rows the streaks reshuffle once.
    this.scroll = (this.scroll + Math.max(0, dt) * t.rainSpeedPxS * dpr) % (ch * 1024);
    this.res.set(w, h);
    mat.setFloat('dpr', dpr);
    mat.setFloat('rain', rain);
    mat.setFloat('fog', fog);
    mat.setFloat('rainLen', len);
    mat.setFloat('rainScroll', this.scroll);
    mat.setFloat('cellW', cw);
    mat.setFloat('cellH', ch);
  }

  dispose(): void {
    this.mesh.dispose();
    this.mat.dispose();
  }
}
