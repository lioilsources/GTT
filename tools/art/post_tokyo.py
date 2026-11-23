#!/usr/bin/env python3
"""GTT Tokio pohlednice (finální sada, landmarks.yaml): výběr seedů z várek tokyo2 (s21x), tokyo3 (s22x),
tokyo4 (s23x), ploché přebarvení zbylých falešných nápisů (štíty, cedulky; na lampionech jen tmavé tahy), ořez 1080×1350, 256 barev.
  python3 post_tokyo.py ROOT OUT   (ROOT obsahuje tokyoN/postcards/tokyo/*.png)"""
import sys, os, numpy as np
from PIL import Image, ImageDraw, ImageFilter
PICK = {"akihabara": 222, "ginza_clock": 223, "hamarikyu": 223, "kabukiza": 223, "kaminarimon": 221,
        "kokugikan": 223, "nihonbashi": 221, "nijubashi": 223, "roppongi_hills": 221, "skytree": 223,
        "sumida_river": 223, "tokyo_dome": 223, "tokyo_national_museum": 222, "tokyo_station": 222,
        "tokyo_tower": 223, "zojoji": 223,
        "akasaka_palace": 232, "ameyoko": 233, "budokan": 232, "hie_shrine": 232, "kachidoki_bridge": 232,
        "kanda_myojin": 233, "nakamise": 232, "national_diet": 233, "tsukiji_outer": 233}
# (x0, y0, x1, y1, tvar) v souřadnicích 1088×1360; barva = medián okolí (obdélník) / světlé části (elipsa)
FIX = {
    "kaminarimon": [(482, 369, 697, 435, "rect")],
    "akasaka_palace": [(478, 456, 638, 486, "rect")],
    "budokan": [(510, 696, 654, 750, "rect"), (840, 1086, 900, 1130, "rect")],
    "national_diet": [(460, 364, 630, 384, "rect")],
    "kachidoki_bridge": [(880, 1326, 1060, 1356, "rect")],
    "kanda_myojin": [(535, 528, 573, 588, "rect")],
    "nakamise": [(542, 736, 613, 818, "lantern_red"), (912, 708, 968, 794, "lantern")],
    "tsukiji_outer": [(245, 594, 301, 623, "flat")],
}
def fill(a, x0, y0, x1, y1, shape):
    if shape == "rect":
        ring = np.concatenate([a[y0:y1, max(x0 - 3, 0)], a[y0:y1, min(x1 + 2, a.shape[1] - 1)],
                               a[max(y0 - 3, 0), x0:x1], a[min(y1 + 2, a.shape[0] - 1), x0:x1]])
        a[y0:y1, x0:x1] = np.median(ring, axis=0).astype(np.uint8)
    elif shape == "flat":
        a[y0:y1, x0:x1] = np.median(a[y0:y1, x0:x1].reshape(-1, 3), axis=0).astype(np.uint8)
    elif shape.startswith("glyph"):  # tmavé tahy znaků -> medián světlejší plochy (tělo lampionu)
        r = a[y0:y1, x0:x1]; lum = r @ [0.299, 0.587, 0.114]; thr = int(shape[5:])
        dark = np.asarray(Image.fromarray(((lum < thr) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
        r[dark] = np.median(r[lum >= thr], axis=0).astype(np.uint8); a[y0:y1, x0:x1] = r
    elif shape.startswith("lantern"):  # elipsa těla lampionu: vše odlišné od převládající barvy (znaky i jejich lem) -> ta barva
        m = Image.new("L", (a.shape[1], a.shape[0])); ImageDraw.Draw(m).ellipse((x0, y0, x1, y1), fill=255)
        m = np.asarray(m) > 0; px = a[m].astype(np.float32)
        q = (px // 24).astype(int); keys, cnt = np.unique(q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2], return_counts=True)
        dom = keys[cnt.argmax()]; sel = (q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]) == dom
        if shape == "lantern_red":  # červený lampion s velkými černými znaky: barva = medián červených pixelů
            sel = (px[:, 0] - px[:, 1] > 60) & (px[:, 0] > 120)
        med = np.median(px[sel], axis=0); off = np.linalg.norm(px - med, axis=1) > 50
        mm = np.zeros(m.shape, bool); mm[m] = off
        mm = (np.asarray(Image.fromarray((mm * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0) & m
        a[mm] = med.astype(np.uint8)
    else:
        m = Image.new("L", (a.shape[1], a.shape[0])); ImageDraw.Draw(m).ellipse((x0, y0, x1, y1), fill=255)
        m = np.asarray(m) > 0; px = a[m]; lum = px @ [0.299, 0.587, 0.114]
        a[m] = np.median(px[lum >= np.percentile(lum, 50)], axis=0).astype(np.uint8)
root, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for k, s in PICK.items():
    batch = {21: "tokyo2", 22: "tokyo3", 23: "tokyo4"}[s // 10]
    a = np.asarray(Image.open(f"{root}/{batch}/postcards/tokyo/{k}_s{s}.png").convert("RGB")).copy()
    for f in FIX.get(k, []): fill(a, *f)
    im = Image.fromarray(a); w, h = im.size; l, t = (w - 1080) // 2, (h - 1350) // 2
    im.crop((l, t, l + 1080, t + 1350)).quantize(256, method=Image.Quantize.MEDIANCUT).save(f"{out}/{k}.png", optimize=True)
print(len(PICK))
