#!/usr/bin/env python3
"""Rekvizity světa (docs/art-requests.md kap. 5), procedurálně (PIL, bez modelu), plochý vektor styl A.

- `assets/shops/<id>.png` 256² – vývěsní štít podniku shora (kruhový emblém, barva druhu z `color.shops`,
  bílý symbol, bez textu a značek): cafe, bar, pizza, souvenir, hotdog, bodega.
- `assets/props/booth.png`, `booth_ring.png` – telefonní budka shora 96×96 px (3 m, budka 2,4 m, 32 px/m),
  barvy `color.booth`; zvonící stav: rozsvícený maják a žluté vlny.
- `assets/props/metro_entrance.png` – vstup do metra shora 96×224 px (3 × 7 m), schodiště dolů, zábradlí,
  dvě kulové lampy; `assets/props/metro_line_<1–6>.png` 128² – fiktivní kolečka linek (barva + bílý
  geometrický znak, žádná písmena ani čísla, ne logo MTA).
  python3 tools/art/props_proc.py --root assets
"""
import argparse, json, math, os
from PIL import Image, ImageDraw

TOK = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "design", "tokens.json")))["color"]
OUT = (27, 27, 31, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def hx(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3],)


class C:
    """Plátno v normovaných souřadnicích 0..1 (x doprava, y dolů), SS× supersampling."""

    def __init__(self, w, h, ss=8):
        self.w, self.h, self.ss = w, h, ss
        self.im = Image.new("RGBA", (w * ss, h * ss), CLEAR)
        self.d = ImageDraw.Draw(self.im)

    def P(self, x, y):
        return (x * self.w * self.ss, y * self.h * self.ss)

    def box(self, x0, y0, x1, y1):
        return [*self.P(x0, y0), *self.P(x1, y1)]

    def ell(self, x0, y0, x1, y1, c):
        self.d.ellipse(self.box(x0, y0, x1, y1), fill=c)

    def rr(self, x0, y0, x1, y1, r, c):
        self.d.rounded_rectangle(self.box(x0, y0, x1, y1), radius=r * self.w * self.ss, fill=c)

    def poly(self, pts, c):
        self.d.polygon([self.P(x, y) for x, y in pts], fill=c)

    def line(self, pts, w, c):
        self.d.line([self.P(x, y) for x, y in pts], fill=c, width=max(1, int(w * self.w * self.ss)))
        for x, y in pts:
            r = w / 2
            self.ell(x - r, y - r * self.w / self.h, x + r, y + r * self.w / self.h, c)

    def out(self):
        return self.im.resize((self.w, self.h), Image.LANCZOS)


# ---------------------------------------------------------------- podniky
SHOPS = {"cafe": "food", "bar": "bar", "pizza": "food", "souvenir": "souvenir", "hotdog": "food", "bodega": "food"}


def emblem(kind):
    c = C(256, 256)
    col = hx(TOK["shops"][kind])
    c.ell(0.02, 0.02, 0.98, 0.98, OUT)
    c.ell(0.05, 0.05, 0.95, 0.95, WHITE)
    c.ell(0.09, 0.09, 0.91, 0.91, col)
    return c


def g_cafe(c):  # šálek s podšálkem a párou
    c.ell(0.24, 0.66, 0.76, 0.76, WHITE)
    c.rr(0.30, 0.42, 0.64, 0.70, 0.08, WHITE)
    c.ell(0.58, 0.47, 0.74, 0.63, WHITE)
    c.ell(0.62, 0.51, 0.70, 0.59, hx(TOK["shops"]["food"]))
    for x in (0.40, 0.52):
        c.line([(x, 0.36), (x - 0.03, 0.30), (x, 0.24)], 0.035, WHITE)


def g_bar(c):  # pivní půllitr s pěnou
    c.rr(0.32, 0.30, 0.62, 0.76, 0.04, WHITE)
    c.rr(0.62, 0.40, 0.72, 0.64, 0.05, WHITE)
    c.rr(0.645, 0.45, 0.695, 0.59, 0.02, hx(TOK["shops"]["bar"]))
    for x, y, r in ((0.36, 0.28, 0.06), (0.46, 0.25, 0.07), (0.56, 0.28, 0.06)):
        c.ell(x - r, y - r, x + r, y + r, WHITE)
    for x in (0.40, 0.47, 0.54):
        c.rr(x - 0.012, 0.40, x + 0.012, 0.70, 0.01, hx(TOK["shops"]["bar"]))


def g_pizza(c):  # dílek pizzy
    c.poly([(0.26, 0.30), (0.74, 0.30), (0.50, 0.80)], WHITE)
    c.rr(0.24, 0.24, 0.76, 0.34, 0.04, WHITE)
    col = hx(TOK["shops"]["food"])
    for x, y in ((0.40, 0.42), (0.58, 0.44), (0.50, 0.58)):
        c.ell(x - 0.045, y - 0.045, x + 0.045, y + 0.045, col)


def g_souvenir(c):  # sněžítko: koule na podstavci s mrakodrapem
    col = hx(TOK["shops"]["souvenir"])
    c.ell(0.28, 0.20, 0.72, 0.64, WHITE)
    c.rr(0.30, 0.62, 0.70, 0.78, 0.04, WHITE)
    c.rr(0.46, 0.34, 0.54, 0.58, 0.01, col)
    c.poly([(0.46, 0.34), (0.54, 0.34), (0.50, 0.26)], col)
    for x, y in ((0.36, 0.36), (0.62, 0.32), (0.40, 0.50), (0.63, 0.48)):
        c.ell(x - 0.015, y - 0.015, x + 0.015, y + 0.015, col)


def g_hotdog(c):  # párek v rohlíku s hořčicí
    c.rr(0.20, 0.42, 0.80, 0.64, 0.11, WHITE)
    c.rr(0.16, 0.47, 0.84, 0.57, 0.05, shade(hx(TOK["shops"]["food"]), 0.6))
    pts = [(0.24 + 0.52 * i / 12, 0.52 + 0.025 * (1 if i % 2 else -1)) for i in range(13)]
    c.line(pts, 0.022, hx("#F2BD2C"))


def g_bodega(c):  # nákupní košík
    c.poly([(0.22, 0.42), (0.78, 0.42), (0.70, 0.74), (0.30, 0.74)], WHITE)
    col = hx(TOK["shops"]["food"])
    for x in (0.38, 0.50, 0.62):
        c.rr(x - 0.018, 0.48, x + 0.018, 0.68, 0.01, col)
    c.line([(0.34, 0.42), (0.42, 0.26), (0.58, 0.26), (0.66, 0.42)], 0.035, WHITE)


GLYPH = dict(cafe=g_cafe, bar=g_bar, pizza=g_pizza, souvenir=g_souvenir, hotdog=g_hotdog, bodega=g_bodega)


# ---------------------------------------------------------------- telefonní budka
def booth(ring):
    c = C(96, 96)
    b, roof, glass, rc = hx(TOK["booth"]["body"]), hx(TOK["booth"]["roof"]), hx(TOK["booth"]["glass"]), hx(TOK["booth"]["ring"])
    m = 0.10  # budka 2,4 m na plátně 3 m
    if ring:  # vlny kolem budky (uvnitř plátna)
        for r, a, w in ((0.475, 0.55, 0.035), (0.445, 1.0, 0.035)):
            c.d.ellipse(c.box(0.5 - r, 0.5 - r, 0.5 + r, 0.5 + r), outline=rc[:3] + (int(255 * a),), width=int(w * 96 * 8))
    c.rr(m, m, 1 - m, 1 - m, 0.08, OUT)
    c.rr(m + 0.02, m + 0.02, 1 - m - 0.02, 1 - m - 0.02, 0.07, b)
    # sklo na čtyřech stranách mezi sloupky
    for (x0, y0, x1, y1) in ((0.24, m + 0.03, 0.76, m + 0.07), (0.24, 1 - m - 0.07, 0.76, 1 - m - 0.03),
                             (m + 0.03, 0.24, m + 0.07, 0.76), (1 - m - 0.07, 0.24, 1 - m - 0.03, 0.76)):
        c.rr(x0, y0, x1, y1, 0.01, glass)
    c.rr(0.22, 0.22, 0.78, 0.78, 0.06, roof)
    c.rr(0.30, 0.30, 0.70, 0.70, 0.05, shade(roof, 1.25))
    lamp = rc if ring else shade(glass, 0.85)
    c.ell(0.42, 0.42, 0.58, 0.58, OUT)
    c.ell(0.44, 0.44, 0.56, 0.56, lamp)
    if ring:
        c.ell(0.47, 0.47, 0.51, 0.51, WHITE)
    return c.out()


# ---------------------------------------------------------------- metro
def metro_entrance():
    c = C(96, 224)
    pav, stair, rail = hx("#BDB6AE"), hx("#8F8985"), hx("#2C4A3E")
    c.rr(0.06, 0.03, 0.94, 0.97, 0.06, OUT)
    c.rr(0.08, 0.04, 0.92, 0.96, 0.05, pav)
    # otvor se schody dolů (tmavnou směrem dolů = hloubka), vstup nahoře
    c.rr(0.22, 0.16, 0.78, 0.90, 0.02, hx("#3A3633"))
    n = 12
    for i in range(n):
        y0 = 0.18 + i * (0.70 / n)
        f = 1.0 - 0.5 * i / n
        c.rr(0.24, y0, 0.76, y0 + 0.70 / n - 0.008, 0.005, shade(stair, f))
    # zábradlí po stranách a vzadu
    for x in (0.18, 0.82):
        c.line([(x, 0.18), (x, 0.92)], 0.05, rail)
    c.line([(0.18, 0.92), (0.82, 0.92)], 0.05, rail)
    # dvě kulové lampy u vstupu (zelené sloupky, mléčné koule)
    for x in (0.16, 0.84):
        c.ell(x - 0.09, 0.07 - 0.04, x + 0.09, 0.07 + 0.04, OUT)
        c.ell(x - 0.075, 0.07 - 0.033, x + 0.075, 0.07 + 0.033, hx("#F4EBC8"))
    return c.out()


LINES = [("#D7263D", "dot"), ("#2F6FB0", "bar"), ("#F2A83B", "tri"), ("#2E9E5B", "square"), ("#8C5AB4", "diamond"),
         ("#5E5860", "ring")]


def metro_line(col, sym):
    c = C(128, 128)
    c.ell(0.03, 0.03, 0.97, 0.97, OUT)
    c.ell(0.06, 0.06, 0.94, 0.94, hx(col))
    if sym == "dot":
        c.ell(0.34, 0.34, 0.66, 0.66, WHITE)
    elif sym == "bar":
        c.rr(0.24, 0.42, 0.76, 0.58, 0.04, WHITE)
    elif sym == "tri":
        c.poly([(0.50, 0.26), (0.76, 0.70), (0.24, 0.70)], WHITE)
    elif sym == "square":
        c.rr(0.32, 0.32, 0.68, 0.68, 0.04, WHITE)
    elif sym == "diamond":
        c.poly([(0.50, 0.24), (0.76, 0.50), (0.50, 0.76), (0.24, 0.50)], WHITE)
    elif sym == "ring":
        c.ell(0.28, 0.28, 0.72, 0.72, WHITE)
        c.ell(0.38, 0.38, 0.62, 0.62, hx(col))
    return c.out()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="assets")
    a = ap.parse_args()
    for sub in ("shops", "props"):
        os.makedirs(os.path.join(a.root, sub), exist_ok=True)
    for sid, kind in SHOPS.items():
        c = emblem(kind)
        GLYPH[sid](c)
        c.out().save(os.path.join(a.root, "shops", f"{sid}.png"), optimize=True)
    booth(False).save(os.path.join(a.root, "props", "booth.png"), optimize=True)
    booth(True).save(os.path.join(a.root, "props", "booth_ring.png"), optimize=True)
    metro_entrance().save(os.path.join(a.root, "props", "metro_entrance.png"), optimize=True)
    for i, (col, sym) in enumerate(LINES, 1):
        metro_line(col, sym).save(os.path.join(a.root, "props", f"metro_line_{i}.png"), optimize=True)
    print("ok")


if __name__ == "__main__":
    main()
