#!/usr/bin/env python3
"""Procedurální bezešvé textury Tokio 512² (styl D shora: ploché cel tóny, bez linek). python3 proc_tex_tokyo.py OUTDIR"""
import sys, os, numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from proc_tex import N, hexc, noise, speckle, quant, save
out = sys.argv[1]
# asfalt: světle modrozelený, jemné kamínky
rng = np.random.default_rng(521)
base, hi, lo = hexc("#8FB9B9"), hexc("#A6CACA"), hexc("#7AA4A6")
n = quant(noise(rng, 4) * 0.6 + noise(rng, 16) * 0.4, 3)
img = base + (n[..., None] - 0.5) * (hi - lo) * 0.35
speckle(img, rng, 2600, [hi, lo, hexc("#B9D6D5"), hexc("#6F9799")], 1.2)
save(img, f"{out}/cities/tokyo/asphalt.png")
# chodník: 8×8 šedobéžových dlaždic, 1 sloupec žlutých hmatových dlaždic s výstupky
rng = np.random.default_rng(522)
tile, joint = N // 8, hexc("#A59D93")
tones = [hexc("#D6CFC4"), hexc("#CFC7BB"), hexc("#DAD3C9")]
img = np.zeros((N, N, 3), np.float32)
for ty in range(8):
    for tx in range(8):
        img[ty * tile:(ty + 1) * tile, tx * tile:(tx + 1) * tile] = tones[rng.integers(3)]
ycol, yshade, ydot = 3, hexc("#E8BE4A"), hexc("#D3A836")
img[:, ycol * tile:(ycol + 1) * tile] = yshade
for ty in range(8):  # výstupky 5×5 na dlaždici
    for i in range(5):
        for j in range(5):
            cy, cx = ty * tile + 6 + i * 13, ycol * tile + 6 + j * 13
            yy, xx = np.mgrid[-3:4, -3:4]; m = xx ** 2 + yy ** 2 <= 9
            img[cy + yy[m], cx + xx[m]] = ydot
            img[cy + yy[m] - 1, cx + xx[m] - 1] = np.where((xx[m] ** 2 + yy[m] ** 2 <= 2)[:, None], hexc("#F2D374"), ydot)
for k in range(8):
    img[(k * tile) % N, :] = joint; img[(k * tile + 1) % N, :] = joint
    img[:, (k * tile) % N] = joint; img[:, (k * tile + 1) % N] = joint
speckle(img, rng, 500, [hexc("#C2B9AC"), hexc("#E2DCD3")], 1.0)
save(img, f"{out}/cities/tokyo/sidewalk_tile.png")
# střecha: světle šedá plochá, švy, 2 klimatizační jednotky se stínem (shora, světlo zleva nahoře)
rng = np.random.default_rng(523)
base, hi, lo = hexc("#C9CACB"), hexc("#D6D7D8"), hexc("#B7B8BB")
n = quant(noise(rng, 5), 3)
img = base + (n[..., None] - 0.5) * (hi - lo) * 0.2
for y in (0, 256):
    img[y:y + 2, :] = hexc("#AEB0B4")
def ac(x, y):
    w, h = 86, 64
    img[y + 6:y + h + 6, x + 6:x + w + 6] = hexc("#2C334A") * 0.35 + img[y + 6:y + h + 6, x + 6:x + w + 6] * 0.65  # stín
    img[y:y + h, x:x + w] = hexc("#EEEEEC"); img[y:y + 4, x:x + w] = hexc("#FFFFFF"); img[y + h - 4:y + h, x:x + w] = hexc("#C9CBCF")
    cy, cx = y + h // 2, x + 28; yy, xx = np.mgrid[-22:23, -22:23]; r2 = xx ** 2 + yy ** 2
    img[cy + yy[r2 <= 484], cx + xx[r2 <= 484]] = hexc("#8E959E"); img[cy + yy[r2 <= 380], cx + xx[r2 <= 380]] = hexc("#565D6E")
    for a in range(0, 360, 60):  # lopatky
        t = np.radians(a); 
        for r in range(4, 18):
            img[int(cy + r * np.sin(t)), int(cx + r * np.cos(t))] = hexc("#A4A4A9")
    for gx in range(x + 58, x + 80, 5): img[y + 12:y + h - 12, gx:gx + 2] = hexc("#B4B7BC")  # mřížka
ac(70, 90); ac(330, 350)
speckle(img, rng, 700, [hexc("#B2B4B8"), hexc("#DCDDDE")], 1.0)
save(img, f"{out}/cities/tokyo/roof.png")
print("ok")
