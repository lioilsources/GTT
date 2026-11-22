#!/usr/bin/env python3
"""GTT oprava 2: pohlednice bez nápisů (amnh, guggenheim, msg), synagoga bez křížů, NYC textury jako výřez povrchu."""
import json
A = ("flat vector illustration, cel shading with two or three flat tones per surface, thin dark outline, "
     "clean geometric shapes, no gradients, crisp edges")
C = ("retro screenprint risograph poster style, limited palette of four inks, visible paper grain texture, "
     "fine halftone dots, slight ink misregistration")
PAL_NYC = "color palette of warm grey asphalt, taxi yellow, red brick, cool steel blue"
PAL_PRG = "color palette of ochre, terracotta red, copper verdigris green, warm cream paper"
NEG = ("text, letters, words, inscription, engraved letters, lettering, typography, sign, signage, marquee, banner, "
       "billboard, screen, logo, watermark, signature, license plate, photo, blurry, low quality")
out = []
PC = {
 "nyc/amnh": "the American Museum of Natural History, Central Park West facade with tall columns and an equestrian "
             "statue in front, seen from a low angle so the frieze is hidden behind the columns, all stone surfaces plain",
 "nyc/guggenheim": "the Guggenheim Museum white spiral building seen from across Fifth Avenue among autumn trees, "
                   "the smooth curved white bands are completely plain and blank",
 "nyc/msg": "the round drum-shaped Madison Square Garden arena seen from above at an angle at dusk, a plain concrete "
            "and glass cylinder with vertical ribs, completely blank facade, city streets around",
}
for k, v in PC.items():
    for s in (211, 212, 213, 214):
        out.append({"name": f"postcards/{k}_s{s}", "w": 1088, "h": 1360, "seed": s, "model": "qwen",
                    "prompt": f"illustrated travel postcard of {v}, vertical composition, no border. Style: {A}, {PAL_NYC}. "
                              "Absolutely no text or letters anywhere.", "neg": NEG})
for s in (211, 212, 213, 214):
    out.append({"name": f"postcards/prague/old_new_synagogue_s{s}", "w": 1088, "h": 1360, "seed": s, "model": "qwen",
        "prompt": "illustrated travel postcard of the medieval Old New Synagogue in the Jewish Quarter of Prague: a low "
                  "rough stone hall building with a tall steep dark roof and a large triangular stepped brick gable "
                  "with saw-tooth brick steps, small pointed windows, a narrow old lane with a lamppost in front; "
                  "the gable steps end in plain brick, the building has no tower and nothing on top of the roof, "
                  "vertical composition, no border. Style: " + C + ", " + PAL_PRG + ". Absolutely no text.",
        "neg": NEG + ", cross, crucifix, church, christian symbol, steeple, spire, bell tower, turret, finial"})
TEX = ("a square close-up swatch of the material only, flat surface filling the entire image edge to edge, camera "
       "pointing straight down, even neutral light, no shadows, no objects, no borders, no road markings, no lines, "
       "no frame. Style: flat vector, two or three flat tones, simple shapes")
T = {"nyc/asphalt": "plain warm grey asphalt with small speckles of lighter and darker aggregate, colors #A49E9A #98969B #887F82",
     "nyc/roof_tar": "flat roof covered in dark grey gravel and tar with a few straight membrane seams, colors #887F82 #43384A #98969B",
     "nyc/sidewalk_concrete": "light concrete with a few faint hairline cracks and subtle speckles, no joints, colors #DEC3B4 #DAC2B0"}
for k, v in T.items():
    for s in (411, 412, 413):
        out.append({"name": f"cities/{k}_s{s}", "w": 1024, "h": 1024, "seed": s, "model": "qwen",
                    "prompt": f"{v}. {TEX}.", "neg": NEG + ", perspective, horizon, road, lane, curb, building, car, frame, border"})
for j in out: print(json.dumps(j))
