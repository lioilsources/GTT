import { VertexBuffer } from '@babylonjs/core/Buffers/buffer';
import type { Mesh } from '@babylonjs/core/Meshes/mesh';

import type { Rgba } from './palette';

/**
 * Recolours the first [vertices] vertices of [mesh] (the ground-shadow rect each vehicle mesh
 * starts with) to [c]: the city skin's shadow by day, `color.car.shadow` otherwise (specs/style.md).
 * Runs on a day/night switch only.
 */
export function setShadowColour(mesh: Mesh, vertices: number, c: Rgba): void {
  const col = mesh.getVerticesData(VertexBuffer.ColorKind);
  if (!col) return;
  const out = Float32Array.from(col);
  for (let i = 0; i < vertices && 4 * i + 3 < out.length; i++) out.set(c, 4 * i);
  mesh.setVerticesData(VertexBuffer.ColorKind, out, false, 4);
}

/**
 * Sets a thin-instance count and hides the mesh while it is 0. With no instances Babylon draws
 * the mesh as a plain mesh, and a material shared with a mesh that does have instance colours
 * can then compile without INSTANCES but with INSTANCESCOLOR ('instanceColor' undeclared).
 */
export function setCount(mesh: Mesh, n: number): void {
  mesh.thinInstanceCount = n;
  mesh.isVisible = n > 0;
}
