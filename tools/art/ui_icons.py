#!/usr/bin/env python3
"""Ikony HUD a telefonu (docs/art-requests.md kap. 5), procedurální plochý vektor bez modelu.

Bílý glyf na průhledném pozadí, 256×256, tónovatelný (klient násobí barvou: dlaždice aplikace
`color.phone.app` / `appOff`, počasí `color.weather.icon`). Bez textu a značek (R10).
  python3 tools/art/ui_icons.py [--out assets/ui] [id ...]
"""
import argparse, math, os
from PIL import Image, ImageDraw

SIZE, SS = 256, 4
N = SIZE * SS
W = 0.075  # tloušťka čáry (podíl strany)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


class G:
    def __init__(self):
        self.im = Image.new("RGBA", (N, N), CLEAR)
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def p(x, y):
        return (x * N, y * N)

    def dot(self, x, y, r, c=WHITE):
        self.d.ellipse([(x - r) * N, (y - r) * N, (x + r) * N, (y + r) * N], fill=c)

    def line(self, pts, w=W, c=WHITE, closed=False):
        pts = list(pts) + ([pts[0]] if closed else [])
        self.d.line([self.p(*q) for q in pts], fill=c, width=round(w * N))
        for q in pts:  # kulaté konce a spoje
            self.dot(q[0], q[1], w / 2, c)

    def ring(self, x, y, r, w=W, c=WHITE):
        self.d.ellipse([(x - r - w / 2) * N, (y - r - w / 2) * N, (x + r + w / 2) * N, (y + r + w / 2) * N], fill=c)
        self.d.ellipse([(x - r + w / 2) * N, (y - r + w / 2) * N, (x + r - w / 2) * N, (y + r - w / 2) * N], fill=CLEAR)

    def rrect(self, x0, y0, x1, y1, r, w=W, c=WHITE, fill=False):
        box = [x0 * N, y0 * N, x1 * N, y1 * N]
        if fill:
            self.d.rounded_rectangle(box, radius=r * N, fill=c)
        else:
            self.d.rounded_rectangle(box, radius=r * N, outline=c, width=round(w * N))

    def frect(self, x0, y0, x1, y1, c=WHITE):
        self.d.rectangle([x0 * N, y0 * N, x1 * N, y1 * N], fill=c)

    def poly(self, pts, c=WHITE):
        self.d.polygon([self.p(*q) for q in pts], fill=c)

    def arc(self, x, y, r, a0, a1, w=W, c=WHITE, steps=48):
        pts = [(x + r * math.cos(math.radians(a0 + (a1 - a0) * i / steps)),
                y + r * math.sin(math.radians(a0 + (a1 - a0) * i / steps))) for i in range(steps + 1)]
        self.line(pts, w, c)

    def out(self):
        return self.im.resize((SIZE, SIZE), Image.LANCZOS)


def feed(g):  # balíček karet
    g.rrect(0.30, 0.16, 0.80, 0.70, 0.06)
    g.rrect(0.20, 0.30, 0.70, 0.84, 0.06, fill=True)
    g.rrect(0.20 + W, 0.30 + W, 0.70 - W, 0.84 - W, 0.03, c=CLEAR, fill=True)
    g.dot(0.33, 0.44, 0.045)
    for y in (0.58, 0.69):
        g.line([(0.31, y), (0.59, y)], W * 0.8)


def map_(g):  # skládaná mapa se špendlíkem
    zig = [(0.16, 0.26), (0.38, 0.18), (0.62, 0.26), (0.84, 0.18), (0.84, 0.74), (0.62, 0.82), (0.38, 0.74), (0.16, 0.82)]
    g.line(zig, closed=True)
    g.line([(0.38, 0.18), (0.38, 0.74)], W * 0.8)
    g.line([(0.62, 0.26), (0.62, 0.82)], W * 0.8)
    g.dot(0.50, 0.44, 0.10)
    g.poly([(0.415, 0.48), (0.585, 0.48), (0.50, 0.62)])
    g.dot(0.50, 0.44, 0.04, CLEAR)


def taxi(g):  # auto zepředu se střešní cedulkou (bez nápisu)
    g.rrect(0.42, 0.14, 0.58, 0.24, 0.025, fill=True)
    g.poly([(0.30, 0.30), (0.70, 0.30), (0.80, 0.50), (0.20, 0.50)])
    g.rrect(0.14, 0.46, 0.86, 0.72, 0.07, fill=True)
    g.poly([(0.35, 0.36), (0.65, 0.36), (0.71, 0.47), (0.29, 0.47)], CLEAR)
    g.dot(0.27, 0.59, 0.055, CLEAR)
    g.dot(0.73, 0.59, 0.055, CLEAR)
    g.rrect(0.20, 0.68, 0.34, 0.84, 0.04, fill=True)
    g.rrect(0.66, 0.68, 0.80, 0.84, 0.04, fill=True)


def garage(g):  # dům s vraty
    g.line([(0.14, 0.44), (0.50, 0.16), (0.86, 0.44)])
    g.line([(0.24, 0.40), (0.24, 0.84), (0.76, 0.84), (0.76, 0.40)])
    for y in (0.52, 0.63, 0.74):
        g.line([(0.36, y), (0.64, y)], W * 0.75)


def passport(g):  # pas s glóbem
    g.rrect(0.22, 0.12, 0.78, 0.88, 0.06)
    g.ring(0.50, 0.44, 0.15, W * 0.75)
    g.line([(0.35, 0.44), (0.65, 0.44)], W * 0.6)
    g.d.ellipse([0.43 * N, 0.29 * N, 0.57 * N, 0.59 * N], outline=WHITE, width=round(W * 0.6 * N))
    g.line([(0.36, 0.72), (0.64, 0.72)], W * 0.75)


def camera(g):
    g.rrect(0.36, 0.20, 0.64, 0.34, 0.04, fill=True)
    g.rrect(0.12, 0.28, 0.88, 0.80, 0.09, fill=True)
    g.dot(0.50, 0.54, 0.19, CLEAR)
    g.dot(0.50, 0.54, 0.12)
    g.dot(0.76, 0.38, 0.035, CLEAR)


def contacts(g):  # busta
    g.dot(0.50, 0.34, 0.15)
    g.d.chord([0.20 * N, 0.56 * N, 0.80 * N, 1.12 * N], 180, 360, fill=WHITE)
    g.frect(0.20, 0.84, 0.80, 0.90, CLEAR)


def wallet(g):
    g.rrect(0.14, 0.26, 0.86, 0.80, 0.08)
    g.line([(0.22, 0.26), (0.66, 0.14), (0.72, 0.26)], W * 0.8)
    g.rrect(0.58, 0.44, 0.90, 0.62, 0.05, fill=True)
    g.dot(0.67, 0.53, 0.035, CLEAR)


def travel(g):  # letadlo shora, příď vpravo nahoře
    pts = [(0.00, -0.38), (0.06, -0.26), (0.06, -0.08), (0.38, 0.10), (0.38, 0.18), (0.06, 0.08),
           (0.05, 0.26), (0.16, 0.34), (0.16, 0.40), (0.0, 0.35)]
    pts = pts + [(-x, y) for x, y in reversed(pts[1:-1])]
    a = math.radians(45)
    g.poly([(0.5 + x * math.cos(a) - y * math.sin(a), 0.5 + x * math.sin(a) + y * math.cos(a)) for x, y in pts])


def settings(g):  # ozubené kolo
    teeth, r0, r1 = 8, 0.27, 0.37
    pts = []
    for i in range(teeth * 4):
        ang = 2 * math.pi * (i - 0.5) / (teeth * 4)
        r = r1 if i % 4 in (1, 2) else r0
        pts.append((0.5 + r * math.cos(ang), 0.5 + r * math.sin(ang)))
    g.poly(pts)
    g.dot(0.50, 0.50, 0.11, CLEAR)


def radio(g):
    g.line([(0.30, 0.30), (0.70, 0.12)], W * 0.7)
    g.rrect(0.12, 0.30, 0.88, 0.82, 0.08, fill=True)
    g.dot(0.36, 0.56, 0.14, CLEAR)
    g.dot(0.36, 0.56, 0.06)
    g.frect(0.58, 0.42, 0.78, 0.48, CLEAR)
    g.dot(0.68, 0.64, 0.07, CLEAR)


def weather_clear(g):
    g.dot(0.50, 0.50, 0.17)
    for i in range(8):
        a = math.radians(i * 45)
        g.line([(0.5 + 0.27 * math.cos(a), 0.5 + 0.27 * math.sin(a)), (0.5 + 0.37 * math.cos(a), 0.5 + 0.37 * math.sin(a))])


def drop(g, x, y, s):
    g.dot(x, y + 0.10 * s, 0.16 * s)
    g.poly([(x - 0.152 * s, y + 0.05 * s), (x + 0.152 * s, y + 0.05 * s), (x, y - 0.24 * s)])


def weather_rain(g):
    drop(g, 0.42, 0.40, 1.0)
    drop(g, 0.70, 0.66, 0.55)
    drop(g, 0.30, 0.76, 0.40)


def weather_fog(g):
    for y in (0.30, 0.50, 0.70):
        g.line([(0.16 + 0.68 * i / 40, y + 0.035 * math.sin(i / 40 * 2.5 * 2 * math.pi)) for i in range(41)])


def wanted_star(g):
    pts = []
    for i in range(10):
        r = 0.38 if i % 2 == 0 else 0.16
        a = math.radians(-90 + 36 * i)
        pts.append((0.5 + r * math.cos(a), 0.53 + r * math.sin(a)))
    g.poly(pts)


ICONS = dict(feed=feed, map=map_, taxi=taxi, garage=garage, passport=passport, camera=camera,
             contacts=contacts, wallet=wallet, travel=travel, settings=settings, radio=radio,
             weather_clear=weather_clear, weather_rain=weather_rain, weather_fog=weather_fog,
             wanted_star=wanted_star)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/ui")
    ap.add_argument("ids", nargs="*")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for i in a.ids or ICONS:
        g = G()
        ICONS[i](g)
        g.out().save(os.path.join(a.out, i + ".png"), optimize=True)
        print(i)


if __name__ == "__main__":
    main()
