#!/usr/bin/env python3
"""Procedurální bezešvé textury NYC 512² (styl A: ploché tóny, jemný šum). python3 proc_tex.py OUTDIR"""
import sys, os, numpy as np
from PIL import Image
N = 512
def hexc(h): return np.array([int(h[i:i+2], 16) for i in (1, 3, 5)], np.float32)
def noise(rng, cells):  # periodický hodnotový šum (bilineárně, tileable)
    g = rng.random((cells, cells)); x = np.arange(N) * cells / N
    i0 = np.floor(x).astype(int); f = x - i0; f = f * f * (3 - 2 * f); i1 = (i0 + 1) % cells
    a = g[i0][:, i0] * (1 - f)[None] + g[i0][:, i1] * f[None]
    b = g[i1][:, i0] * (1 - f)[None] + g[i1][:, i1] * f[None]
    return a * (1 - f)[:, None] + b * f[:, None]
def speckle(img, rng, n, cols, rmax):
    R = int(np.ceil(rmax)); yy, xx = np.mgrid[-R:R + 1, -R:R + 1]
    for _ in range(n):
        cx, cy, r = rng.integers(N), rng.integers(N), rng.uniform(0.6, rmax)
        c = cols[rng.integers(len(cols))]; m = (xx ** 2 + yy ** 2) <= r * r
        img[(cy + yy[m]) % N, (cx + xx[m]) % N] = c
def quant(img, levels):  # ploché tóny: posterizace jasu šumu
    return np.floor(img * levels) / levels
def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).quantize(256, method=Image.Quantize.MEDIANCUT).save(path, optimize=True)
out = sys.argv[1]
# chodník: 4×4 desky (~1,5 m), spáry, pár vlasových prasklin, jemné tečky
rng = np.random.default_rng(511)
base, light, dark, joint = hexc("#DEC3B4"), hexc("#E6D0C3"), hexc("#CDB2A3"), hexc("#B39A8C")
n = quant(noise(rng, 4) * 0.6 + noise(rng, 16) * 0.4, 3)
img = base + (n[..., None] - 0.5) * (light - dark) * 0.45
slab = N // 4
for k in range(4):  # spáry 3 px, periodicky na hraně
    for o in (-1, 0, 1):
        img[(k * slab + o) % N, :] = joint; img[:, (k * slab + o) % N] = joint
for _ in range(5):  # praskliny: náhodná procházka v rámci jedné desky
    sx, sy = rng.integers(4) * slab, rng.integers(4) * slab
    x, y = sx + rng.integers(20, slab - 20), sy + rng.integers(20, slab - 20); ang = rng.uniform(0, 2 * np.pi)
    for _ in range(rng.integers(40, 90)):
        ang += rng.normal(0, 0.35); x += np.cos(ang); y += np.sin(ang)
        if not (sx + 4 < x < sx + slab - 4 and sy + 4 < y < sy + slab - 4): break
        img[int(y), int(x)] = joint
speckle(img, rng, 900, [dark, light, hexc("#C4A999")], 1.3)
save(img, f"{out}/cities/nyc/sidewalk_concrete.png")
# střecha: tmavý štěrk, dehtové záplaty, švy membrány
rng = np.random.default_rng(512)
base, hi, lo, seam = hexc("#5E5B60"), hexc("#888386"), hexc("#46424A"), hexc("#3C383F")
n = quant(noise(rng, 6), 3)
img = base + (n[..., None] - 0.5) * (hi - lo) * 0.25
p = noise(rng, 3) > 0.68; img[p] = img[p] * 0.93 + lo * 0.07   # záplaty
for y in (128, 384):
    img[y - 1:y + 2, :] = seam
for x in (64, 320):
    img[:128, x - 1:x + 2] = seam; img[384:, x - 1:x + 2] = seam
speckle(img, rng, 3500, [hi, lo, hexc("#98969B"), hexc("#6E6570")], 1.6)
save(img, f"{out}/cities/nyc/roof_tar.png")
print("ok")
