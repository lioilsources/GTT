#!/usr/bin/env python3
"""Procedurální bezešvé textury Moskva 512² (styl E shora: ploché tvrdé tóny, bez přechodů, paleta color.city.moscow).
  python3 proc_tex_moscow.py OUTDIR"""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from proc_tex import N, hexc, noise, speckle, quant, save
out = sys.argv[1]

# asfalt: teplá tmavě šedá (#4A4542), dva ploché tóny skvrn, ostré kamínky
rng = np.random.default_rng(531)
base, hi, lo = hexc("#4A4542"), hexc("#4F4946"), hexc("#46413F")
n = quant(noise(rng, 8) * 0.5 + noise(rng, 16) * 0.5, 3)
img = np.where((n > 0.66)[..., None], hi, np.where((n < 0.34)[..., None], lo, base)).astype(np.float32)
speckle(img, rng, 2200, [hexc("#6A625C"), hexc("#3A3533"), hexc("#7A6F66")], 1.1)
save(img, f"{out}/cities/moscow/asphalt.png")

# chodník: velké žulové desky (#D9CBA8) na vazbu, 4 řady × 2 desky, tmavé spáry, ploché tóny desek
rng = np.random.default_rng(532)
rows, cols = 4, 2
th, tw = N // rows, N // cols
tones = [hexc("#D9CBA8"), hexc("#D2C3A0"), hexc("#DFD2B2"), hexc("#CDBE9A")]
joint = hexc("#8C8170")
img = np.zeros((N, N, 3), np.float32)
for r in range(rows):
    off = (tw // 2) * (r % 2)
    for c in range(cols + 1):
        x0 = c * tw - off
        col = tones[rng.integers(len(tones))]
        xs = np.arange(x0, x0 + tw) % N
        img[r * th:(r + 1) * th][:, xs] = col
    img[r * th:r * th + 3, :] = joint
    for c in range(cols + 1):
        x = (c * tw - off) % N
        img[r * th:(r + 1) * th, x:x + 3] = joint
speckle(img, rng, 900, [hexc("#B8A988"), hexc("#E8DEC6"), hexc("#7A6F66")], 1.0)
save(img, f"{out}/cities/moscow/sidewalk.png")

# střecha: krémové asfaltové pásy (#DCCFB2) se švy, dvě černé čtvercové větrací hlavice s tvrdým stínem
rng = np.random.default_rng(533)
base, alt = hexc("#DCCFB2"), hexc("#D3C5A6")
img = np.zeros((N, N, 3), np.float32)
band = N // 4
for k in range(4):
    img[k * band:(k + 1) * band] = base if k % 2 == 0 else alt
    img[k * band:k * band + 3] = hexc("#B9AA8A")
shadow = hexc("#1D1A1A")


def vent(x, y, s=46):
    d = 10  # stín doprava dolů (světlo zleva nahoře), tvrdý, 55 % krytí
    ys, xs = np.arange(y + d, y + s + d) % N, np.arange(x + d, x + s + d) % N
    img[np.ix_(ys, xs)] = img[np.ix_(ys, xs)] * 0.45 + shadow * 0.55
    ys, xs = np.arange(y, y + s) % N, np.arange(x, x + s) % N
    img[np.ix_(ys, xs)] = hexc("#3A3533")
    ys, xs = np.arange(y + 10, y + s - 10) % N, np.arange(x + 10, x + s - 10) % N
    img[np.ix_(ys, xs)] = shadow


vent(96, 70)
vent(350, 330)
speckle(img, rng, 600, [hexc("#C9BB9A"), hexc("#E8DDC4")], 1.0)
save(img, f"{out}/cities/moscow/roof.png")
print("ok")
