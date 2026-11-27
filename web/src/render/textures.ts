import { DynamicTexture } from '@babylonjs/core/Materials/Textures/dynamicTexture';
import { Texture } from '@babylonjs/core/Materials/Textures/texture';
import type { Scene } from '@babylonjs/core/scene';

import { tokens } from '../gen/tokens';
import { Prng } from '../rules/prng';
import { TEX_SIZE } from './geometry';

function lerpHex(a: string, b: string, t: number): string {
  const pa = parseInt(a.slice(1, 7), 16), pb = parseInt(b.slice(1, 7), 16);
  const ch = (s: number): number => Math.round(((pa >> s) & 255) * (1 - t) + ((pb >> s) & 255) * t);
  return `rgb(${ch(16)},${ch(8)},${ch(0)})`;
}

/**
 * Procedural facade texture: a 4×4 grid of 64 px window cells, tiled over every wall (port of
 * world_engine textures.dart). White wall pixels keep the vertex colour, windows darken it;
 * at night some windows glow. Window pattern is presentation (P2).
 */
export function facadeTexture(scene: Scene, night: boolean): Texture {
  const tex = new DynamicTexture(night ? 'facade-night' : 'facade-day', TEX_SIZE, scene, true, Texture.TRILINEAR_SAMPLINGMODE);
  const c = tex.getContext() as CanvasRenderingContext2D;
  const rnd = new Prng(night ? 7 : 3);
  const unit = (): number => rnd.nextU32() / 4294967296;
  const cell = TEX_SIZE / 4;
  c.fillStyle = night ? tokens.colorFacadeNightWall : tokens.colorFacadeDayWall;
  c.fillRect(0, 0, TEX_SIZE, TEX_SIZE);
  for (let i = 0; i < 4; i++) {
    for (let j = 0; j < 4; j++) {
      const x = i * cell + 12, y = j * cell + 14, w = cell - 24, h = cell - 26;
      if (night) {
        c.fillStyle = unit() < 0.45
          ? lerpHex(tokens.colorFacadeNightLitA, tokens.colorFacadeNightLitB, unit() * 0.4)
          : tokens.colorFacadeNightDark;
      } else {
        c.fillStyle = lerpHex(tokens.colorFacadeDayGlassA, tokens.colorFacadeDayGlassB, unit());
      }
      c.fillRect(x, y, w, h);
      if (!night) {
        c.fillStyle = tokens.colorFacadeDayMullion; // mullion
        c.fillRect(x + w / 2 - 1.5, y, 3, h);
      }
    }
  }
  tex.update(false);
  tex.wrapU = Texture.WRAP_ADDRESSMODE;
  tex.wrapV = Texture.WRAP_ADDRESSMODE;
  return tex;
}

/**
 * Stone wall of a landmark model (specs/models.md v2 "Fasáda"): one bay, models.facade_bay_m
 * across and models.facade_storey_m up. A buttress on the left edge, a pointed (lancet) window
 * with a mullion and a small rose in the middle, a string course at the bottom. Multiplies the
 * vertex colour (white keeps it). Canvas top = top of the bay. Presentation only (P2).
 */
export function modelStoneTexture(scene: Scene, night: boolean): Texture {
  const W = 128, H = 256;
  const tex = new DynamicTexture(night ? 'model-stone-night' : 'model-stone-day', { width: W, height: H }, scene, true, Texture.TRILINEAR_SAMPLINGMODE);
  const c = tex.getContext() as CanvasRenderingContext2D;
  const k = night
    ? { base: tokens.colorModelFacadeNightBase, window: tokens.colorModelFacadeNightLit, tracery: tokens.colorModelFacadeNightWindow, buttress: tokens.colorModelFacadeNightButtress, course: tokens.colorModelFacadeNightCourse }
    : { base: tokens.colorModelFacadeDayBase, window: tokens.colorModelFacadeDayWindow, tracery: tokens.colorModelFacadeDayTracery, buttress: tokens.colorModelFacadeDayButtress, course: tokens.colorModelFacadeDayCourse };
  c.fillStyle = k.base;
  c.fillRect(0, 0, W, H);
  // Buttress with a set-off half way up (wider below).
  c.fillStyle = k.buttress;
  c.fillRect(0, 0, 14, H);
  c.fillRect(0, 120, 20, H - 120);
  // Lancet window: straight jambs, a pointed arch of two arcs.
  const cx = 72, hw = 18, top = 34, spring = 72, bottom = 214;
  c.fillStyle = k.window;
  c.beginPath();
  c.moveTo(cx - hw, bottom);
  c.lineTo(cx - hw, spring);
  c.quadraticCurveTo(cx - hw, top + 10, cx, top);
  c.quadraticCurveTo(cx + hw, top + 10, cx + hw, spring);
  c.lineTo(cx + hw, bottom);
  c.closePath();
  c.fill();
  // Tracery: a mullion, a transom and a small rose in the arch.
  c.fillStyle = k.tracery;
  c.fillRect(cx - 2, spring, 4, bottom - spring);
  c.fillRect(cx - hw, 142, 2 * hw, 3);
  c.beginPath();
  c.arc(cx, spring - 6, 7, 0, 2 * Math.PI);
  c.lineWidth = 3;
  c.strokeStyle = k.tracery;
  c.stroke();
  // Sill and string course.
  c.fillStyle = k.course;
  c.fillRect(cx - hw - 4, bottom, 2 * hw + 8, 5);
  c.fillRect(0, H - 14, W, 8);
  tex.update(false);
  tex.wrapU = Texture.WRAP_ADDRESSMODE;
  tex.wrapV = Texture.WRAP_ADDRESSMODE;
  return tex;
}

/**
 * Roof of a landmark model (specs/models.md v2 "Fasáda"): four seams across, stripes down the
 * slope (standing seams of copper and lead, rows of slate), one tile = 4 × models.roof_seam_m.
 */
export function modelRoofTexture(scene: Scene, night: boolean): Texture {
  const W = 256, H = 4;
  const tex = new DynamicTexture(night ? 'model-roof-night' : 'model-roof-day', { width: W, height: H }, scene, true, Texture.TRILINEAR_SAMPLINGMODE);
  const c = tex.getContext() as CanvasRenderingContext2D;
  c.fillStyle = night ? tokens.colorModelFacadeNightBase : tokens.colorModelFacadeDayBase;
  c.fillRect(0, 0, W, H);
  c.fillStyle = night ? tokens.colorModelFacadeNightSeam : tokens.colorModelFacadeDaySeam;
  for (let i = 0; i < 4; i++) c.fillRect(i * 64, 0, 10, H);
  tex.update(false);
  tex.wrapU = Texture.WRAP_ADDRESSMODE;
  tex.wrapV = Texture.WRAP_ADDRESSMODE;
  return tex;
}
