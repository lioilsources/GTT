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
