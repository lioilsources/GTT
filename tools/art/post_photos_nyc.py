#!/usr/bin/env python3
"""GTT fotomísta New York: výběr seedu z várky photos1 v2 (s611–s613, bez aut v promptu), automatické odstranění
drobných tmavých značek na žlutých taxících (falešné nápisy a znak podobný logu), ploché přebarvení dalších
nápisů (FIX), ořez 1080×1350, 256 barev.
  python3 post_photos_nyc.py SRC OUT   (SRC = adresář s <id>_s<seed>.png)"""
import sys, os, json, numpy as np
from PIL import Image
from scipy import ndimage

PICK = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "photos_nyc_pick.json")))
# (x0, y0, x1, y1) v souřadnicích 1088×1360; barva = převládající barva okolního prstence
FIX = {k: [tuple(b) for b in v] for k, v in PICK.pop("_fix", {}).items()}


def fill(a, x0, y0, x1, y1):
    ring = np.concatenate([a[y0:y1, max(x0 - 3, 0)], a[y0:y1, min(x1 + 2, a.shape[1] - 1)],
                           a[max(y0 - 3, 0), x0:x1], a[min(y1 + 2, a.shape[0] - 1), x0:x1]])
    q = (ring // 24).astype(int); keys = q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]
    u, c = np.unique(keys, return_counts=True)
    a[y0:y1, x0:x1] = np.median(ring[keys == u[c.argmax()]], axis=0).astype(np.uint8)


def detaxi(a):
    """Žlutá karoserie: tmavé komponenty menší než 4 % plochy vozu (nápisy, kolečko znaku, šachovnice, SPZ) -> žlutá.
    Jen u tvarů s oknem (tmavá plocha ≥ 6 % vozu); okna a pneumatiky jsou větší a zůstanou, protáhlé
    tvary (sloupy lamp, nohy chodců) se nemění. Vrací počet přebarvených pixelů."""
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    yel = (r > 200) & (g > 140) & (g < 222) & (b < 110) & (r - b > 120)
    lab, n = ndimage.label(yel)
    done = 0
    for i, sl in enumerate(ndimage.find_objects(lab)):
        area = int((lab[sl] == i + 1).sum())
        hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if area < 350 or hh > 300 or ww > 300:
            continue
        y0, y1 = max(sl[0].start - 6, 0), min(sl[0].stop + 6, a.shape[0])
        x0, x1 = max(sl[1].start - 6, 0), min(sl[1].stop + 6, a.shape[1])
        y = yel[y0:y1, x0:x1]
        body = ndimage.binary_fill_holes(ndimage.binary_closing(y, iterations=4))
        sub = a[y0:y1, x0:x1]
        lum = sub[..., 0] * 0.299 + sub[..., 1] * 0.587 + sub[..., 2] * 0.114
        red = (sub[..., 0].astype(int) > 150) & (sub[..., 1].astype(int) < 110)  # červené nápisy na střešní ceduli
        dark = body & ~y & (lum < 120)
        dl, dn = ndimage.label(dark)
        if dn == 0 or np.bincount(dl.ravel())[1:].max() < 0.06 * body.sum():
            continue  # bez okna = není to vůz (koruna stromu, chodník, lavička)
        marks = body & ~y & ((lum < 120) | red)
        ml, mn = ndimage.label(marks)
        col = np.median(sub[y], axis=0).astype(np.uint8)
        for j, msl in enumerate(ndimage.find_objects(ml)):
            m = ml[msl] == j + 1
            mh, mw = msl[0].stop - msl[0].start, msl[1].stop - msl[1].start
            if m.sum() < 0.04 * body.sum() and max(mh, mw) < 4 * max(1, min(mh, mw)):  # kompaktní značky, ne sloupy a nohy
                mm = np.zeros(body.shape, bool); mm[msl] = m
                mm = ndimage.binary_dilation(mm, iterations=1) & body
                sub[mm] = col
                done += int(mm.sum())
    return done


src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for k, s in PICK.items():
    a = np.asarray(Image.open(f"{src}/{k}_s{s}.png").convert("RGB")).copy()
    nd = detaxi(a)
    for f in FIX.get(k, []): fill(a, *f)
    im = Image.fromarray(a); w, h = im.size; l, t = (w - 1080) // 2, (h - 1350) // 2
    im.crop((l, t, l + 1080, t + 1350)).quantize(256, method=Image.Quantize.MEDIANCUT).save(f"{out}/{k}.png", optimize=True)
    print(k, s, "taxi px", nd)
