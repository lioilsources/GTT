#!/usr/bin/env python3
"""GTT várka cities2: fotomísta Tokia (styl D, anime) a Moskvy (styl E, konstruktivistický plakát) a suvenýry obou
měst (styl A jako suvenýry NYC, alfa přes BiRefNet). Id = spoty `kind: photo|souvenir` v content/cities/<city>/spots.yaml.
Bez textu, znaků, azbuky, vlajek, symbolů a značek; bez aut (v NYC měly taxíky falešné nápisy).
Vypíše JSONL pro run_board.py.
  python3 make_cities2.py photos|tokyo2|tokyo3|souvenirs"""
import json, sys

NOCAR = "no cars, no taxis, no buses, no vehicles"
# --- Tokio (styl D, jako make_tokyo1 postcards3/4) ---
D = ("anime cel shading, clean thin lineart, soft painted atmospheric sky and ambient light, "
     "high quality anime background art")
PAL_T = "color palette of warm daylight concrete greys, soft sky blue, deep indigo shadows, fresh greens"
NOSIGN_T = ("no paper lanterns, no hanging lanterns, no signs, no signboards, no billboards, no banners, no flags, "
            "no posters, no screens, no plaques, plain blank walls and blank shop awnings, no text anywhere")
NEG_T = ("text, letters, words, kanji, hiragana, katakana, japanese characters, chinese characters, glyphs, writing, "
         "calligraphy, inscription, sign text, logo, brand name, watermark, signature, license plate, robot, mecha, "
         "anime character, mascot, photo, photorealistic, blurry, low quality, deformed, child, nsfw, zebra crossing, "
         "paper lantern, hanging lantern, signboard, billboard, banner, flag, poster, screen, plaque, nameplate, "
         "mockup, picture frame, border, car, taxi, bus, vehicle")
TOKYO = {
 "photo_tower_shiba": "Tokyo Tower in vermilion and white rising above the green trees of Shiba Park, a park path in "
                      "the foreground",
 "photo_skytree_jikken": "the very tall slender Tokyo Skytree tower seen across the wide Sumida river with low "
                         "riverside buildings and a long embankment",
 "photo_nijubashi": "the stone double-arched Nijubashi bridge over the Imperial Palace moat with a white watchtower "
                    "and black pine trees, seen from the wide gravel plaza",
 "photo_station_front": "the long red brick Marunouchi facade of Tokyo Station with its two domes seen straight down "
                        "a wide tree-lined boulevard between glass office towers",
 "photo_kachidoki": "the steel Kachidoki drawbridge with two arched spans over the Sumida river seen from the "
                    "riverside promenade, towers behind",
 "photo_nihonbashi": "the old stone Nihonbashi bridge with bronze lampposts and a heavy elevated expressway running "
                     "low above it over the canal",
 "photo_ginza_lights": "a long straight wide shopping avenue canyon at dusk lined with elegant modern buildings with "
                       "glowing plain colored facades and windows, pedestrians, no signage",
 "photo_moat_chidorigafuchi": "a wide palace moat with a stone embankment wall, cherry trees along the water and small "
                              "rowboats",
 "photo_kanda_river": "a narrow river in a deep green ravine with a stone bridge and an orange suburban train crossing "
                      "on a viaduct",
 "photo_akasaka_palace": "the ornate black and gold wrought-iron main gate of a neo-baroque palace with a green copper "
                         "roof and white stone facade behind",
}
# --- Moskva (styl E, jako make_moscow1) ---
E = ("Russian constructivist poster art style, flat hard-edged color fills, bold diagonal composition, geometric "
     "shapes, strong silhouettes, screen-printed paper texture, no gradients, no airbrush, original artwork")
PAL_M = ("strictly limited palette of signal red, deep black, warm cream paper, with small accents of ochre gold and "
         "warm grey; water is blue and trees are green")
NOSIGN_M = ("absolutely no text anywhere, no letters, no slogans, no banners, no signs, no billboards, no flags, no "
            "posters on walls, no emblems, plain blank walls")
NEG_M = ("text, letters, words, cyrillic, latin letters, typography, slogan, caption, headline, title, glyphs, writing, "
         "inscription, banner with writing, signboard, billboard, logo, brand name, watermark, signature, license "
         "plate, hammer and sickle, emblem, coat of arms, flag, political symbol, portrait of a leader, propaganda "
         "figure, soldier, weapon, gradient, airbrush, photo, photorealistic, 3d render, blurry, low quality, deformed, "
         "child, nsfw, border, frame, mockup, pennant, flags on roofs, red flag, flagpole, printed caption, small print "
         "in the margin, artist signature, car, taxi, bus, vehicle")
MOSCOW = {
 "photo_kremlin_bridge": "the red brick Kremlin wall with its towers and golden cathedral domes seen from a long flat "
                         "steel arch bridge over the Moskva river",
 "photo_basils_moskvoretsky": "Saint Basil's Cathedral with its colorful onion domes seen from a bridge over the "
                              "river, the Kremlin wall to the side",
 "photo_christ_patriarch_bridge": "the white Cathedral of Christ the Saviour with five golden domes seen from a "
                                  "pedestrian steel bridge over the river",
 "photo_kotelnicheskaya": "a monumental stepped high-rise with a central spire towering over the confluence of a "
                          "small river and the Moskva river, embankments",
 "photo_bolshoi_square": "the Bolshoi Theatre neoclassical colonnade with a quadriga of horses seen across a square "
                         "with a fountain and flower beds",
 "photo_ministry_ring": "a monumental stepped skyscraper with a tall central spire seen straight down a wide ring "
                        "boulevard",
 "photo_zaryadye_river": "the wide Moskva river and its embankments seen from a modern park on a hill with a "
                         "cantilevered viewpoint bridge",
 "photo_gorky_embankment": "a long tree-lined river embankment promenade with granite parapets, park trees, a few "
                           "adult strollers and the river beside it",
}
# --- suvenýry (styl A, jako make_souv1) ---
A = ("flat vector illustration, cel shading with two or three flat tones per surface, thin dark outline, "
     "clean geometric shapes, no gradients, crisp edges")
NEG_S = ("text, letters, words, inscription, lettering, typography, kanji, cyrillic, sign, label, sticker, logo, brand "
         "name, watermark, signature, price tag, photo, photorealistic, blurry, low quality, multiple objects, hands, "
         "people, table, shelf, cast shadow, background scenery, flag, emblem, political symbol, weapon")
SOUV = {
 "souvenir_nakamise": "a small red paper folding fan with a plain red pattern of golden waves, half open, standing upright",
 "souvenir_akihabara": "a small round plastic capsule toy ball, half transparent and half bright blue, with a tiny "
                       "cute generic robot figurine inside",
 "souvenir_tsukiji": "a small Japanese kitchen knife with a wooden handle lying on its wooden box, the blade is plain "
                     "and polished with no engraving",
 "souvenir_arbat": "a set of three painted wooden nesting dolls in decreasing size standing side by side, red and gold "
                   "floral patterns, friendly faces",
 "souvenir_varvarka": "a small decorated porcelain teacup and saucer with a blue and white floral pattern",
 "souvenir_kuznetsky": "a small stack of three blank illustrated picture postcards fanned out, showing only colorful "
                       "abstract city skyline shapes, with no writing",
}
out = []
mode = sys.argv[1]
# v3 (s627–629): pohledy odkud žádná ulice s obchody není (z vody, z mostu, z trávníku), v2 měla pořád stánky s lampiony
TOKYO3 = {
 "photo_tower_shiba": "Tokyo Tower in vermilion and white seen across a wide open lawn and a pond of Shiba Park with big trees",
 "photo_skytree_jikken": "the very tall slender Tokyo Skytree seen from a small boat in the middle of the wide Sumida river, "
                         "only water, embankments and distant low buildings",
 "photo_nijubashi": "the stone double-arched Nijubashi bridge reflected in the dark palace moat with black pine trees and a "
                    "white watchtower, seen from the low stone wall of the moat",
 "photo_station_front": "the long red brick Tokyo Station with two domes seen across a wide empty paved plaza and lawn "
                        "with rows of young zelkova trees, glass towers on both sides",
 "photo_kachidoki": "the steel Kachidoki drawbridge with two arched spans and two stone tower houses seen from the middle "
                    "of the wide Sumida river, water in the foreground",
 "photo_nihonbashi": "the old stone Nihonbashi double-arched bridge seen from the canal water level, the green steel elevated "
                     "expressway passing low above it",
 "photo_ginza_lights": "a long straight wide avenue canyon at dusk seen from high above on a footbridge, elegant modern "
                       "buildings with glowing glass facades, tiny pedestrians far below",
 "photo_moat_chidorigafuchi": "a wide palace moat with a high stone embankment wall and a white keep, cherry trees in bloom "
                              "along the water, two small rowboats, seen from a rowboat on the water",
 "photo_kanda_river": "a narrow river in a deep green ravine with an arched stone railway bridge and an orange train crossing, "
                      "seen from the water between the green cliffs",
 "photo_akasaka_palace": "the ornate black and gold wrought-iron gate of a neo-baroque palace with a green copper dome, seen "
                         "across a wide empty gravel forecourt with lawns",
}
if mode == "tokyo3":
    NEG_T3 = NEG_T + (", shop, storefront, stall, awning, noren, banner, nobori, vertical banner, lantern, lamp post, "
                      "street lamp, signpost, road sign, vending machine, sign, kanji, flag, flagpole")
    for k, v in TOKYO3.items():
        for s in (627, 628, 629):
            out.append({"name": f"photos/tokyo/{k}_s{s}", "w": 1088, "h": 1360, "seed": s, "model": "qwen",
                        "prompt": f"illustrated scenic view of {v}, Tokyo, vertical composition, full bleed illustration, "
                                  f"calm and uncluttered. Style: {D}, {PAL_T}. {NOSIGN_T}, {NOCAR}, no flags.",
                        "neg": NEG_T3})
if mode in ("photos", "tokyo2"):
    # v2 (s624–626): v1 (s621–623) měla lampiony a cedule se znaky, praporky a vlajky -> čisté popředí, bez obchodů
    CLEAN_T = ("wide calm view from a distance, clean empty foreground of pavement, gravel, grass or water, no shops, "
               "no street stalls, no shop awnings, no lamp posts, no street furniture, no people close to the viewer")
    NEG_T2 = NEG_T + (", shop, storefront, stall, awning, noren, nobori banner, vertical banner, lantern, lamp post, "
                      "street lamp, signpost, vending machine, sign, kanji")
    for k, v in TOKYO.items():
        for s in (624, 625, 626):
            out.append({"name": f"photos/tokyo/{k}_s{s}", "w": 1088, "h": 1360, "seed": s, "model": "qwen",
                        "prompt": f"illustrated scenic view of {v} in Tokyo, vertical composition, full bleed "
                                  f"illustration, {CLEAN_T}. Style: {D}, {PAL_T}. {NOSIGN_T}, {NOCAR}.",
                        "neg": NEG_T2})
    for k, v in (MOSCOW.items() if mode == "photos" else []):
        for s in (631, 632, 633):
            out.append({"name": f"photos/moscow/{k}_s{s}", "w": 1088, "h": 1360, "seed": s, "model": "qwen",
                        "prompt": f"illustrated scenic view of {v} in Moscow, vertical composition, full bleed "
                                  f"illustration, dynamic diagonal composition. Style: {E}, {PAL_M}. {NOSIGN_M}, "
                                  f"{NOCAR}.", "neg": NEG_M})
elif mode == "souvenirs":
    for k, v in SOUV.items():
        for s in (641, 642, 643):
            out.append({"name": f"souvenirs/{k}_s{s}", "w": 1024, "h": 1024, "seed": s, "model": "qwen",
                        "prompt": f"a single souvenir object: {v}, seen from the front, centered, filling most of the "
                                  f"frame, isolated on a plain flat white background. Style: {A}, warm cheerful colors. "
                                  "Absolutely no text, no letters, no logos.", "neg": NEG_S})
for j in out:
    print(json.dumps(j))
