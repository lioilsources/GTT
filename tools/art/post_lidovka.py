#!/usr/bin/env python3
"""Lidka 105: dodatečně k hotovému body.png (oprava 1, Qwen-Image) maska laku, šedý lak, výřezy pro kola,
kolo a světla podle formátu docs/art-requests.md kap. 3.

  python3 tools/art/post_lidovka.py assets/cars/lidovka/body.png assets/cars/lidovka

Krémový lak se pozná podle barvy (světlý, teplý, málo sytý), převede se na jas normovaný tak, aby
nejčastější tón laku byl 235 (hra ho násobí lakem lidka_cream). Vstup musí být původní krémový body.png.
"""
import os, sys, colorsys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import cars_proc as cp

L, W = 4.2, 1.6


def main():
    src, out = sys.argv[1], sys.argv[2]
    im = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32)
    rgb, a = im[..., :3] / 255, im[..., 3]
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    # lak: teplý (r ≥ g ≥ b), světlý, sytost do 0,45; měkký přechod na hranách
    warm = (r >= g - 0.02) & (g >= b - 0.02) & (r - b < 0.45)
    m = np.clip((lum - 0.45) / 0.15, 0, 1) * np.clip((0.50 - sat) / 0.10, 0, 1) * warm
    m *= (a > 0)
    ref = np.median(lum[m > 0.9])
    grey = np.clip(lum / ref * 235 / 255, 0, 1)
    out_rgb = rgb * (1 - m[..., None]) + grey[..., None] * m[..., None]
    H, Wd = a.shape
    body = np.dstack([out_rgb * 255, a]).clip(0, 255).astype(np.uint8)
    mask = (m * 255).astype(np.uint8)

    # výřezy pro kola (stejná geometrie jako cars_proc)
    S = 1
    hl, hw = L / 2 * 32, W / 2 * 32
    wl, ww = cp.wheel_size(L, W)
    wl, ww = wl * 32, ww * 32
    bim, mim = Image.fromarray(body), Image.fromarray(mask)
    alpha = Image.fromarray(a.astype(np.uint8))
    for u in (cp.AXLE, -cp.AXLE):
        for s in (1, -1):
            x, y = Wd / 2 + s * cp.WHEEL_V * hw, H / 2 - u * hl
            well = [x - s * (ww / 2 + 1.2), y - wl / 2 - 1.4, x + s * 4 * ww, y + wl / 2 + 1.4]
            box = [min(well[0], well[2]), well[1], max(well[0], well[2]), well[3]]
            ImageDraw.Draw(bim).rounded_rectangle(box, radius=1.5, fill=cp.WELL)
            ImageDraw.Draw(mim).rounded_rectangle(box, radius=1.5, fill=0)
            cut = [x - s * (ww / 2 - 0.8), y - wl / 2 - 0.6, x + s * 4 * ww, y + wl / 2 + 0.6]
            ImageDraw.Draw(alpha).rounded_rectangle([min(cut[0], cut[2]), cut[1], max(cut[0], cut[2]), cut[3]], radius=1, fill=0)
    al = np.minimum(np.asarray(alpha), np.asarray(bim)[..., 3])
    bim.putalpha(Image.fromarray(al))
    bim.save(os.path.join(out, "body.png"), optimize=True)
    Image.merge("LA", (mim, Image.fromarray(al))).save(os.path.join(out, "paint_mask.png"), optimize=True)
    cp.draw_wheel(L, W).save(os.path.join(out, "wheel.png"), optimize=True)

    # světla: tam, kde jsou v body.png světlomety (světlé, předních 8 %) a koncová světla (červená, zadních 8 %)
    li = np.zeros((H, Wd, 4), np.uint8)
    rear = np.zeros_like(a, bool); rear[int(H * 0.82):] = True
    red = (r > g + 0.20) & (r > 0.35) & rear & (a > 0)
    li[red] = (255, 40, 40, 255)
    # světlomety v body.png nejsou odlišené: dva ploché ovály v předních rozích
    lim = Image.fromarray(li)
    for cx in (0.24, 0.76):
        ImageDraw.Draw(lim).rounded_rectangle([Wd * cx - 5, 9.5, Wd * cx + 5, 13], radius=1.5, fill=(255, 246, 214, 255))
    li = np.asarray(lim).copy()
    li[..., 3] = np.minimum(li[..., 3], al)
    Image.fromarray(li).save(os.path.join(out, "lights.png"), optimize=True)
    print("lak ref", round(float(ref), 3), "pixely laku", int((m > 0.5).sum()), "zadní", int(red.sum()))


if __name__ == "__main__":
    main()
