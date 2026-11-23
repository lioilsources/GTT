#!/usr/bin/env python3
"""GTT suvenýry NYC (art-requests kap. 7): jeden předmět zepředu, styl A, bílé pozadí -> alfa přes BiRefNet."""
import json
A = ("flat vector illustration, cel shading with two or three flat tones per surface, thin dark outline, "
     "clean geometric shapes, no gradients, crisp edges")
NEG = ("text, letters, words, inscription, lettering, typography, sign, label, sticker, logo, brand name, watermark, "
       "signature, price tag, photo, photorealistic, blurry, low quality, multiple objects, hands, people, table, shelf, "
       "cast shadow, background scenery")
ITEM = {
 "souvenir_times_sq": "a small glass snow globe souvenir with tiny skyscrapers and falling snow inside, on a round dark base",
 "souvenir_canal": "a small white porcelain lucky cat figurine with one raised waving paw, red collar with a golden bell",
 "souvenir_battery": "a small green copper souvenir statuette of a robed woman holding a torch high and a tablet, "
                     "crown with rays, on a small square pedestal, the tablet and pedestal are completely blank",
 "souvenir_dumbo": "a small desk model of a stone suspension bridge with two towers with gothic arches and cables, "
                   "on a wooden base",
 "souvenir_soho": "a canvas tote bag with a bold abstract geometric pattern of colorful shapes, standing upright",
}
for k, v in ITEM.items():
    for s in (601, 602, 603, 604):
        print(json.dumps({"name": f"souvenirs/{k}_s{s}", "w": 1024, "h": 1024, "seed": s, "model": "qwen",
            "prompt": f"a single souvenir object: {v}, seen from the front, centered, filling most of the frame, "
                      f"isolated on a plain flat white background. Style: {A}, warm cheerful colors. "
                      "Absolutely no text, no letters, no logos.", "neg": NEG}))
