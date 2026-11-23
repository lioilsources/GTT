#!/usr/bin/env python3
"""Kosmetika garáže (docs/art-requests.md kap. 5, specs/garage.md): polepy a kola, procedurálně (PIL).

Polepy `decals/<id>.png` 512×1024, předek nahoru, bílý motiv na alfě; klient je roztáhne na plátno
karoserie (= rozměry auta × 1,1, auto je uprostřed) a ořízne `paint_mask`. Motivy snesou roztažení
v poměru délka/šířka 2,2–3,5 (žádné kruhy). Kola `wheels/<id>.png` 128×128 kolmo shora jako
`wheel.png` (tmavá pneumatika, světlý disk), klient je škáluje na velikost kola auta a tónuje.
  python3 tools/art/garage_cosmetics.py [--out assets/garage]
"""
import argparse, math, os, random
from PIL import Image, ImageDraw, ImageFilter

DW, DH, SS = 512, 1024, 2
CLEAR, WHITE = (0, 0, 0, 0), (255, 255, 255, 255)
BODY = 1 / 1.1  # karoserie na plátně
ASP = 2.6  # typický poměr délka/šířka auta: tvary jsou „čtvercové“ v metrech pro něj


class D:
    def __init__(self):
        self.w, self.h = DW * SS, DH * SS
        self.im = Image.new("RGBA", (self.w, self.h), CLEAR)
        self.d = ImageDraw.Draw(self.im)

    def p(self, u, v):
        """u podél auta (+1 příď nahoře), v napříč (+1 vpravo), ±1 = obrys karoserie."""
        return (self.w / 2 + v * self.w / 2 * BODY, self.h / 2 - u * self.h / 2 * BODY)

    def poly(self, pts, c=WHITE):
        self.d.polygon([self.p(u, v) for u, v in pts], fill=c)

    def rect(self, u0, v0, u1, v1, c=WHITE):
        self.poly([(u0, v0), (u0, v1), (u1, v1), (u1, v0)], c)

    def out(self):
        return self.im.resize((DW, DH), Image.LANCZOS)


def mirror(pts):
    return [(u, -v) for u, v in pts]


def stripes(g):  # jako kód: ±0,22 hw, polovina šířky 0,07 hw, přes celé auto
    for s in (1, -1):
        g.rect(-1.02, s * 0.22 - 0.07, 1.02, s * 0.22 + 0.07)


def flames(g):  # jazyky plamenů od přídě dozadu ke 0,35 hl, zvlněné okraje
    tips = [(-0.86, 0.50), (-0.55, 0.30), (-0.20, 0.42), (0.20, 0.42), (0.55, 0.30), (0.86, 0.50)]
    base_u = 1.02
    pts = [(base_u, -0.98)]
    edges = [-0.98, -0.70, -0.38, 0.0, 0.38, 0.70, 0.98]
    for k, (tv, tu) in enumerate(tips):
        a, b = edges[k], edges[k + 1]
        # vnitřní žlábek mezi jazyky (u přídě), pak jazyk zahnutý dozadu ven
        valley_u = 0.80 if k else 0.92
        n = 14
        for i in range(n + 1):  # náběh ke špičce
            t = i / n
            u = valley_u + (tu - valley_u) * t ** 0.8
            v = a + (tv - a) * t + 0.05 * math.sin(t * math.pi) * (1 if tv > 0 else -1)
            pts.append((u if i else valley_u, v))
        for i in range(1, n + 1):  # návrat ke žlábku
            t = i / n
            nxt = 0.80 if k < len(tips) - 1 else 0.92
            u = tu + (nxt - tu) * (t ** 1.4)
            v = tv + (b - tv) * t - 0.04 * math.sin(t * math.pi) * (1 if tv > 0 else -1)
            pts.append((u, v))
    pts.append((base_u, 0.98))
    g.poly(pts)


def checker(g):  # jako kód: dvě řady čtverců na obou bocích
    sq_v = 0.16
    sq_u = sq_v / ASP
    n = int(1.6 / sq_u)
    for side in (1, -1):
        for row in range(2):
            va = side * (0.96 - row * sq_v)
            vb = va - side * sq_v
            for i in range(n):
                if (i + row) % 2:
                    continue
                ua = n * sq_u / 2 - i * sq_u
                g.rect(ua - sq_u, min(va, vb), ua, max(va, vb))


def star(g, u, v, r_u, rot=0):
    r_v = r_u * ASP
    pts = []
    for i in range(10):
        r = 1 if i % 2 == 0 else 0.42
        a = math.radians(-90 + 36 * i + rot)
        pts.append((u - r * r_u * math.sin(a), v + r * r_v * math.cos(a)))
    g.poly(pts)


def stars(g):  # roj hvězd od zadního boku šikmo k přídi, zmenšují se
    for side in (1, -1):
        for k in range(5):
            t = k / 4
            u = -0.72 + 1.40 * t
            v = side * (0.62 - 0.22 * t)
            star(g, u, v, (0.34 - 0.16 * t) / ASP, rot=side * 15 * k)


def lightning(g):  # blesk podél každého boku, od přídě dozadu
    zz = [(0.90, 0.36), (0.42, 0.74), (0.32, 0.50), (-0.18, 0.80), (-0.28, 0.56), (-0.86, 0.80)]
    th = 0.11
    for s in (1, -1):
        top = [(u, s * (v - th)) for u, v in zz]
        bot = [(u - 0.02, s * (v + th)) for u, v in zz]
        top[0] = (zz[0][0], s * zz[0][1])
        bot[-1] = (zz[-1][0] - 0.06, s * zz[-1][1])
        g.poly(top + bot[::-1])


def waves(g):  # tři vlnovky podél boků
    for s in (1, -1):
        for k, v0 in enumerate((0.88, 0.66, 0.44)):
            th = 0.06 - 0.012 * k
            n = 120
            a = [(1.02 - 2.04 * i / n, s * (v0 + 0.06 * math.sin(i / n * 3 * 2 * math.pi + k))) for i in range(n + 1)]
            g.poly([(u, v - th) for u, v in a] + [(u, v + th) for u, v in reversed(a)])


def camo(g):  # skvrny z rozmazaného šumu, práh
    rnd = random.Random(701)
    gw, gh = 9, round(9 * ASP)
    small = Image.new("L", (gw, gh))
    small.putdata([rnd.randrange(256) for _ in range(gw * gh)])
    big = small.resize((g.w, g.h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(SS * 22))
    mask = big.point(lambda x: 255 if x > 140 else 0).filter(ImageFilter.ModeFilter(9))
    g.im.paste(Image.new("RGBA", (g.w, g.h), WHITE), (0, 0), mask)


def halftone(g):  # rastr kosočtverců, velké na bocích, mizí ke středu
    nv = 9
    nu = round(nv * ASP)
    for i in range(nu):
        u = 1.0 - 2.0 * (i + 0.5) / nu
        for j in range(nv):
            v = -1.0 + 2.0 * (j + 0.5) / nv + (1.0 / nv if i % 2 else 0)
            if abs(v) > 1.02:
                continue
            r = max(0.0, (abs(v) - 0.18) / 0.82) * 0.95
            if r < 0.08:
                continue
            ru, rv = r / nu, r / nv
            g.poly([(u + ru, v), (u, v + rv), (u - ru, v), (u, v - rv)])


DECALS = dict(stripes=stripes, flames=flames, checker=checker, stars=stars, lightning=lightning,
              waves=waves, camo=camo, halftone=halftone)

# --- kola -------------------------------------------------------------------
WS = 8
TYRE, TREAD, DISC, HUB, DARK = (30, 30, 34, 255), (16, 16, 19, 255), (214, 216, 222, 255), (150, 154, 162, 255), (70, 72, 80, 255)


class Wh:
    def __init__(self):
        self.n = 128 * WS
        self.im = Image.new("RGBA", (self.n, self.n), CLEAR)
        self.d = ImageDraw.Draw(self.im)

    def b(self, x0, y0, x1, y1):
        return [x0 * self.n, y0 * self.n, x1 * self.n - 1, y1 * self.n - 1]

    def rr(self, x0, y0, x1, y1, r, c):
        self.d.rounded_rectangle(self.b(x0, y0, x1, y1), radius=r * self.n, fill=c)

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle(self.b(x0, y0, x1, y1), fill=c)

    def poly(self, pts, c):
        self.d.polygon([(x * self.n, y * self.n) for x, y in pts], fill=c)

    def tyre(self, tread=7, width=0.05):
        self.rr(0, 0, 1, 1, 0.22, TYRE)
        for k in range(1, tread):
            y = k / tread
            self.rect(0.06, y - width / 2, 0.94, y + width / 2, TREAD)

    def out(self):
        return self.im.resize((128, 128), Image.LANCZOS)


def w_sport(w):  # nízký profil: velký disk, dvě drážky
    w.tyre(9, 0.035)
    w.rr(0.12, 0.10, 0.88, 0.90, 0.10, DISC)
    for y in (0.30, 0.70):
        w.rr(0.26, y - 0.05, 0.74, y + 0.05, 0.04, DARK)
    w.rr(0.38, 0.44, 0.62, 0.56, 0.04, HUB)


def w_whitewall(w):  # bílý bok pneumatiky kolem chromové poklice
    w.tyre(7, 0.05)
    w.rr(0.14, 0.12, 0.86, 0.88, 0.14, DISC)
    w.rr(0.26, 0.24, 0.74, 0.76, 0.10, TYRE)
    w.rr(0.34, 0.32, 0.66, 0.68, 0.08, DISC)
    w.rr(0.42, 0.45, 0.58, 0.55, 0.03, HUB)


def w_five_spoke(w):  # disk s pěti otvory mezi paprsky (z boku viděné jako okénka)
    w.tyre(7, 0.05)
    w.rr(0.18, 0.12, 0.82, 0.88, 0.12, DISC)
    for y in (0.20, 0.35, 0.65, 0.80):
        w.poly([(0.30, y - 0.05), (0.70, y - 0.03), (0.70, y + 0.03), (0.30, y + 0.05)], DARK)
    w.rr(0.36, 0.44, 0.64, 0.56, 0.04, HUB)


def w_mesh(w):  # síťka (BBS styl)
    w.tyre(7, 0.05)
    w.rr(0.16, 0.12, 0.84, 0.88, 0.12, DISC)
    for k in range(-6, 7):
        x = 0.5 + k * 0.08
        w.d.line([((x - 0.25) * w.n, 0.16 * w.n), ((x + 0.25) * w.n, 0.84 * w.n)], fill=DARK, width=int(0.022 * w.n))
        w.d.line([((x + 0.25) * w.n, 0.16 * w.n), ((x - 0.25) * w.n, 0.84 * w.n)], fill=DARK, width=int(0.022 * w.n))
    # oříznout síťku na disk
    m = Image.new("L", (w.n, w.n))
    ImageDraw.Draw(m).rounded_rectangle(w.b(0.16, 0.12, 0.84, 0.88), radius=0.12 * w.n, fill=255)
    base = Wh()
    base.tyre(7, 0.05)
    base.im.paste(w.im, (0, 0), m)
    w.im, w.d = base.im, ImageDraw.Draw(base.im)
    w.d.rounded_rectangle(w.b(0.16, 0.12, 0.84, 0.88), radius=0.12 * w.n, outline=DISC, width=int(0.05 * w.n))
    w.rr(0.38, 0.44, 0.62, 0.56, 0.04, HUB)


def w_turbine(w):  # šikmé lopatky
    w.tyre(7, 0.05)
    w.rr(0.16, 0.12, 0.84, 0.88, 0.12, DISC)
    for k in range(7):
        y = 0.18 + k * 0.105
        w.poly([(0.24, y), (0.76, y + 0.06), (0.76, y + 0.095), (0.24, y + 0.035)], DARK)
    w.rr(0.36, 0.45, 0.64, 0.55, 0.04, HUB)


def w_offroad(w):  # hrubý běhoun se špalky, malý disk
    w.rr(0.04, 0, 0.96, 1, 0.16, TYRE)
    for k in range(8):
        y = (k + 0.5) / 8
        off = 0.0 if k % 2 else 0.06
        for x0, x1 in ((0.00 + off, 0.16 + off), (0.84 - off, 1.00 - off)):
            w.rr(x0, y - 0.045, x1, y + 0.045, 0.02, TYRE)
        w.rect(0.04, y + 0.055, 0.96, y + 0.07, TREAD)
    w.rr(0.30, 0.26, 0.70, 0.74, 0.08, DISC)
    for y in (0.36, 0.64):
        w.rr(0.40, y - 0.03, 0.60, y + 0.03, 0.02, HUB)


WHEELS = dict(sport=w_sport, whitewall=w_whitewall, five_spoke=w_five_spoke, mesh=w_mesh,
              turbine=w_turbine, offroad=w_offroad)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/garage")
    a = ap.parse_args()
    for sub in ("decals", "wheels"):
        os.makedirs(os.path.join(a.out, sub), exist_ok=True)
    for i, f in DECALS.items():
        g = D()
        f(g)
        g.out().save(os.path.join(a.out, "decals", i + ".png"), optimize=True)
    for i, f in WHEELS.items():
        w = Wh()
        f(w)
        w.out().save(os.path.join(a.out, "wheels", i + ".png"), optimize=True)
    print(" ".join(list(DECALS) + list(WHEELS)))


if __name__ == "__main__":
    main()
