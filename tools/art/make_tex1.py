#!/usr/bin/env python3
"""GTT textury povrchů (shora, neutrální světlo), 1024² -> po zpracování tileable 512²."""
import json
A = "flat vector illustration, two or three flat tones, thin dark outlines, clean geometric shapes, no gradients"
C = "retro screenprint risograph style, limited palette of four inks, flat ink areas, simple shapes"
NEG = ("text, letters, logo, watermark, perspective, horizon, sky, vignette, directional shadows, cast shadows, "
       "objects, cars, people, border, frame, blurry, photo, photorealistic")
BASE = ("seamless tileable texture, orthographic top-down view looking straight down, flat even neutral lighting, "
        "no shadows, uniform pattern filling the whole square edge to edge")
T = {
 "nyc/asphalt": f"warm grey asphalt road surface with subtle aggregate speckles and a few fine cracks. Style: {A}, colors #A49E9A, #98969B, #887F82",
 "nyc/sidewalk_concrete": f"concrete sidewalk slabs in a regular grid of square panels with thin joints. Style: {A}, colors #DEC3B4, #DAC2B0, #F3E3CE",
 "nyc/roof_tar": f"flat tar roof with gravel and seams of roofing membrane strips. Style: {A}, colors #887F82, #43384A, #98969B",
 "prague/cobblestone": f"old European granite cobblestone pavement, small rounded square setts in arcs (segmental pattern). Style: {C}, colors #DBD1A9, #C1C4A2, #3E1A13",
 "prague/mosaic_sidewalk": f"Prague mosaic sidewalk of small limestone and basalt cubes forming a simple repeating geometric pattern. Style: {C}, colors #DDE4CD, #FBEED7, #3E1A13, #206756",
 "prague/roof_tiles": f"terracotta clay roof tiles (beaver tail tiles) in overlapping rows seen from above. Style: {C}, colors #DE632D, #BA4D2A, #C85930",
}
for k, v in T.items():
    for s in (401, 402, 403):
        print(json.dumps({"name": f"cities/{k}_s{s}", "w": 1024, "h": 1024, "seed": s, "model": "qwen",
                          "prompt": f"{v}. {BASE}.", "neg": NEG}))
