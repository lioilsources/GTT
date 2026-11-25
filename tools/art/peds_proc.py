#!/usr/bin/env python3
"""Chodci shora (docs/art-requests.md kap. 4, specs/pedestrians.md „Kreslení“), procedurálně (PIL, bez modelu).

Jedna sada pro všechna města (shora je postava ~20 px, rozdíly měst by nebyly vidět; barvu trička dosazuje hra).
Na chodce: `ped_<n>.png` pás 3 snímků vedle sebe (chůze A, chůze B, uskočení), každý 24×24 px (32 px/m,
0,75 m), předek (směr chůze) nahoru, bez stínu. `ped_<n>_mask.png` stejný pás, bílá = tričko (hra ho násobí
barvou z `color.pedestrians.shirts`), tričko je v `ped_<n>.png` světle šedé.
  python3 tools/art/peds_proc.py --out assets/peds
"""
import argparse, os
from PIL import Image, ImageDraw

PX_M, SS, F = 32, 16, 24          # px/m, supersampling, strana snímku
OUT = (27, 27, 31, 255)
SHIRT = (226, 226, 226, 255)       # světlá šedá, hra tónuje
SHIRT_D = (196, 196, 198, 255)     # stín rukávu
SKIN = [(236, 196, 164, 255), (198, 146, 108, 255), (141, 96, 66, 255), (96, 64, 46, 255)]
PANTS = (52, 58, 74, 255)
SHOE = (34, 34, 38, 255)

# vlasy / pokrývka, barva, kůže, doplněk
PEDS = {
    1: dict(hair="short", hc=(44, 34, 30, 255), skin=1, acc="backpack"),
    2: dict(hair="long", hc=(222, 186, 112, 255), skin=0, acc="shoulderbag"),
    3: dict(hair="bun", hc=(74, 50, 36, 255), skin=2, acc=None),
    4: dict(hair="cap", hc=(36, 70, 132, 255), skin=0, acc=None),
    5: dict(hair="short", hc=(170, 170, 172, 255), skin=1, acc="shoulderbag"),
    6: dict(hair="curly", hc=(28, 24, 24, 255), skin=3, acc="backpack"),
    7: dict(hair="ponytail", hc=(168, 74, 40, 255), skin=0, acc=None),
    8: dict(hair="hat", hc=(206, 184, 140, 255), skin=2, acc=None),
}


class P:
    def __init__(self):
        self.n = F * SS
        self.im = Image.new("RGBA", (self.n, self.n), (0, 0, 0, 0))
        self.mk = Image.new("L", (self.n, self.n), 0)
        self.d, self.dm = ImageDraw.Draw(self.im), ImageDraw.Draw(self.mk)

    def xy(self, x, y):  # metry, střed snímku, y dopředu (nahoru)
        return (self.n / 2 + x * PX_M * SS, self.n / 2 - y * PX_M * SS)

    def ell(self, x, y, rx, ry, col, mask=False, ol=True):
        x0, y0 = self.xy(x - rx, y + ry)
        x1, y1 = self.xy(x + rx, y - ry)
        if ol:
            o = 0.016 * PX_M * SS
            self.d.ellipse([x0 - o, y0 - o, x1 + o, y1 + o], fill=OUT)
        self.d.ellipse([x0, y0, x1, y1], fill=col)
        self.dm.ellipse([x0, y0, x1, y1], fill=255 if mask else 0)

    def out(self):
        return self.im.resize((F, F), Image.LANCZOS), self.mk.resize((F, F), Image.LANCZOS)


def head(p, spec):
    h, hc, sk = spec["hair"], spec["hc"], SKIN[spec["skin"]]
    hx, hy, r = 0.0, 0.02, 0.095
    if h == "long":  # vlasy přes záda
        p.ell(0, -0.07, 0.12, 0.13, hc)
    if h == "ponytail":
        p.ell(0, -0.15, 0.045, 0.08, hc)
    if h == "hat":   # široká krempa
        p.ell(hx, hy, 0.165, 0.165, hc)
        p.ell(hx, hy, 0.11, 0.11, tuple(max(0, c - 30) for c in hc[:3]) + (255,))
        return
    if h == "cap":
        p.ell(hx, hy + 0.10, 0.075, 0.06, hc)  # kšilt dopředu
    p.ell(hx, hy, r, r, sk)
    cover = {"short": 0.95, "long": 0.98, "bun": 0.95, "cap": 1.0, "curly": 1.25, "ponytail": 0.95}[h]
    p.ell(hx, hy - 0.012, r * cover, r * cover * 0.92, hc)
    if h == "bun":
        p.ell(0, -0.06, 0.05, 0.05, hc)
    if h == "cap":
        p.ell(0, 0.0, 0.03, 0.03, tuple(min(255, c + 40) for c in hc[:3]) + (255,), ol=False)


def frame(spec, k):
    p = P()
    sk = SKIN[spec["skin"]]
    dodge = k == 2
    s = 1 if k == 0 else -1  # krok: levá/pravá noha vpřed
    if dodge:
        # uskočení: nohy rozkročené do strany, paže zdvižené a roztažené
        for sx in (-1, 1):
            p.ell(sx * 0.15, -0.02, 0.04, 0.065, SHOE)
        for sx in (-1, 1):
            p.ell(sx * 0.27, 0.09, 0.085, 0.038, SHIRT, mask=True)
            p.ell(sx * 0.35, 0.13, 0.03, 0.03, sk, ol=False)
    else:
        # boty: jedna vpředu, druhá vzadu
        p.ell(0.07 * s, 0.16, 0.04, 0.065, SHOE)
        p.ell(-0.07 * s, -0.15, 0.04, 0.06, SHOE)
        # paže kmitají proti nohám
        for sx in (-1, 1):
            off = -s * sx * 0.07
            p.ell(sx * 0.215, off, 0.04, 0.085, SHIRT_D, mask=True)
            p.ell(sx * 0.215, off + (0.09 if off > 0 else -0.09), 0.028, 0.028, sk, ol=False)
    if spec["acc"] == "backpack":
        p.ell(0, -0.12, 0.13, 0.07, (70, 74, 84, 255))
    # ramena (kapsle napříč)
    p.ell(0, 0, 0.21, 0.105, SHIRT, mask=True)
    if spec["acc"] == "shoulderbag":
        p.ell(0.20, -0.08, 0.05, 0.07, (120, 82, 52, 255))
        x0, y0 = p.xy(-0.18, 0.08)
        x1, y1 = p.xy(0.20, -0.06)
        p.d.line([x0, y0, x1, y1], fill=(90, 62, 40, 255), width=int(0.03 * PX_M * SS))
        p.dm.line([x0, y0, x1, y1], fill=0, width=int(0.03 * PX_M * SS))
    head(p, spec)
    return p.out()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for n, spec in PEDS.items():
        strip = Image.new("RGBA", (3 * F, F), (0, 0, 0, 0))
        mstrip = Image.new("L", (3 * F, F), 0)
        for k in range(3):
            im, m = frame(spec, k)
            strip.paste(im, (k * F, 0))
            mstrip.paste(m, (k * F, 0))
        strip.save(os.path.join(a.out, f"ped_{n}.png"), optimize=True)
        Image.merge("LA", (mstrip, strip.getchannel("A"))).save(os.path.join(a.out, f"ped_{n}_mask.png"), optimize=True)
        print(f"ped_{n}", strip.size)


if __name__ == "__main__":
    main()
