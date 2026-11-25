#!/usr/bin/env python3
"""Textury počasí (docs/art-requests.md kap. 5, specs/weather.md), procedurálně (numpy, bez modelu).
Bílé / světlé na alfě, klient je tónuje barvami `color.weather` (rain, fog) a míchá s krytím podle tuningu.

- `rain_drops.png` 512² bezešvá: šikmé tahy kapek (úhel jako `weather.rain_angle_deg` ≈ 12°), různá délka a jas.
- `puddles.png` 512² bezešvá: kaluže shora (ploché skvrny s jasnějším okrajem), na vozovku za deště.
- `wet_sheen.png` 512² bezešvá: odlesk mokré silnice, podélné rozmazané pruhy (pro budoucí odlesky, v1 nejsou).
- `fog.png` 1024² (není dlaždice): radiální maska mlhy, krytí od středu k okraji (smoothstep), tvar jako ve spec.
  python3 tools/art/weather_tex.py OUTDIR
"""
import os, sys, numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from proc_tex import N, noise


def save_la(alpha, path, lum=255):
    a = np.clip(alpha, 0, 255).astype(np.uint8)
    im = Image.merge("LA", (Image.new("L", a.shape[::-1], lum), Image.fromarray(a)))
    im.save(path, optimize=True)


def rain(out):
    rng = np.random.default_rng(541)
    S = 4
    im = Image.new("L", (N * S, N * S), 0)
    d = ImageDraw.Draw(im)
    ang = np.radians(12)
    for _ in range(420):
        x, y = rng.uniform(0, N), rng.uniform(0, N)
        L = rng.uniform(14, 34)
        a = int(rng.uniform(90, 230))
        w = rng.choice([1, 1, 2]) * S
        dx, dy = -np.sin(ang) * L, np.cos(ang) * L
        for ox in (-N, 0, N):  # obtočení přes hrany = bezešvé
            for oy in (-N, 0, N):
                d.line([((x + ox) * S, (y + oy) * S), ((x + ox + dx) * S, (y + oy + dy) * S)], fill=a, width=w)
    save_la(np.asarray(im.resize((N, N), Image.LANCZOS)).astype(np.float32), os.path.join(out, "rain_drops.png"))


def puddles(out):
    rng = np.random.default_rng(542)
    n = noise(rng, 6) * 0.65 + noise(rng, 18) * 0.35
    body = (n > 0.62).astype(np.float32)
    im = Image.fromarray((body * 255).astype(np.uint8))
    tile = Image.new("L", (N * 3, N * 3))
    for i in range(3):
        for j in range(3):
            tile.paste(im, (i * N, j * N))
    tile = tile.filter(ImageFilter.ModeFilter(7))  # bez drobných teček, filtrováno na dlaždici 3×3 = bezešvé
    soft = tile.filter(ImageFilter.GaussianBlur(2)).crop((N, N, 2 * N, 2 * N))
    edge = tile.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3)).crop((N, N, 2 * N, 2 * N))
    a = np.asarray(soft).astype(np.float32) * 0.22 + np.asarray(edge).astype(np.float32) * 0.30
    save_la(a, os.path.join(out, "puddles.png"), lum=235)


def sheen(out):
    rng = np.random.default_rng(543)
    g = rng.random((8, 64))  # podélné pruhy: nízká frekvence napříč, vyšší podél
    big = Image.fromarray((g * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
    tile = Image.new("L", (N * 3, N * 3))
    for i in range(3):
        for j in range(3):
            tile.paste(big, (i * N, j * N))
    t = np.asarray(tile.filter(ImageFilter.GaussianBlur((2, 18))).crop((N, N, 2 * N, 2 * N))).astype(np.float32) / 255
    a = np.clip((t - 0.55) / 0.45, 0, 1) ** 1.5 * 150
    save_la(a, os.path.join(out, "wet_sheen.png"))


def fog(out, M=1024, inner=0.35, center=0.10, edge=0.85):
    y, x = np.mgrid[0:M, 0:M].astype(np.float32)
    r = np.hypot(x - M / 2 + 0.5, y - M / 2 + 0.5) / (M / 2 * np.sqrt(2))
    t = np.clip((r - inner) / (1 - inner), 0, 1)
    t = t * t * (3 - 2 * t)
    save_la((center + (edge - center) * t) * 255, os.path.join(out, "fog.png"))


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    rain(out); puddles(out); sheen(out); fog(out)
    print("ok")
