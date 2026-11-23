// Package dem reads elevation for the citypack `elevation` step (Prompts/02-METROPOLE_TERRAIN_PLAN.md 3.1).
//
// The AWS Terrain Tiles code (fetch.go, tiles.go, mosaic.go, Hillshade in shade.go and their
// tests) is ported from Ol1n's terrain-fetch tool (MountainsSimulator/terrain-fetch, MIT licence,
// © Ol1n). Only the package name and exported identifiers changed; the Roblox, Lua, strip and
// colour-map parts were left out.
//
// Data: AWS Terrain Tiles (Mapzen terrarium encoding, s3://elevation-tiles-prod) are open data;
// attribution follows the tile sources (tilezen/joerd docs/attribution.md): USGS 3DEP (public
// domain) in the United States, SRTM, GMTED2010, ETOPO1, EU-DEM elsewhere.
package dem

// Attribution is the credit line for packs that use AWS Terrain Tiles.
const Attribution = "Elevation: AWS Terrain Tiles (Mapzen) – USGS 3DEP, SRTM (NASA/USGS), GMTED2010, ETOPO1 (NOAA), EU-DEM (produced using Copernicus data and information funded by the European Union)"
