#!/usr/bin/env python3
"""GTT oprava 3: pohlednice amnh bez nápisu na štítu (Rose Center, CPW fasáda z ostrého úhlu)."""
import json
A = ("flat vector illustration, cel shading with two or three flat tones per surface, thin dark outline, "
     "clean geometric shapes, no gradients, crisp edges")
PAL_NYC = "color palette of warm grey asphalt, taxi yellow, red brick, cool steel blue"
NEG = ("text, letters, words, inscription, engraved letters, lettering, typography, sign, signage, banner, "
       "logo, watermark, signature, license plate, photo, blurry, low quality")
V = {
 "rose": "the Rose Center for Earth and Space at the American Museum of Natural History: a huge glass cube with a "
         "giant white sphere floating inside, seen from the street at dusk with trees in front",
 "cpw": "the American Museum of Natural History, Central Park West facade with tall columns and an equestrian statue, "
        "seen from a steep low side angle, the stone frieze above the columns is blank plain stone with no inscription",
}
for k, v in V.items():
    for s in (221, 222, 223, 224):
        print(json.dumps({"name": f"postcards/nyc/amnh_{k}_s{s}", "w": 1088, "h": 1360, "seed": s, "model": "qwen",
            "prompt": f"illustrated travel postcard of {v}, vertical composition, no border. Style: {A}, {PAL_NYC}. "
                      "Blank stone surfaces, no inscription, absolutely no text or letters anywhere.", "neg": NEG}))
