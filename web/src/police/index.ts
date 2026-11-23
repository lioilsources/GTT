import type { Scene } from '@babylonjs/core/scene';

import type { MessageKey } from '../gen/i18n';
import type { Tuning } from '../gen/tuning';
import type { DriveWorld } from '../drive/driveWorld';
import type { ChunkData } from '../world/chunk';
import type { Rgba } from '../render/palette';
import { PoliceHud } from './hud';
import { Police, type StolenSource } from './police';
import { PoliceView } from './view';
import type { CarSpriteView } from '../render/carSprites';

export { Police } from './police';

/** The police feature as main.ts sees it (specs/police.md). */
export interface PoliceFeature {
  readonly police: Police;
  addChunk(c: ChunkData): void;
  removeChunk(c: ChunkData): void;
  /** Per frame: `stepDt` = driving dt (0 while the world is paused), `dt` = real frame dt. */
  update(stepDt: number, dt: number): void;
  /** Patrol ground shadow colour (specs/style.md). */
  setShadow(c: Rgba): void;
  /** Car sprites shared with the world (specs/art.md v2). */
  setSprites(sp: CarSpriteView): void;
}

export function installPolice(o: {
  drive: DriveWorld;
  cars: StolenSource | null;
  tuning: Tuning;
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
  hud: HTMLElement;
  scene: Scene;
}): PoliceFeature {
  const police = new Police(o.drive, o.tuning, o.cars);
  const on = o.tuning.police.enabled && o.drive.traffic !== null;
  const view = on ? new PoliceView(o.scene, o.drive.traffic!, o.tuning) : null;
  const hud = on ? new PoliceHud(police, o.t, o.hud) : null;
  return {
    police,
    addChunk: (c) => police.addChunk(c),
    removeChunk: (c) => police.removeChunk(c),
    update(stepDt, dt) {
      police.update(stepDt);
      view?.update(stepDt, o.drive.car.layer);
      hud?.update(dt);
    },
    setShadow: (c) => view?.setShadow(c),
    setSprites: (sp) => view?.setSprites(sp),
  };
}
