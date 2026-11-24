#!/usr/bin/env python3
"""GTT Moskva (styl E, konstruktivistický plakát): style check, 25 pohlednic, AI textury. Vypíše JSONL pro run_board.py.
Původní tvorba v duchu doby, ne kopie konkrétních plakátů; bez textu, hesel, azbuky, symbolů režimů a značek (R10).
Hvězdy na věžích Kremlu jsou architektura (jen u věží).
  python3 make_moscow1.py style|postcards|tex"""
import json, sys

E = ("Russian constructivist poster art style, flat hard-edged color fills, bold diagonal composition, geometric "
     "shapes, strong silhouettes, screen-printed paper texture, no gradients, no airbrush, original artwork")
E_TOP = ("flat hard-edged color fills, geometric constructivist graphic style, crisp shapes, no gradients, "
         "no outlines, clean game art")
PAL = ("strictly limited palette of signal red, deep black, warm cream paper, with small accents of ochre gold and "
       "warm grey; water is blue and trees are green")
NOSIGN = ("absolutely no text anywhere, no letters, no slogans, no banners, no signs, no billboards, no flags, no "
          "posters on walls, no emblems, plain blank walls")
NEG = ("text, letters, words, cyrillic, latin letters, typography, slogan, caption, headline, title, glyphs, writing, "
       "inscription, banner with writing, signboard, billboard, logo, brand name, watermark, signature, license "
       "plate, hammer and sickle, emblem, coat of arms, flag, political symbol, portrait of a leader, propaganda "
       "figure, soldier, weapon, gradient, airbrush, photo, photorealistic, 3d render, blurry, low quality, deformed, "
       "child, nsfw, border, frame, mockup, pennant, flags on roofs, red flag, flagpole, printed caption, small print in the margin, artist signature")
NEG_NOSTAR = NEG + ", star, red star"
out = []


def job(name, w, h, seed, prompt, neg=NEG):
    out.append({"name": name, "w": w, "h": h, "seed": seed, "model": "qwen", "prompt": prompt, "neg": neg})


STARS = {"spasskaya_tower", "borovitskaya_tower", "red_square"}  # rubínové hvězdy jsou součást věží
P = {
 "spasskaya_tower": "the Spasskaya Tower of the Kremlin with its clock face that has only plain marks and no numerals, "
                    "red brick walls, tented green spire topped by a ruby star",
 "borovitskaya_tower": "the stepped Borovitskaya Tower of the Kremlin rising above the red brick wall and green trees, "
                       "topped by a ruby star",
 "red_square": "the vast cobbled Red Square with the red brick Kremlin wall and towers on one side and colorful onion "
               "domes in the distance, a few small adult figures walking",
 "st_basils": "Saint Basil's Cathedral with its cluster of colorful striped and patterned onion domes",
 "upper_trading_rows": "the long ornate pale stone facade of the Upper Trading Rows arcade with glass roofs, no shop "
                       "names, plain facade",
 "historical_museum": "the red brick State Historical Museum with its many pointed white-trimmed towers",
 "bolshoi": "the Bolshoi Theatre neoclassical facade with eight tall columns and a quadriga of horses on the portico, "
            "fountain in front",
 "christ_saviour": "the white Cathedral of Christ the Saviour with five golden domes beside the river",
 "pushkin_museum": "the neoclassical Pushkin Museum of Fine Arts with its white colonnade portico and stairs",
 "tretyakov": "the fairy-tale facade of the Tretyakov Gallery with its decorative arched gable, red and white",
 "old_arbat": "the pedestrian Old Arbat street with low pastel historic houses, old street lamps and a few adult "
              "strollers, plain shopfronts",
 "patriarch_ponds": "Patriarch's Ponds, a rectangular pond with trees, benches and a small pavilion, elegant apartment "
                    "buildings around",
 "gorky_park": "Gorky Park with the grand colonnaded entrance arch, wide alleys, trees and a fountain",
 "zaryadye": "Zaryadye Park with the floating V-shaped concrete bridge cantilevered over the Moskva river, the Kremlin "
             "in the background",
 "kotelnicheskaya": "the Kotelnicheskaya Embankment Building, a monumental stepped skyscraper with a central spire, on "
                    "the river embankment",
 "foreign_ministry": "the Ministry of Foreign Affairs Building, a stepped monumental skyscraper with a tall central "
                     "spire, symmetric",
 "kudrinskaya": "the Kudrinskaya Square Building, a stepped monumental residential skyscraper with a central tower and "
                "spire",
 "red_gates": "the Red Gates Building, a stepped monumental skyscraper with a central spire towering over a square",
 "lubyanka_square": "Lubyanka Square, a round open square with traffic around it and a large ochre neoclassical "
                    "building behind",
 "manege": "the long low neoclassical Manege exhibition hall with a row of white columns and a pale yellow facade",
 "state_library": "the Russian State Library with its row of tall dark square columns and a seated bronze figure of an "
                  "old writer in front on the stairs",
 "house_on_embankment": "the massive grey constructivist House on the Embankment apartment block by the river",
 "bolshoy_kamenny": "the Bolshoy Kamenny Bridge, a long flat steel arch bridge over the Moskva river with the Kremlin "
                    "towers and golden domes behind",
 "pushkin_square": "Pushkin Square with a bronze statue of a young clean-shaven poet with curly hair and long "
                   "sideburns, no beard, in a long cloak with his head slightly bowed, on a tall pedestal, fountains "
                   "and trees, plain building facades behind",
 "komsomolskaya": "Komsomolskaya Square with three historic railway station buildings: one with a tall tented clock "
                  "tower that has plain marks only, one with a pointed spire, and one with a fairy-tale tower",
}
mode = sys.argv[1]
if mode == "style":
    for s in (11, 12):
        job(f"styleboard/moscow/intersection_s{s}", 1088, 1920, s,
            "orthographic top-down view looking straight down at a wide Moscow boulevard intersection, dark warm grey "
            "asphalt, ochre yellow centre lines, cream sidewalks, small cars seen from directly above driving on the "
            "right, tiny adult pedestrians from above, flat building rooftops in cream and warm grey with black edges, "
            "red and cream facades, a few green trees, light from the top-left, short hard shadows toward "
            f"bottom-right. Style: {E_TOP}, {PAL}. {NOSIGN}.", NEG_NOSTAR)
    for s in (11, 12):
        job(f"styleboard/moscow/postcard_s{s}", 1088, 1360, s,
            f"illustrated travel postcard of {P['st_basils']} in Moscow, vertical composition, full bleed "
            f"illustration, the landmark is the main subject, tilted dynamic diagonal angle with large red and black "
            f"geometric wedges and circles in the sky. Style: {E}, {PAL}. {NOSIGN}.", NEG_NOSTAR)
    for s in (11, 12):  # varianta bez lidí: čistá architektura, méně grafiky
        job(f"styleboard/moscow/postcard_plain_s{s}", 1088, 1360, s,
            f"illustrated travel postcard of {P['kotelnicheskaya']} in Moscow, vertical composition, full bleed "
            f"illustration, low angle view looking up, no people, calm cream sky with a single large red circle sun. "
            f"Style: {E}, {PAL}. {NOSIGN}.", NEG_NOSTAR)
elif mode == "postcards":
    for k, v in P.items():
        for s in (301, 302, 303):
            job(f"postcards/moscow/{k}_s{s}", 1088, 1360, s,
                f"illustrated travel postcard of {v} in Moscow, vertical composition, full bleed illustration, the "
                f"landmark is the main subject, dynamic diagonal composition. Style: {E}, {PAL}. {NOSIGN}.",
                NEG if k in STARS else NEG_NOSTAR)
elif mode == "fix1":  # oprava 1: Puškin bez plnovousu (v1 vypadal jako jiná historická postava)
    for s in (311, 312, 313):
        job(f"postcards/moscow/pushkin_square_s{s}", 1088, 1360, s,
            f"illustrated travel postcard of {P['pushkin_square']} in Moscow, vertical composition, full bleed "
            f"illustration, the landmark is the main subject, dynamic diagonal composition. Style: {E}, {PAL}. {NOSIGN}.",
            NEG_NOSTAR + ", beard, bearded man")
elif mode == "tex":
    TEX = ("a square close-up swatch of the material only, flat surface filling the entire image edge to edge, camera "
           f"pointing straight down, even neutral light, no shadows, no objects, no borders, no perspective. Style: {E_TOP}")
    T = {"asphalt": "plain dark warm grey asphalt with fine lighter speckles of aggregate, no markings",
         "sidewalk": "large rectangular cream and warm grey granite paving slabs in a running bond with thin dark joints",
         "roof": "flat roof of pale cream bitumen sheets with overlapping seams and a few small square vents"}
    for k, v in T.items():
        for s in (431, 432, 433):
            job(f"cities/moscow/{k}_s{s}", 1024, 1024, s, f"{v}. {TEX}.",
                NEG_NOSTAR + ", perspective, horizon, road, curb, building, car, rounded corners")
for j in out:
    print(json.dumps(j))
