#!/usr/bin/env python3
"""GTT suvenýry: výběr seedu, ořez na obsah, čtverec s okrajem 6 %, 512², alfa, 256 barev.
  python3 post_souv.py ALPHA_DIR RGB_DIR OUT_DIR
Sněžítko: BiRefNet bere bílé vločky jako pozadí, takže alfa = maska bez vnitřních děr a barvy z původního RGB."""
import sys, os
from PIL import Image, ImageDraw, ImageChops
PICK = {"souvenir_times_sq": 601, "souvenir_canal": 604, "souvenir_battery": 602,
        "souvenir_dumbo": 602, "souvenir_soho": 602}
FILL_HOLES = {"souvenir_times_sq"}
src, rgb, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
for k, s in PICK.items():
    im = Image.open(f"{src}/{k}_s{s}.png").convert("RGBA")
    if k in FILL_HOLES:
        m = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
        bg = m.copy(); ImageDraw.floodfill(bg, (0, 0), 128)
        holes = bg.point(lambda v: 255 if v == 0 else 0)
        im = Image.open(f"{rgb}/{k}_s{s}.png").convert("RGBA")
        im.putalpha(ImageChops.lighter(Image.open(f"{src}/{k}_s{s}.png").getchannel("A"), holes))
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    im = im.crop(a.getbbox()); w, h = im.size; side = int(max(w, h) / 0.88)
    c = Image.new("RGBA", (side, side), (0, 0, 0, 0)); c.paste(im, ((side - w) // 2, (side - h) // 2))
    c.resize((512, 512), Image.LANCZOS).quantize(256, method=Image.Quantize.FASTOCTREE).save(f"{out}/{k}.png", optimize=True)
print("ok")
