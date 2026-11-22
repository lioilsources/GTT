#!/usr/bin/env python3
"""GTT várka 1: NPC (styl A, manga), 54 pohlednic (NYC=A, Praha=C), test spritů kolmo shora (A).
Vypíše JSONL pro run_board.py. Jména = cesty v assets/ (bez přípony)."""
import json

A = ("flat vector illustration, cel shading with two or three flat tones per surface, thin dark outline, "
     "clean geometric shapes, no gradients, crisp edges")
C = ("retro screenprint risograph poster style, limited palette of four inks, visible paper grain texture, "
     "fine halftone dots, slight ink misregistration")
PAL_NYC = "color palette of warm grey asphalt, taxi yellow, red brick, cool steel blue"
PAL_PRG = "color palette of ochre, terracotta red, copper verdigris green, warm cream paper"
NOTXT = "no text, no letters, no words, no signs, no logos, no license plates"
NEG = ("text, letters, words, caption, name, watermark, signature, logo, brand name, license plate, "
       "photo, photorealistic, blurry, low quality, deformed, extra limbs, extra fingers, child, nsfw, nudity, cleavage")
NEG_SPRITE = NEG + ", isometric, three-quarter view, perspective, side view, tilted, angled view, taxi sign, roof sign"

out = []
def job(name, w, h, seed, prompt, neg=NEG):
    out.append({"name": name, "w": w, "h": h, "seed": seed, "model": "qwen", "prompt": prompt, "neg": neg})

# --- NPC: stejný popis + seed na postavu, mění se jen výraz -------------------------------------------
NPC = {
    "maya": "Maya, a 24-year-old adult woman, lifestyle influencer, wavy shoulder-length brown hair, warm brown eyes, "
            "light golden makeup, dark green bomber jacket over a white top, small gold hoop earrings",
    "theo": "Theo, a 27-year-old adult man, hipster barista, short dark curly hair, neat short beard, round glasses, "
            "rust-colored beanie, denim apron over a striped shirt",
    "ray":  "Ray, a 58-year-old man, veteran New York taxi driver, grey stubble, short grey hair under a flat cap, "
            "kind tired eyes with crow's feet, brown leather jacket",
    "iris": "Iris, a 29-year-old adult woman, bookworm, chin-length black bob haircut, oversized tortoiseshell glasses, "
            "a pencil tucked behind her ear, mustard cardigan over a cream blouse",
    "jules": "Jules, a 31-year-old adult man, street musician, messy auburn hair to the chin, light stubble, "
             "guitar strap across the chest, worn denim jacket with pins, red scarf",
    "dana": "Dana, a 38-year-old adult woman, busy corporate manager, sleek dark blonde hair in a low bun, "
            "sharp navy blazer over a white shirt, small pearl earrings, wireless earbud in one ear",
}
EXPR = {"happy": "big warm genuine smile", "neutral": "calm neutral expression, slight smile",
        "annoyed": "annoyed expression, raised eyebrow, slight frown, unimpressed"}
STYLE_NPC = f"anime manga character art, attractive, clearly adult, fully clothed. Style: {A}, harmonious palette"
for i, (nid, desc) in enumerate(NPC.items()):
    seed = 101 + i
    for ex, ed in EXPR.items():
        job(f"npc/{nid}_{ex}", 1024, 1024, seed,
            f"head and shoulders portrait of {desc}, {ed}, facing the viewer, centered, "
            f"plain flat light grey background. {STYLE_NPC}. {NOTXT}.")
    job(f"npc/{nid}_bust", 768, 1280, seed,
        f"waist-up character card of {desc}, {EXPR['happy']}, confident pose, centered, "
        f"plain flat light grey background. {STYLE_NPC}. {NOTXT}.")

# --- Pohlednice ---------------------------------------------------------------------------------------
NYC = {
    "empire_state": "the Empire State Building", "chrysler": "the Chrysler Building with its Art Deco crown",
    "grand_central": "Grand Central Terminal facade and main concourse windows", "times_square": "Times Square at dusk with glowing abstract colorful billboards showing only shapes",
    "central_park": "Central Park with Bow Bridge and the skyline behind", "one_vanderbilt": "the One Vanderbilt skyscraper",
    "rockefeller": "Rockefeller Center plaza with the skating rink and 30 Rock tower", "one_bryant_park": "the One Bryant Park skyscraper above Bryant Park",
    "park_432": "the slender 432 Park Avenue supertall tower", "central_park_tower": "Central Park Tower supertall on 57th Street",
    "one57": "the One57 glass tower on 57th Street", "park_200": "the 200 Park Avenue tower above Grand Central",
    "eighth_620": "the New York Times Building tower on Eighth Avenue without any lettering", "hudson_yards_30": "30 Hudson Yards with the Edge observation deck",
    "msg": "Madison Square Garden round arena", "farley": "the Farley Building neoclassical colonnade (Moynihan Train Hall)",
    "un_hq": "the United Nations Headquarters slab building by the East River", "st_patricks": "St. Patrick's Cathedral Gothic spires on Fifth Avenue",
    "nypl": "the New York Public Library with its marble lions", "carnegie_hall": "Carnegie Hall Renaissance revival facade",
    "one_wtc": "One World Trade Center tower", "wtc_memorial": "the 9/11 Memorial reflecting pools with trees, calm and respectful",
    "woolworth": "the Woolworth Building Gothic skyscraper", "city_hall": "New York City Hall with its park and fountain",
    "federal_hall": "Federal Hall with George Washington statue on Wall Street", "trinity_church": "Trinity Church Gothic spire among skyscrapers",
    "flatiron": "the Flatiron Building", "washington_arch": "the Washington Square Arch with the fountain",
    "high_line": "the High Line elevated park with plantings between buildings", "met_museum": "the Metropolitan Museum of Art Beaux-Arts facade and steps",
    "amnh": "the American Museum of Natural History facade", "guggenheim": "the Guggenheim Museum spiral building",
    "lincoln_center": "Lincoln Center plaza with the fountain at night", "brooklyn_bridge": "the Brooklyn Bridge stone towers and cables",
}
PRG = {
    "prague_castle": "Prague Castle with St. Vitus Cathedral above the Vltava river", "old_town_square": "Old Town Square with the Tyn Church towers",
    "old_town_hall": "the Old Town Hall tower with the astronomical clock", "tyn_church": "the Gothic Church of Our Lady before Tyn",
    "bridge_tower": "the Old Town Bridge Tower at Charles Bridge", "st_nicholas": "the baroque St. Nicholas Church green dome in Lesser Town",
    "wenceslas_square": "Wenceslas Square with the St. Wenceslas statue", "national_museum": "the National Museum neo-Renaissance building with its dome",
    "national_theatre": "the National Theatre with its golden roof by the river", "dancing_house": "the Dancing House deconstructivist building on the riverbank",
    "powder_tower": "the Gothic Powder Tower", "municipal_house": "the Art Nouveau Municipal House",
    "rudolfinum": "the Rudolfinum concert hall by the river", "petrin_tower": "the Petrin lookout tower on a green hill",
    "zizkov_tower": "the Zizkov Television Tower", "vysehrad": "Vysehrad with the twin spires of the Basilica of St. Peter and Paul above the river",
    "main_station": "the Art Nouveau Prague main railway station hall", "old_new_synagogue": "the Gothic Old New Synagogue with its brick gable",
    "klementinum": "the Klementinum baroque library and astronomical tower", "vitkov": "the National Memorial on Vitkov Hill with the equestrian statue",
}
for k, v in NYC.items():
    job(f"postcards/nyc/{k}", 1088, 1360, 201,
        f"illustrated travel postcard of {v} in New York, vertical composition, no border. "
        f"Style: {A}, {PAL_NYC}. {NOTXT}, no real brands on buildings.")
for k, v in PRG.items():
    job(f"postcards/prague/{k}", 1088, 1360, 201,
        f"illustrated travel postcard of {v} in Prague, vertical composition, no border. "
        f"Style: {C}, {PAL_PRG}. {NOTXT}.")

# --- Test spritů kolmo shora (oprava vad v1) -------------------------------------------------------------
TOP = ("flat 2D top-down game sprite viewed from straight above at exactly 90 degrees, orthographic plan view, "
       "only the roof, hood and trunk are visible, perfectly symmetric left and right, front pointing to the top "
       "of the image, no perspective, centered on a plain flat white background, light from the top-left, short "
       "soft shadow to the bottom-right")
SPR = {
    "coupe": f"a small red two-door sports coupe car, {TOP}. Style: {A}",
    "lidka": f"a small boxy cream-colored 1980s four-door sedan car, {TOP}. Style: flat vector, thin dark outline, "
             "flat colors, no texture, ochre and cream palette",
    "ped":   "a single adult pedestrian walking, seen from straight above at exactly 90 degrees, top of the head and "
             "shoulders visible, arms and feet slightly visible, flat 2D top-down game sprite, no perspective, centered "
             f"on a plain flat white background, light from the top-left. Style: {A}",
}
for k, p in SPR.items():
    for s in (301, 302, 303, 304):
        job(f"test/sprites/{k}_s{s}", 1024, 1024, s, f"{p}. {NOTXT}.", NEG_SPRITE)

ORDER = {"test": 0, "npc": 1, "postcards": 2}
for j in sorted(out, key=lambda j: ORDER[j["name"].split("/")[0]]):
    print(json.dumps(j))
