#!/usr/bin/env python3
"""GTT várka cities2: výběr seedů (cities2_pick.json), ploché přebarvení vlajek a nápisů (FIX), u Moskvy vyčištění
falešných popisků ve spodním okraji papíru (jako post_moscow.py), ořez fotomíst 1080×1350, 256 barev; suvenýry
ořez na obsah, čtverec s okrajem 6 %, 512², alfa, 256 barev (jako post_souv.py).
  python3 post_cities2.py ROOT ASSETS   (ROOT obsahuje png/photos/<city>/ a alpha/souvenirs/)"""
import sys, os, json, numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PICK = json.load(open(os.path.join(HERE, "cities2_pick.json")))
FIX = PICK.pop("_fix", {})


def fill(a, x0, y0, x1, y1):
    ring = np.concatenate([a[y0:y1, max(x0 - 3, 0)], a[y0:y1, min(x1 + 2, a.shape[1] - 1)],
                           a[max(y0 - 3, 0), x0:x1], a[min(y1 + 2, a.shape[0] - 1), x0:x1]])
    q = (ring // 24).astype(int); keys = q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]
    u, c = np.unique(keys, return_counts=True)
    a[y0:y1, x0:x1] = np.median(ring[keys == u[c.argmax()]], axis=0).astype(np.uint8)


def clean_bottom(a, M=45):
    """Spodní okraj papíru (pruh pod ilustrací, nejvýš M px) -> barva papíru."""
    h = a.shape[0]
    paper = np.median(a[h - 4:h].reshape(-1, 3), axis=0)
    if not (paper[0] > 200 and paper[1] > 185 and paper[2] > 150):
        return  # ilustrace sahá až k hraně (bez papírového okraje)
    off = np.linalg.norm(a.astype(np.float32) - paper, axis=2) > 40
    rows = off.mean(axis=1)
    yb = h - 1
    while yb > h * 0.8 and rows[yb] < 0.5: yb -= 1
    yb = max(yb, h - 1 - M)
    if yb < h - 2: a[yb + 2:] = paper.astype(np.uint8)


root, assets = sys.argv[1], sys.argv[2]
for city in ("tokyo", "moscow"):
    out = os.path.join(assets, "photos", city)
    os.makedirs(out, exist_ok=True)
    for k, s in PICK[city].items():
        a = np.asarray(Image.open(f"{root}/png/photos/{city}/{k}_s{s}.png").convert("RGB")).copy()
        for b in FIX.get(f"{city}/{k}", []): fill(a, *b)
        if city == "moscow": clean_bottom(a)
        im = Image.fromarray(a); w, h = im.size; l, t = (w - 1080) // 2, (h - 1350) // 2
        im.crop((l, t, l + 1080, t + 1350)).quantize(256, method=Image.Quantize.MEDIANCUT).save(f"{out}/{k}.png", optimize=True)
        print(city, k, s)
out = os.path.join(assets, "souvenirs")
os.makedirs(out, exist_ok=True)
for k, s in PICK["souvenirs"].items():
    im = Image.open(f"{root}/alpha/souvenirs/{k}_s{s}.png").convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    im = im.crop(a.getbbox()); w, h = im.size; side = int(max(w, h) / 0.88)
    c = Image.new("RGBA", (side, side), (0, 0, 0, 0)); c.paste(im, ((side - w) // 2, (side - h) // 2))
    c.resize((512, 512), Image.LANCZOS).quantize(256, method=Image.Quantize.FASTOCTREE).save(f"{out}/{k}.png", optimize=True)
    print("souvenir", k, s)
