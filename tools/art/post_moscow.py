#!/usr/bin/env python3
"""GTT Moskva pohlednice (styl E): výběr seedů z várky moscow1 (s30x) a opravy fix1 (s31x), vyčištění okrajů papíru
(falešné popisky a podpisy v okraji -> barva papíru), ploché přebarvení vlajek, falešného nápisu a státního znaku,
ořez 1080×1350, 256 barev.
  python3 post_moscow.py SRC OUT   (SRC = adresář s <id>_s<seed>.png)"""
import sys, os, numpy as np
from PIL import Image, ImageDraw

PICK = {"spasskaya_tower": 301, "borovitskaya_tower": 301, "red_square": 302, "st_basils": 301,
        "upper_trading_rows": 301, "historical_museum": 302, "bolshoi": 302, "christ_saviour": 302,
        "pushkin_museum": 302, "tretyakov": 303, "old_arbat": 302, "patriarch_ponds": 302, "gorky_park": 302,
        "zaryadye": 302, "kotelnicheskaya": 303, "foreign_ministry": 303, "kudrinskaya": 301, "red_gates": 302,
        "lubyanka_square": 302, "manege": 303, "state_library": 301, "house_on_embankment": 301,
        "bolshoy_kamenny": 302, "pushkin_square": 0, "komsomolskaya": 302}
PICK["pushkin_square"] = int(os.environ.get("PUSHKIN_SEED", "312"))
# (x0, y0, x1, y1, tvar) v souřadnicích 1088×1360; rect = medián okolního prstence, disc = převládající barva uvnitř elipsy
FIX = {
    "red_square": [(695, 4, 738, 32, "rect"), (526, 448, 552, 465, "rect")],   # rudé praporky na věžích
    "historical_museum": [(572, 38, 630, 80, "rect")],                         # prapor
    "tretyakov": [(934, 470, 976, 512, "rect")],                               # prapor
    "patriarch_ponds": [(468, 280, 510, 324, "rect")],                         # černá vlajka v siluetě
    "kudrinskaya": [(550, 62, 584, 94, "rect")],                               # trikolóra
    "foreign_ministry": [(566, 430, 626, 510, "disc")],                        # státní znak na věži -> plochý zlatý kotouč
    "red_gates": [(556, 40, 612, 84, "rect")],                                 # prapor
    "lubyanka_square": [(545, 197, 578, 234, "rect")],                         # trikolóra
    "state_library": [(860, 282, 916, 342, "rect")],                           # trikolóra
    "komsomolskaya": [(523, 847, 546, 880, "rect")],                           # trikolóra ve štítu
    "old_arbat": [(278, 798, 369, 838, "rect")],                               # falešný nápis na cedulce
}


def fill(a, x0, y0, x1, y1, shape):
    if shape == "rect":
        ring = np.concatenate([a[y0:y1, max(x0 - 3, 0)], a[y0:y1, min(x1 + 2, a.shape[1] - 1)],
                               a[max(y0 - 3, 0), x0:x1], a[min(y1 + 2, a.shape[0] - 1), x0:x1]])
        q = (ring // 24).astype(int); keys = q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]
        u, c = np.unique(keys, return_counts=True)  # převládající barva okolí (ne průměr přes hranu)
        a[y0:y1, x0:x1] = np.median(ring[keys == u[c.argmax()]], axis=0).astype(np.uint8)
    elif shape == "disc":
        m = Image.new("L", (a.shape[1], a.shape[0])); ImageDraw.Draw(m).ellipse((x0, y0, x1, y1), fill=255)
        m = np.asarray(m) > 0; px = a[m]
        q = (px // 24).astype(int); keys = q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]
        u, c = np.unique(keys, return_counts=True)
        a[m] = np.median(px[keys == u[c.argmax()]], axis=0).astype(np.uint8)


def clean_margins(a):
    """Spodní okraj papíru (pruh pod ilustrací) přebarví na barvu papíru: smaže falešné popisky a podpisy."""
    h, w, _ = a.shape
    paper = np.median(np.concatenate([a[h - 4:h].reshape(-1, 3), a[:4].reshape(-1, 3)]), axis=0)
    off = np.linalg.norm(a.astype(np.float32) - paper, axis=2) > 40
    rows, cols = off.mean(axis=1), off.mean(axis=0)
    yb = h - 1
    while yb > h * 0.8 and rows[yb] < 0.5: yb -= 1
    yt = 0
    while yt < h * 0.2 and rows[yt] < 0.5: yt += 1
    xl = 0
    while xl < w * 0.2 and cols[xl] < 0.5: xl += 1
    xr = w - 1
    while xr > w * 0.8 and cols[xr] < 0.5: xr -= 1
    # krémové nebe splývá s papírem: okraj nejvýš M px, jinak se pruh nečistí (ilustrace sahá k hraně)
    M = 45
    yb, yt, xl, xr = max(yb, h - 1 - M), min(yt, M), min(xl, M), max(xr, w - 1 - M)
    p = paper.astype(np.uint8)
    if yb < h - 2: a[yb + 2:] = p
    # boky a horní okraj beze změny (popisky jsou jen dole; krémové nebe by se tam smazalo)
    return (yt, yb, xl, xr)


src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for k, s in PICK.items():
    a = np.asarray(Image.open(f"{src}/{k}_s{s}.png").convert("RGB")).copy()
    for f in FIX.get(k, []): fill(a, *f)
    box = clean_margins(a)
    im = Image.fromarray(a); w, h = im.size; l, t = (w - 1080) // 2, (h - 1350) // 2
    im.crop((l, t, l + 1080, t + 1350)).quantize(256, method=Image.Quantize.MEDIANCUT).save(f"{out}/{k}.png", optimize=True)
    print(k, s, "ilustrace", box)
