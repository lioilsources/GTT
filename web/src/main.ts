import { Engine } from '@babylonjs/core/Engines/engine';
import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { WebGPUEngine } from '@babylonjs/core/Engines/webgpuEngine';
import { FreeCamera } from '@babylonjs/core/Cameras/freeCamera';
import { HemisphericLight } from '@babylonjs/core/Lights/hemisphericLight';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Color3, Color4 } from '@babylonjs/core/Maths/math.color';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import { CreateGround } from '@babylonjs/core/Meshes/Builders/groundBuilder';
import { Scene } from '@babylonjs/core/scene';

import { ASSET_BASE_URL } from './config';
import { t, type Locale } from './gen/i18n';
import { tokens } from './gen/tokens';
import { Tuning } from './gen/tuning';
import { cameraHeight, fovX } from './world/camera';

const canvas = document.getElementById('world') as HTMLCanvasElement;
const locale: Locale = navigator.language.startsWith('cs') ? 'cs' : 'en';
document.getElementById('title')!.textContent = t(locale, 'appTitle');

/** WebGL2 by default; WebGPU only on request (?gpu=webgpu), never required (DUALSTACK 2). */
async function createEngine(): Promise<AbstractEngine> {
  if (new URLSearchParams(location.search).get('gpu') === 'webgpu' && (await WebGPUEngine.IsSupportedAsync)) {
    const e = new WebGPUEngine(canvas, { antialias: true });
    await e.initAsync();
    return e;
  }
  return new Engine(canvas, true, { preserveDrawingBuffer: false, stencil: false }, true);
}

async function main(): Promise<void> {
  const tuning = Tuning.fromJson(await (await fetch(`${ASSET_BASE_URL}content/tuning.json`)).json());
  const engine = await createEngine();
  const scene = new Scene(engine);
  scene.clearColor = Color4.FromHexString(tokens.colorWorldDayLand + 'FF');

  // Top-down camera at H = 1/k: the same image as the Flutter extrusion (DUALSTACK 6.2).
  const h = cameraHeight(tuning);
  const camera = new FreeCamera('camera', new Vector3(0, h, 0), scene);
  camera.upVector = new Vector3(0, 0, 1);
  camera.setTarget(Vector3.Zero());
  camera.fovMode = FreeCamera.FOVMODE_HORIZONTAL_FIXED;
  camera.fov = fovX(tuning.viewWidthM.slow, h);
  camera.minZ = 1;
  camera.maxZ = h * 4;

  new HemisphericLight('sun', new Vector3(tuning.extrusion.k, 1, 0), scene);
  const ground = CreateGround('ground', { width: 256, height: 256 }, scene);
  const mat = new StandardMaterial('asphalt', scene);
  mat.diffuseColor = Color3.FromHexString(tokens.colorWorldDayAsphalt);
  // Flat ground under a light straight above: specular would wash the whole view out white.
  mat.specularColor = Color3.Black();
  ground.material = mat;

  document.getElementById('status')!.textContent = `${engine.isWebGPU ? 'WebGPU' : 'WebGL2'} · H ${h.toFixed(0)} m`;
  engine.runRenderLoop(() => scene.render());
  if (import.meta.env.DEV || new URLSearchParams(location.search).has('debug')) {
    (window as unknown as Record<string, unknown>)['metro'] = { engine, scene, camera };
  }
  window.addEventListener('resize', () => engine.resize());
}

main().catch((e: unknown) => {
  document.getElementById('status')!.textContent = String(e);
  throw e;
});
