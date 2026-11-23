import { fromBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';

import {
  ChunkSchema,
  GraphSchema,
  LandmarksSchema,
  LodSchema,
  ManifestSchema,
  SpotsSchema,
  TramGraphSchema,
  type Chunk,
  type Graph,
  type Landmarks,
  type Lod,
  type Manifest,
  type Spots,
  type TramGraph,
} from '../gen/pb/citypack_pb';

/** Where citypack files come from (specs/citypack.md): fetch on the web, the file system in tests. */
export interface PackSource {
  read(path: string): Promise<Uint8Array>;
}

/** Every citypack file is gzip-compressed protobuf. */
export async function gunzip(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes as BlobPart]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function decode<D extends DescMessage>(schema: D, gz: Uint8Array): Promise<MessageShape<D>> {
  return fromBinary(schema, await gunzip(gz));
}

export const decodeManifest = (gz: Uint8Array): Promise<Manifest> => decode(ManifestSchema, gz);
export const decodeGraph = (gz: Uint8Array): Promise<Graph> => decode(GraphSchema, gz);
export const decodeLandmarks = (gz: Uint8Array): Promise<Landmarks> => decode(LandmarksSchema, gz);
export const decodeSpots = (gz: Uint8Array): Promise<Spots> => decode(SpotsSchema, gz);
export const decodeTrams = (gz: Uint8Array): Promise<TramGraph> => decode(TramGraphSchema, gz);
export const decodeChunk = (gz: Uint8Array): Promise<Chunk> => decode(ChunkSchema, gz);
/** lod/{x}_{y}.pb (citypack v4): the far ring; the phone map takes its water and green masses. */
export const decodeLod = (gz: Uint8Array): Promise<Lod> => decode(LodSchema, gz);

export const chunkPath = (x: number, y: number): string => `chunks/${x}_${y}.pb`;

/** Reads a pack over HTTP from `<base>packs/<city>/<version>/` (metro sync layout, DUALSTACK 6.7). */
export class HttpPackSource implements PackSource {
  private constructor(readonly root: string) {}

  static async open(base: string, city: string): Promise<HttpPackSource> {
    const res = await fetch(`${base}packs/${city}/current.json`, { cache: 'no-cache' });
    if (!res.ok) throw new Error(`packs/${city}/current.json: HTTP ${res.status}`);
    const { version } = (await res.json()) as { version: string };
    return new HttpPackSource(`${base}packs/${city}/${version}/`);
  }

  async read(path: string): Promise<Uint8Array> {
    const res = await fetch(this.root + path);
    if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
    return new Uint8Array(await res.arrayBuffer());
  }
}
