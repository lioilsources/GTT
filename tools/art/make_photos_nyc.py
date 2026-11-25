#!/usr/bin/env python3
"""GTT fotomísta New York (docs/art-requests.md kap. 5): 20 pohledových ilustrací 1080×1350 (výhledy, ne
památky), styl A (plochý vektor), paleta NYC. Id a jméno = spoty `kind: photo` v content/cities/nyc/spots.yaml.
Bez textu, nápisů, log a značek (R10); cedule, reklamy a lampiony prázdné nebo mimo záběr.
Vypíše JSONL pro run_board.py (3 seedy na místo).
  python3 make_photos_nyc.py"""
import json

A = ("flat vector illustration, cel shading with two or three flat tones per surface, thin dark outline, "
     "clean geometric shapes, no gradients, crisp edges, full bleed, no border")
PAL = "color palette of warm grey asphalt, warm yellow, red brick, cool steel blue, soft sky"
NOTXT = ("no text anywhere, no letters, no words, no signs, no billboards, no logos, no brand names, no cars, "
         "no taxis, no vehicles with markings, only pedestrians, trees and architecture")
NEG = ("text, letters, words, caption, writing, signage text, chinese characters, logo, brand name, watermark, "
       "signature, license plate, graffiti tag, photo, photorealistic, blurry, low quality, deformed, child, nsfw, "
       "border, frame, mockup, postcard border, billboard, signboard, sign, taxi, car, vehicle, boat lettering, "
       "license plate, emblem")
P = {
 "photo_dumbo_washington": "the view down a cobblestone street between red brick warehouses in Brooklyn framing a huge "
                           "dark blue steel suspension bridge tower with the Manhattan skyline behind it",
 "photo_queens_plaza": "a massive grey steel cantilever bridge crossing over a wide avenue with elevated train tracks, "
                       "seen from a plaza in Queens",
 "photo_tudor_city": "the view from a stone overpass straight down a long wide crosstown street lined with tall "
                     "buildings toward the river, golden evening light",
 "photo_high_line_17": "an avenue passing under an old elevated steel railway converted into a park with plants on top, "
                       "seen from the street with pedestrians",
 "photo_pier_45": "a wide river at sunset seen from a long pier with benches and grass, orange sky, distant shore "
                  "with low buildings",
 "photo_battery_harbor": "a wide harbor with ferries and a small island with a green copper statue in the far distance, "
                         "seen from a waterfront promenade with trees",
 "photo_seaport_bridge": "a huge stone suspension bridge with gothic arches and fan of cables seen from a riverside "
                         "street with old masted ships in the foreground",
 "photo_williamsburg_kent": "a long steel suspension bridge with lattice towers across a river seen from a waterfront "
                            "park in Brooklyn, Manhattan towers behind",
 "photo_park_ave_viaduct": "an elevated road viaduct wrapping around a monumental grand train terminal building with "
                           "tall skyscrapers above",
 "photo_fifth_ave_arch": "a straight elegant avenue lined with brownstone townhouses leading down to a white marble "
                         "triumphal arch in a park at the end",
 "photo_cpw_lake": "a calm lake in a big city park with a rowboat, trees in autumn colors and a row of grand "
                   "twin-towered apartment buildings rising behind the trees",
 "photo_columbus_circle": "a busy round traffic circle with a tall column and statue in the middle, fountains, glass towers around",
 "photo_sutton_place": "a grey steel cantilever bridge over a river seen from a small quiet riverside park with benches "
                       "and trees",
 "photo_mott_street": "a narrow crowded old street with fire escapes, colorful round paper lanterns hanging overhead "
                      "that are completely plain without any characters, small shops with blank awnings",
 "photo_mulberry_lights": "a narrow old street at night with strings of festive light arches over the street, red, "
                          "white and green bulbs, outdoor restaurant tables, blank awnings",
 "photo_madison_square": "a small leafy city park seen from an avenue, with a thin wedge-shaped corner skyscraper on one "
                         "side and a tall tower with a golden pyramid top behind the trees",
 "photo_bowery_wall": "a large brick wall on a street corner covered with a colorful abstract mural of geometric "
                      "shapes and bold color fields without any letters, pedestrians walking past",
 "photo_riverside_drive": "a wide river with high wooded cliffs on the far shore seen from a hilly riverside park "
                          "with old lamp posts and a curving promenade",
 "photo_harlem_meer": "a pond at the edge of a big city park with willows, ducks and a small boathouse, apartment "
                      "buildings beyond the trees",
 "photo_east_river_23": "a wide river with a ferry and the skyline of the opposite bank seen from a small riverside "
                        "cove park with grasses and a bike path",
}
for k, v in P.items():
    for s in (611, 612, 613):  # v2: bez aut a billboardů (v1 s601–603 měla falešné nápisy na taxících)
        print(json.dumps({"name": f"photos/nyc/{k}_s{s}", "w": 1088, "h": 1360, "seed": s, "model": "qwen",
                          "prompt": f"illustrated view of {v}, New York City, vertical composition, scenic viewpoint "
                                    f"illustration. Style: {A}, {PAL}. {NOTXT}.",
                          "neg": NEG}))
