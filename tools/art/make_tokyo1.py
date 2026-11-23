#!/usr/bin/env python3
"""GTT Tokio (v2 = mode postcards2: bez zeber a sakur z palety, bez cedulí, 3 seedy): style check (styl D), 25 pohlednic, 2 AI textury. Vypíše JSONL pro run_board.py.
  python3 make_tokyo1.py style|postcards|tex"""
import json, sys
D = ("anime cel shading, clean thin lineart, soft painted atmospheric sky and ambient light, "
     "high quality anime background art")
D_TOP = "anime cel shading, flat cel-shaded color areas with soft shadow tones, no outlines, clean game art"
PAL = ("color palette of warm daylight concrete greys, pale blue-green asphalt, white zebra markings, "
       "vermilion red accents, sakura pink accents, deep indigo shadows")
BLANK = ("all shop signs, banners and billboards are blank plain colored panels without any characters, "
         "no readable text, no Japanese characters, no logos, no brands, no license plates")
NEG = ("text, letters, words, kanji, hiragana, katakana, japanese characters, chinese characters, glyphs, writing, "
       "calligraphy, inscription, sign text, logo, brand name, watermark, signature, license plate, robot, mecha, "
       "anime character, mascot, photo, photorealistic, blurry, low quality, deformed, child, nsfw")
out = []
def job(name, w, h, seed, prompt, neg=NEG):
    out.append({"name": name, "w": w, "h": h, "seed": seed, "model": "qwen", "prompt": prompt, "neg": neg})
mode = sys.argv[1]
P = {
 "tokyo_tower": "Tokyo Tower in vermilion and white with sakura trees in the foreground",
 "skytree": "the Tokyo Skytree tower rising above low old Sumida neighbourhood roofs and the river",
 "shibuya_crossing": "the Shibuya scramble crossing seen from above at dusk with crowds crossing and tall buildings with blank glowing screens",
 "kaminarimon": "the Kaminarimon gate of Sensoji temple with its huge red paper lantern which is completely plain red, vermilion gate",
 "meiji_jingu": "the giant wooden torii gate of Meiji Shrine in a tall green forest path with gravel",
 "tokyo_station": "the red brick Marunouchi facade of Tokyo Station with its domes and the plaza in front",
 "rainbow_bridge": "the white Rainbow Bridge suspension bridge over Tokyo Bay at dusk with the city skyline",
 "nijubashi": "the Nijubashi double bridge over the Imperial Palace moat with the white watchtower and pine trees",
 "kabukiza": "the Kabukiza theatre with its traditional curved Japanese gabled roof facade in Ginza",
 "metropolitan_gov": "the twin-towered Tokyo Metropolitan Government Building in Shinjuku against a blue sky",
 "shinjuku_gyoen": "Shinjuku Gyoen garden with a pond, sakura trees in full bloom and skyscrapers behind",
 "tokyo_national_museum": "the Tokyo National Museum main building with its tiled Japanese roof and the fountain in Ueno Park",
 "ginza_clock": "the Ginza corner building with its elegant round clock tower at the crossing, the clock face has only plain marks",
 "nakamise": "the Nakamise shopping street to Sensoji with rows of small stalls with red roofs and a temple gate at the end",
 "akihabara": "an Akihabara electric town street with colorful tall narrow buildings covered in blank glowing colored panels",
 "takeshita": "the narrow Takeshita street in Harajuku with colorful pastel shopfronts and adult shoppers",
 "zojoji": "Zojoji temple main gate with Tokyo Tower rising behind it",
 "roppongi_hills": "the Roppongi Hills Mori Tower with a giant spider sculpture in the plaza",
 "hamarikyu": "Hamarikyu garden with a teahouse on a pond and modern skyscrapers behind",
 "tokyo_dome": "the white inflated roof of the Tokyo Dome stadium with a roller coaster next to it",
 "nihonbashi": "the old stone Nihonbashi bridge with bronze lampposts and an elevated expressway above",
 "kokugikan": "the Ryogoku Kokugikan sumo hall with its green Japanese roof",
 "golden_gai": "a narrow Golden Gai alley at night with tiny bars, warm lanterns which are plain, and tangled wires",
 "tsukiji_outer": "the Tsukiji outer market lane with small food stalls, steam and adult shoppers",
 "sumida_river": "the Sumida river with a futuristic sightseeing boat, bridges and sakura along the embankment",
}
if mode == "style":
    for s in (11, 12):
        job(f"styleboard/tokyo/intersection_s{s}", 1088, 1920, s,
            "orthographic top-down view looking straight down at a large Tokyo scramble crossing intersection with "
            "wide white zebra stripes crossing diagonally and straight, pale blue-green asphalt, warm grey concrete "
            "sidewalks, small compact cars driving on the LEFT side of the road seen from directly above, many tiny "
            "adult pedestrians seen from above crossing, flat building rooftops with air conditioning units at the "
            "edges, a few sakura trees, light from the top-left, short shadows toward bottom-right. "
            f"Style: {D_TOP}, {PAL}. {BLANK}.")
    for s in (11, 12):
        job(f"styleboard/tokyo/postcard_s{s}", 1088, 1360, s,
            "illustrated travel postcard of Tokyo Tower in vermilion and white rising above a Tokyo street with "
            f"sakura trees in bloom, vertical composition, no border. Style: {D}, {PAL}. {BLANK}.")
elif mode == "postcards":
    for k, v in P.items():
        job(f"postcards/tokyo/{k}_s201", 1088, 1360, 201,
            f"illustrated travel postcard of {v} in Tokyo, vertical composition, no border. Style: {D}, {PAL}. {BLANK}.")
if mode == "postcards2":
    PAL_PC = ("color palette of warm daylight concrete greys, soft sky blue, vermilion red accents, "
              "deep indigo shadows, fresh greens")
    NOSIGN = ("no signs, no billboards, no banners, no flags, no shop signs, no screens, no posters, no lanterns with "
              "writing, plain blank walls, no text anywhere, no people's faces on displays")
    NEG2 = NEG + ", zebra crossing, crosswalk, road markings in the foreground, signboard, billboard, banner, poster, screen"
    for k, v in P.items():
        for s in (211, 212, 213):
            job(f"postcards/tokyo/{k}_s{s}", 1088, 1360, s,
                f"illustrated travel postcard of {v} in Tokyo, vertical composition, no border, the landmark is the "
                f"main subject filling the frame. Style: {D}, {PAL_PC}. {NOSIGN}.", NEG2)
elif mode == "postcards3":
    # v3: bez lampionů a cedulí (Qwen na ně kreslí falešné znaky), rumělka jen u památek, které ji mají
    KEEP = {"metropolitan_gov", "rainbow_bridge"}
    LANT = {"kaminarimon"}  # lampion je památka: hladký, bez znaků
    PAL3 = "color palette of warm daylight concrete greys, soft sky blue, deep indigo shadows, fresh greens"
    NOSIGN3 = ("no paper lanterns, no hanging lanterns, no signs, no signboards, no billboards, no banners, no flags, "
               "no posters, no screens, no plaques, plain blank walls and blank shop awnings, no text anywhere")
    NEG3 = NEG + (", zebra crossing, crosswalk, paper lantern, chochin, hanging lantern, signboard, billboard, banner, "
                  "flag, poster, screen, plaque, nameplate, noren with writing, mockup, picture frame, border, wall behind")
    for k, v in P.items():
        if k in KEEP: continue
        ns = NOSIGN3.replace("no paper lanterns, no hanging lanterns, ", "") if k in LANT else NOSIGN3
        ng = NEG3.replace(", paper lantern, chochin, hanging lantern", "") if k in LANT else NEG3
        for s in (221, 222, 223):
            job(f"postcards/tokyo/{k}_s{s}", 1088, 1360, s,
                f"illustrated travel postcard of {v} in Tokyo, vertical composition, full bleed illustration, the "
                f"landmark is the main subject. Style: {D}, {PAL3}. {ns}.", ng)
elif mode == "postcards4":
    # v4: finální sada (landmarks.yaml PR #154) – 9 chybějících; ulice bez cedulí přes kompozici
    PAL3 = "color palette of warm daylight concrete greys, soft sky blue, deep indigo shadows, fresh greens"
    NOSIGN3 = ("no paper lanterns, no hanging lanterns, no signs, no signboards, no billboards, no banners, no flags, "
               "no posters, no screens, no plaques, plain blank walls and blank shop awnings, no text anywhere")
    NEG4 = NEG + (", zebra crossing, crosswalk, paper lantern, chochin, hanging lantern, signboard, billboard, banner, "
                  "flag, poster, screen, plaque, nameplate, noren with writing, mockup, picture frame, border, wall behind")
    P4 = {
     "nakamise": "the Nakamise shopping street in Asakusa early in the morning with all shop shutters pulled down, plain red "
                 "and white striped awnings, empty stone pavement, the large red Hozomon temple gate in the background",
     "tsukiji_outer": "a close-up of a Tsukiji outer market food stall counter: fresh fish on crushed ice, rolls of tamagoyaki "
                      "omelette, small ceramic bowls, steam, no signage in the frame",
     "ameyoko": "the Ameyoko market street under the elevated railway arches in Ueno seen from a distance, a train on the "
                "viaduct above, shop signs are plain colored rectangles with nothing on them",
     "kanda_myojin": "the vermilion and gold Kanda Myojin shrine gate and main hall with green roof tiles",
     "budokan": "the Nippon Budokan octagonal hall with its sweeping roof and golden onion-shaped finial among trees",
     "akasaka_palace": "the neo-baroque Akasaka Palace State Guest House with its green copper roof, white stone facade and "
                       "the large fountain garden in front",
     "hie_shrine": "Hie Shrine with a tunnel of many vermilion torii gates climbing stone stairs on a green hill",
     "kachidoki_bridge": "the steel Kachidoki drawbridge over the Sumida river with its two arched spans and tower houses",
     "national_diet": "the National Diet Building, a symmetric granite building with a stepped pyramid central tower, "
                      "in front of a wide lawn",
    }
    for k, v in P4.items():
        for s in (231, 232, 233):
            job(f"postcards/tokyo/{k}_s{s}", 1088, 1360, s,
                f"illustrated travel postcard of {v} in Tokyo, vertical composition, full bleed illustration, the "
                f"landmark is the main subject. Style: {D}, {PAL3}. {NOSIGN3}.", NEG4)
elif mode == "tex":
    TEX = ("a square close-up swatch of the material only, flat surface filling the entire image edge to edge, camera "
           "pointing straight down, even neutral light, no shadows, no objects, no borders, no frame, no perspective. "
           f"Style: {D_TOP}")
    T = {"asphalt": "plain pale blue-grey asphalt with fine lighter speckles of aggregate, no markings",
         "sidewalk_tile": "grid of square grey-beige concrete paving tiles with thin joints and one straight strip of "
                          "yellow tactile paving tiles with raised bumps running vertically"}
    for k, v in T.items():
        for s in (411, 412, 413):
            job(f"cities/tokyo/{k}_s{s}", 1024, 1024, s, f"{v}. {TEX}.",
                NEG + ", perspective, horizon, road, curb, building, car, frame, border, rounded corners")
for j in out: print(json.dumps(j))
