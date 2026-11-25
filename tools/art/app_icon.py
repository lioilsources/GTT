#!/usr/bin/env python3
"""Ikona aplikace Metropole (dávka gtt-icon), procedurálně (PIL, bez modelu).

Sada barevných módů se stejnou kompozicí (hráč si ve hře vybere, výchozí sunset).
Motiv: hráčovo auto Varga Comet (m0_coupe, lak comet_red) shora na stylizované křižovatce, nad ní silueta
panoramatu velkoměsta (fiktivní, bez skutečných budov a nápisů). 1024², plně neprůhledná.
Vrstvy pro adaptivní ikonu Androidu: pozadí (*_bg, neprůhledné) a popředí (*_fg, auto se stínem na alfě,
uvnitř bezpečné zóny 66/108). Ikona = pozadí + popředí.
  python3 tools/art/app_icon.py --out assets/ui/app_icon [mód ...]      (DIR/<mód>{,_fg,_bg}.png)
"""
import argparse, json, math, os, random
from PIL import Image, ImageDraw, ImageChops

import cars_proc as cp

N = 1024
SS = 2
TOK = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "design", "tokens.json")))["color"]
RED = TOK["carPaint"]["comet_red"]


def hx(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


VARIANTS = {
    # barevné módy se stejnou kompozicí (auto rovně zespodu nahoru); sunset = výchozí
    # sky, skyline, okna, země, asfalt, čára, zebra, slunce (barva, střed x, střed y nad horizontem, poloměr) v px 1024
    "day":    dict(sky="#F2BD2C", city="#193B62", win=None, land="#E9DCCB", road="#5E5860", line="#F5EBDA",
                   zebra="#F5EBDA", sun=None),
    "night":  dict(sky="#193B62", city="#0F2440", win="#F2BD2C", land="#2E465D", road="#3A3F4A", line="#F2BD2C",
                   zebra="#E8E4DA", sun=None),
    "sunset": dict(sky="#F08A4B", city="#2A1E2E", win="#F2BD2C", land="#43384A", road="#2A2530", line="#F2BD2C",
                   zebra="#F5EBDA", sun=("#FFD166", 0.70, 250, 120)),
    "teal":   dict(sky="#1E8C8A", city="#0E3D3C", win=None, land="#E9DCCB", road="#2E465D", line="#F2BD2C",
                   zebra="#F5EBDA", sun=None),
    # japan: krémový papír, velké rumělkové slunce mimo střed za panoramatem (zapadající slunce, ne vlajka)
    "japan":  dict(sky="#F3E6D0", city="#2B2A3A", win=None, land="#E9DCCB", road="#3A3A44", line="#F5EBDA",
                   zebra="#F5EBDA", sun=("#E0452B", 0.66, 250, 175)),
}
HORIZON = 0.36  # podíl výšky: nebe nad, křižovatka pod
CY = 0.56       # střed křižovatky a auta (blízko středu kvůli bezpečné zóně adaptivní ikony)


def skyline(d, rnd, col, win, base_y):
    """Fiktivní panorama: obdélníky různých výšek, některé stupňovité nebo s jehlou, okna jako tečky."""
    x = -20
    while x < N * SS + 20:
        w = rnd.randint(46, 120) * SS
        h = rnd.randint(90, 300) * SS
        top = base_y - h
        d.rectangle([x, top, x + w, base_y], fill=col)
        r = rnd.random()
        if r < 0.25:  # stupňovitá koruna
            d.rectangle([x + w * 0.2, top - 30 * SS, x + w * 0.8, top], fill=col)
            d.rectangle([x + w * 0.38, top - 56 * SS, x + w * 0.62, top - 30 * SS], fill=col)
        elif r < 0.40:  # jehla
            d.rectangle([x + w * 0.46, top - 70 * SS, x + w * 0.54, top], fill=col)
        if win:
            for yy in range(int(top + 18 * SS), int(base_y - 10 * SS), 26 * SS):
                for xx in range(int(x + 10 * SS), int(x + w - 10 * SS), 22 * SS):
                    if rnd.random() < 0.45:
                        d.rectangle([xx, yy, xx + 8 * SS, yy + 10 * SS], fill=win)
        x += w + rnd.randint(-10, 6) * SS


def background(v):
    rnd = random.Random(707)
    im = Image.new("RGBA", (N * SS, N * SS), hx(v["sky"]))
    d = ImageDraw.Draw(im)
    hy = int(N * SS * HORIZON)
    if v["sun"]:
        col, sx, sy, r = v["sun"]
        r *= SS
        d.ellipse([N * SS * sx - r, hy - sy * SS - r, N * SS * sx + r, hy - sy * SS + r], fill=hx(col))
    skyline(d, rnd, hx(v["city"]), hx(v["win"]) if v["win"] else None, hy + 4 * SS)
    # země a křižovatka (shora): svislá a vodorovná silnice, střed křižovatky v (0,5, 0,70)
    d.rectangle([0, hy, N * SS, N * SS], fill=hx(v["land"]))
    cx, cy, rw = N * SS * 0.5, N * SS * CY, 300 * SS
    d.rectangle([cx - rw / 2, hy, cx + rw / 2, N * SS], fill=hx(v["road"]))
    d.rectangle([0, cy - rw / 2 + 20 * SS, N * SS, cy + rw / 2 - 20 * SS], fill=hx(v["road"]))
    # přechody (zebry) na všech čtyřech ramenech
    zl, zw, zg = 46 * SS, 22 * SS, 18 * SS
    hw = rw / 2
    for k in range(-3, 4):
        x = cx + k * (zw + zg) - zw / 2
        for y0 in (cy - hw + 20 * SS - zl - 14 * SS, cy + hw - 20 * SS + 14 * SS):
            d.rectangle([x, y0, x + zw, y0 + zl], fill=hx(v["zebra"]))
        y = cy + k * (zw + zg) * 0.85 - zw / 2
        for x0 in (cx - hw - zl - 14 * SS, cx + hw + 14 * SS):
            if abs(y - cy) < hw - 30 * SS:
                d.rectangle([x0, y, x0 + zl, y + zw * 0.85], fill=hx(v["zebra"]))
    # středové čáry mimo křižovatku
    lw = 10 * SS
    if cy - hw - zl - 30 * SS > hy:
        d.rectangle([cx - lw / 2, hy, cx + lw / 2, cy - hw - zl - 30 * SS], fill=hx(v["line"]))
    d.rectangle([cx - lw / 2, cy + hw + zl + 30 * SS, cx + lw / 2, N * SS], fill=hx(v["line"]))
    for x0, x1 in ((0, cx - hw - zl - 30 * SS), (cx + hw + zl + 30 * SS, N * SS)):
        d.rectangle([x0, cy - lw / 2, x1, cy + lw / 2], fill=hx(v["line"]))
    return im.resize((N, N), Image.LANCZOS)


def car_sprite(px_m=92):
    """Varga Comet shora v daném měřítku: karoserie s lakem comet_red, kola pod ní."""
    cp.PX_M = px_m
    spec = cp.CARS["m0_coupe"]
    res = cp.draw_car("m0_coupe", spec)
    body = res["body"].convert("RGBA")
    mask = res["paint_mask"].getchannel("L")
    tint = ImageChops.multiply(body.convert("RGB"), Image.new("RGB", body.size, hx(RED)[:3]))
    car = Image.composite(tint, body.convert("RGB"), mask).convert("RGBA")
    car.putalpha(body.getchannel("A"))
    wheel = cp.draw_wheel(spec["L"], spec["W"])
    out = Image.new("RGBA", body.size, (0, 0, 0, 0))
    hl, hw = spec["L"] / 2 * px_m, spec["W"] / 2 * px_m
    for a in (cp.AXLE, -cp.AXLE):
        for s in (1, -1):
            ww = wheel if s > 0 else wheel.transpose(Image.FLIP_LEFT_RIGHT)
            x = body.width / 2 + s * cp.WHEEL_V * hw - ww.width / 2
            y = body.height / 2 - a * hl - ww.height / 2
            out.alpha_composite(ww, (round(x), round(y)))
    out.alpha_composite(car)
    return out


def foreground(v, car):
    rc = car  # auto vždy rovně zespodu nahoru (předek nahoru)
    fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    cx, cy = N // 2, int(N * CY)
    # plochý tvrdý stín vpravo dole
    sh = Image.new("RGBA", rc.size, (12, 14, 24, 0))
    sh.putalpha(rc.getchannel("A").point(lambda a: a * 0.45))
    fg.alpha_composite(sh, (cx - rc.width // 2 + 16, cy - rc.height // 2 + 22))
    fg.alpha_composite(rc, (cx - rc.width // 2, cy - rc.height // 2))
    return fg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("variants", nargs="*")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    car = car_sprite()
    for name in a.variants or VARIANTS:
        v = VARIANTS[name]
        bg, fg = background(v), foreground(v, car)
        ic = bg.copy()
        ic.alpha_composite(fg)
        ic.convert("RGB").save(os.path.join(a.out, f"{name}.png"), optimize=True)
        bg.convert("RGB").save(os.path.join(a.out, f"{name}_bg.png"), optimize=True)
        fg.save(os.path.join(a.out, f"{name}_fg.png"), optimize=True)
        # kontrola bezpečné zóny adaptivní ikony (66/108 průměru)
        al = fg.getchannel("A").load()
        r = max(math.hypot(x - N / 2, y - N / 2) for y in range(0, N, 2) for x in range(0, N, 2) if al[x, y] > 8)
        print(name, "max r popředí", round(r), "limit", round(N * 66 / 108 / 2))


if __name__ == "__main__":
    main()
