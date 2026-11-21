/** Base URL for packs and shared assets; move heavy files elsewhere without code changes (DUALSTACK 6.7). */
export const ASSET_BASE_URL: string = import.meta.env.VITE_ASSET_BASE_URL ?? './shared/';
