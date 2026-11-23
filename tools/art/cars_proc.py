#!/usr/bin/env python3
"""Sprity aut kolmo shora, procedurálně (vektor, bez modelu), styl A. Formát: docs/art-requests.md kap. 3,
specs/art.md „Auta“, siluety podle specs/cars.md „Kreslení“.

  python3 tools/art/cars_proc.py --out assets/cars [id ...]

Na auto: body.png (lak světle šedý se stínováním), paint_mask.png (bílá = lak), wheel.png (jedno kolo
na střed), lights.png (rozsvícená světla). Kreslí se v 8× rozlišení a zmenší se (vyhlazené hrany).
Souřadnice auta: u podél (−1 záď … +1 předek, v násobcích hl), v napříč (−1 … +1, v násobcích hw).
"""
import argparse, math, os
from PIL import Image, ImageDraw, ImageChops

PX_M = 32          # px na metr
SS = 8             # supersampling
AXLE = 0.62        # drive.axle_offset
WHEEL_V = 0.92     # kola na ±0,92 hw

# barvy (nelakované části)
OUT = (27, 27, 31, 255)        # obrys
GLASS = (44, 56, 72, 255)
GLASS_HI = (86, 104, 124, 255)
BUMPER = (58, 60, 66, 255)
HEAD_OFF = (222, 220, 204, 255)
TAIL_OFF = (128, 30, 36, 255)
HEAD_ON = (255, 246, 214, 255)
TAIL_ON = (255, 40, 40, 255)
WELL = (20, 20, 24, 255)
# tóny laku (násobí se barvou laku)
P_TOP, P_MID, P_SIDE, P_DARK = 250, 232, 204, 178

# třída, délka, šířka m, kabina (u_zad, u_před), poloměr rohů (předek, záď) v hw
CARS = {
    "m0_coupe":      dict(cls="coupe", L=4.5, W=1.9, cab=(-0.42, 0.30), r=(0.55, 0.45)),
    "taxi_metro":    dict(cls="taxi", L=5.0, W=1.9, cab=(-0.45, 0.30), r=(0.45, 0.40)),
    "hatch_pip":     dict(cls="hatchback", L=3.9, W=1.75, cab=(-0.70, 0.25), r=(0.60, 0.40)),
    "sedan_harbor":  dict(cls="sedan", L=4.8, W=1.85, cab=(-0.45, 0.25), r=(0.50, 0.42)),
    "sedan_crown":   dict(cls="sedan", L=5.2, W=1.9, cab=(-0.45, 0.25), r=(0.40, 0.35), chrome=True),
    "van_courier":   dict(cls="van", L=5.4, W=2.0, cab=(0.62, 0.85), r=(0.40, 0.20)),
    "mini_pebble":   dict(cls="mini", L=3.0, W=1.6, cab=(-0.55, 0.35), r=(0.75, 0.60)),
    "pickup_hauler": dict(cls="pickup", L=5.4, W=2.0, cab=(0.05, 0.45), r=(0.40, 0.18)),
    "muscle_brute":  dict(cls="muscle", L=4.9, W=1.95, cab=(-0.50, 0.10), r=(0.30, 0.28)),
    "traffic_sedan": dict(cls="sedan", L=4.6, W=1.9, cab=(-0.45, 0.25), r=(0.50, 0.42)),
    "police_patrol": dict(cls="police", L=4.9, W=1.95, cab=(-0.45, 0.25), r=(0.45, 0.40)),
    # --- dávka 2 ---
    "sedan_regent":   dict(cls="sedan", L=5.0, W=1.88, cab=(-0.45, 0.25), r=(0.42, 0.36), chrome=True),
    "hatch_city":     dict(cls="hatchback", L=4.1, W=1.75, cab=(-0.70, 0.25), r=(0.55, 0.42)),
    "hatch_rally":    dict(cls="hatchback", L=4.0, W=1.8, cab=(-0.70, 0.25), r=(0.50, 0.38), rally=True),
    "kombi_fjord":    dict(cls="kombi", L=4.9, W=1.85, cab=(-0.75, 0.25), r=(0.48, 0.30)),
    "kombi_woody":    dict(cls="kombi", L=5.3, W=1.95, cab=(-0.75, 0.25), r=(0.40, 0.26), wood=True, chrome=True),
    "van_box":        dict(cls="van", L=6.6, W=2.2, cab=(0.66, 0.86), r=(0.35, 0.10), box=True),
    "van_wander":     dict(cls="van", L=4.6, W=1.8, cab=(0.62, 0.85), r=(0.60, 0.45), wander=True),
    "mini_bolt":      dict(cls="mini", L=3.4, W=1.7, cab=(-0.55, 0.35), r=(0.65, 0.55)),
    "mini_dot":       dict(cls="mini", L=2.7, W=1.55, cab=(-0.55, 0.35), r=(0.85, 0.75)),
    "coupe_nova":     dict(cls="coupe", L=4.4, W=1.82, cab=(-0.42, 0.30), r=(0.60, 0.50)),
    "coupe_strada":   dict(cls="coupe", L=4.6, W=1.85, cab=(-0.42, 0.30), r=(0.55, 0.45), stripe=(36, 38, 44, 255)),
    "taxi_classic":   dict(cls="taxi", L=5.4, W=2.0, cab=(-0.45, 0.30), r=(0.38, 0.34), chrome=True),
    "pickup_mesa":    dict(cls="pickup", L=5.6, W=2.05, cab=(0.05, 0.45), r=(0.38, 0.16)),
    "off_bloc":       dict(cls="offroad", L=4.8, W=1.98, cab=(-0.60, 0.30), r=(0.14, 0.12)),
    "off_ridge":      dict(cls="offroad", L=4.7, W=1.95, cab=(-0.60, 0.30), r=(0.30, 0.18)),
    "muscle_bulldog": dict(cls="muscle", L=5.1, W=1.98, cab=(-0.50, 0.10), r=(0.28, 0.26), stripe=(238, 238, 232, 255)),
    "muscle_thunder": dict(cls="muscle", L=5.0, W=1.95, cab=(-0.50, 0.10), r=(0.30, 0.28), stripe=(238, 238, 232, 255)),
    "limo_grand":     dict(cls="limo", L=8.2, W=2.05, cab=(-0.55, 0.35), r=(0.40, 0.36), chrome=True),
    "limo_stretch":   dict(cls="limo", L=7.6, W=2.0, cab=(-0.55, 0.35), r=(0.36, 0.32), chrome=True),
    "vet_skyliner":   dict(cls="veteran", L=5.6, W=2.0, cab=(-0.40, 0.15), r=(0.30, 0.30), chrome=True),
    "vet_tourer":     dict(cls="veteran", L=4.6, W=1.75, cab=(-0.40, 0.15), r=(0.22, 0.30)),
    "super_arrow":    dict(cls="supersport", L=4.5, W=1.95, cab=(-0.30, 0.15), r=(0.75, 0.40)),
    "super_lumen":    dict(cls="supersport", L=4.7, W=1.98, cab=(-0.30, 0.15), r=(0.85, 0.50)),
    "super_vento":    dict(cls="supersport", L=4.4, W=1.92, cab=(-0.30, 0.15), r=(0.70, 0.35)),
    "vega_roadster":  dict(cls="supersport", L=4.0, W=1.85, cab=(-0.30, 0.15), r=(0.70, 0.45), open=True),
    "bus_city":       dict(cls="bus", L=12.0, W=2.55, cab=(0.92, 1.0), r=(0.20, 0.16)),
    "spec_grill":     dict(cls="foodtruck", L=7.0, W=2.3, cab=(0.66, 0.86), r=(0.35, 0.12)),
    "spec_trike":     dict(cls="trike", L=3.2, W=1.5, cab=(-0.35, 0.10), r=(0.30, 0.35)),
    "spec_rickshaw":  dict(cls="rickshaw", L=2.6, W=1.2, cab=(-0.90, 0.10), r=(0.25, 0.30)),
    "kolo":           dict(cls="micro", L=1.8, W=0.6),
    "micro_cruiser":  dict(cls="micro", L=1.8, W=0.6, cruiser=True),
    "kolobezka":      dict(cls="micro", L=1.2, W=0.55),
    "micro_scoot":    dict(cls="micro", L=1.15, W=0.55),
}
BATCH1 = ["m0_coupe", "taxi_metro", "hatch_pip", "sedan_harbor", "sedan_crown", "van_courier", "mini_pebble",
          "pickup_hauler", "muscle_brute", "traffic_sedan", "police_patrol"]


def wheel_size(L, W):
    """délka × šířka kola v m (docs/art-requests.md kap. 3)."""
    return min(0.36 * L / 2, W / 2), 0.32 * W / 2


class Car:
    def __init__(self, L, W):
        self.L, self.W = L, W
        self.cw = math.ceil(round(W * PX_M * 1.1, 3))
        self.ch = math.ceil(round(L * PX_M * 1.1, 3))
        S = SS
        self.size = (self.cw * S, self.ch * S)
        self.cx, self.cy = self.size[0] / 2, self.size[1] / 2
        self.hl, self.hw = L / 2 * PX_M * S, W / 2 * PX_M * S
        self.body = Image.new("RGBA", self.size, (0, 0, 0, 0))
        self.mask = Image.new("L", self.size, 0)
        self.lights = Image.new("RGBA", self.size, (0, 0, 0, 0))
        self.db, self.dm, self.dl = ImageDraw.Draw(self.body), ImageDraw.Draw(self.mask), ImageDraw.Draw(self.lights)

    def p(self, u, v):
        return (self.cx + v * self.hw, self.cy - u * self.hl)

    def box(self, u0, u1, v0, v1):
        (x0, y0), (x1, y1) = self.p(max(u0, u1), min(v0, v1)), self.p(min(u0, u1), max(v0, v1))
        return [x0, y0, x1, y1]

    def fill(self, shape, col, paint, **kw):
        """shape = ('rect', box, radius_px) | ('poly', [pts]) | ('ellipse', box). paint = tón laku (0–255) nebo None."""
        c = (paint, paint, paint, 255) if paint is not None else col
        m = 255 if paint is not None else 0
        for d, val in ((self.db, c), (self.dm, m)):
            if shape[0] == "rect":
                d.rounded_rectangle(shape[1], radius=shape[2], fill=val)
            elif shape[0] == "poly":
                d.polygon(shape[1], fill=val)
            else:
                d.ellipse(shape[1], fill=val)

    def rect(self, u0, u1, v0, v1, col=None, paint=None, rad=0.0):
        """rad v násobcích hw."""
        self.fill(("rect", self.box(u0, u1, v0, v1), rad * self.hw), col, paint)

    def poly(self, pts, col=None, paint=None):
        self.fill(("poly", [self.p(u, v) for u, v in pts]), col, paint)

    def light(self, u0, u1, v0, v1, on, rad=0.08):
        self.dl.rounded_rectangle(self.box(u0, u1, v0, v1), radius=rad * self.hw, fill=on)


def silhouette(c, rf, rr, half_w=1.0, taper=0.0):
    """Obrys karoserie: obdélník s jinými poloměry rohů vpředu a vzadu, volitelně zúžený předek."""
    pts = []
    def arc(cu, cv, r_u, r_v, a0, a1, n=14):
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cu + r_u * math.sin(a), cv + r_v * math.cos(a)))
    hw_f = half_w - taper
    ru_f, rv_f = rf * c.hw / c.hl, rf
    ru_r, rv_r = rr * c.hw / c.hl, rr
    # předek: levý → pravý, záď: pravý → levý (v = +1 vlevo)
    arc(1 - ru_f, hw_f - rv_f, ru_f, rv_f, 0, 90)        # předek vlevo
    arc(1 - ru_f, -hw_f + rv_f, ru_f, rv_f, 90, 180)     # předek vpravo
    arc(-1 + ru_r, -half_w + rv_r, ru_r, rv_r, 180, 270)  # záď vpravo
    arc(-1 + ru_r, half_w - rv_r, ru_r, rv_r, 270, 360)  # záď vlevo
    return pts


def wheels(c, cls):
    wl, ww = wheel_size(c.L, c.W)
    if cls in ("trike", "rickshaw"):
        # jedno přední kolo uprostřed na +0,75 hl, vzadu dvě
        return [(0.75, 0.0)] + [(-AXLE, s * WHEEL_V) for s in (1, -1)], wl * PX_M * SS, ww * PX_M * SS
    if cls == "bus":
        us = (0.60, -0.70)
    else:
        us = (AXLE, -AXLE)
    return [(u, s * WHEEL_V) for u in us for s in (1, -1)], wl * PX_M * SS, ww * PX_M * SS


def sil_shapes(c, cls, rf, rr, inset_v=0.0):
    """Polygony siluety v (u, v); inset_v > 0 = vnitřní obrys (o tolik hw menší)."""
    k = inset_v * c.hw / c.hl
    if cls == "veteran":
        hw_ = 0.80
        p = silhouette(c, max(rf - inset_v, 0.05), max(rr - inset_v, 0.05), half_w=hw_ - inset_v)
        return [[(u * (1 - k), v) for u, v in p]]
    if cls == "trike":
        # záď v plné šířce do +0,30 hl, příď zúžená na ±0,45 hw do +0,52 hl (kolo je před ní)
        rear = rounded_poly(c, -1 + k, 0.36 - k, 1 - inset_v, max(rr - inset_v, 0.05), max(0.5 - inset_v, 0.05))
        nose = rounded_poly(c, 0.20, 0.52 - k, 0.45 - inset_v, 0.10, max(0.30 - inset_v, 0.05))
        return [rear, nose]
    if cls == "rickshaw":
        rear = rounded_poly(c, -1 + k, 0.16 - k, 1 - inset_v, max(rr - inset_v, 0.05), max(0.25 - inset_v, 0.05))
        beam = rounded_poly(c, 0.05, 0.58 - k, 0.16 - inset_v, 0.06, 0.06)
        return [rear, beam]
    p = silhouette(c, max(rf - inset_v, 0.05), max(rr - inset_v, 0.05), half_w=1 - inset_v)
    return [[(u * (1 - k), v) for u, v in p]]


def rounded_poly(c, u0, u1, half, rr, rf):
    """Obdélník u0…u1 × ±half s poloměry rohů rr (záď) a rf (předek) v hw."""
    pts = []
    def arc(cu, cv, r_u, r_v, a0, a1, n=12):
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cu + r_u * math.sin(a), cv + r_v * math.cos(a)))
    rf, rr = min(rf, half), min(rr, half)
    ruf, rur = rf * c.hw / c.hl, rr * c.hw / c.hl
    arc(u1 - ruf, half - rf, ruf, rf, 0, 90)
    arc(u1 - ruf, -half + rf, ruf, rf, 90, 180)
    arc(u0 + rur, -half + rr, rur, rr, 180, 270)
    arc(u0 + rur, half - rr, rur, rr, 270, 360)
    return pts


def draw_car(cid, spec):
    c = Car(spec["L"], spec["W"])
    cls = spec["cls"]
    if cls == "micro":
        return draw_micro(c, spec)
    rf, rr = spec["r"]
    police = cls == "police"
    S = SS

    # 1) silueta (alfa), obrys a základní lak
    sil = Image.new("L", c.size, 0)
    for pts in sil_shapes(c, cls, rf, rr):
        ImageDraw.Draw(sil).polygon([c.p(u, v) for u, v in pts], fill=255)
        c.poly(pts, col=OUT)
    inset = 1.6 * S / c.hw  # obrys ~1,6 px
    base = P_MID
    for pts in sil_shapes(c, cls, rf, rr, inset):
        c.poly(pts, paint=base)
    # boční pás tmavší, středový pruh světlejší (dva až tři tóny)
    side = 0.80 if cls == "veteran" else 1.0
    if cls == "rickshaw":
        pass
    elif cls == "trike":
        c.rect(-0.97, 0.30, 0.74, 0.92, paint=P_SIDE)
        c.rect(-0.97, 0.30, -0.92, -0.74, paint=P_SIDE)
    else:
        c.rect(-0.97, 0.97, 0.74 * side, 0.92 * side, paint=P_SIDE)
        c.rect(-0.97, 0.97, -0.92 * side, -0.74 * side, paint=P_SIDE)

    cab0, cab1 = spec["cab"]
    if police:
        # fiktivní hlídka: tmavá kapota a víko, bílá kabina a boky, bez masky laku
        NAVY, NAVY_S, WHITE, WHITE_S = (30, 40, 64, 255), (22, 30, 50, 255), (244, 244, 240, 255), (214, 216, 216, 255)
        c.rect(cab1 + 0.02, 0.98, -0.97, 0.97, col=NAVY)
        c.rect(-0.98, cab0 - 0.02, -0.97, 0.97, col=NAVY)
        c.rect(cab0 - 0.02, cab1 + 0.02, -0.97, 0.97, col=WHITE)
        for s in (1, -1):
            c.rect(cab0 - 0.02, cab1 + 0.02, s * 0.76, s * 0.94, col=WHITE_S)
            c.rect(cab1 + 0.02, 0.97, s * 0.76, s * 0.94, col=NAVY_S)
            c.rect(-0.97, cab0 - 0.02, s * 0.76, s * 0.94, col=NAVY_S)

    # 2) kabina / sklo podle třídy
    def cabin(u0, u1, half=0.80, roof_half=0.64, ws=0.20, rw=0.13, roof_paint=P_TOP, roof_col=None):
        c.poly([(u1, half - 0.12), (u1, -half + 0.12), (u1 - ws, -half), (u0 + rw, -half),
                (u0, -half + 0.10), (u0, half - 0.10), (u0 + rw, half), (u1 - ws, half)], col=GLASS)
        # odlesk na předním skle
        c.poly([(u1 - 0.02, 0.30), (u1 - 0.02, 0.10), (u1 - ws + 0.04, -0.05), (u1 - ws + 0.04, 0.18)], col=GLASS_HI)
        c.rect(u0 + rw, u1 - ws, -roof_half, roof_half, col=roof_col, paint=None if roof_col else roof_paint, rad=0.10)

    roof_col = (244, 244, 240, 255) if police else None
    if cls in ("coupe", "sedan", "taxi", "muscle", "police"):
        cabin(cab0, cab1, roof_col=roof_col, ws=0.20 if cls != "muscle" else 0.16)
    elif cls == "hatchback":
        cabin(cab0, cab1, rw=0.08, ws=0.20)
    elif cls == "mini":
        cabin(cab0, cab1, half=0.82, roof_half=0.66, rw=0.10, ws=0.20)
    elif cls == "pickup":
        cabin(cab0, cab1, rw=0.07, ws=0.14)
    elif cls in ("van", "foodtruck"):
        # jen přední sklo, za ním nákladová střecha (lak + žebra)
        c.poly([(cab1, 0.72), (cab1, -0.72), (cab0, -0.84), (cab0, 0.84)], col=GLASS)
        c.poly([(cab1 - 0.02, 0.30), (cab1 - 0.02, 0.12), (cab0 + 0.03, -0.02), (cab0 + 0.03, 0.18)], col=GLASS_HI)
        if spec.get("box") or cls == "foodtruck":
            # skříň oddělená od kabiny tmavou spárou, střecha skříně bez žeber
            c.rect(cab0 - 0.10, cab0 - 0.07, -0.97, 0.97, col=OUT)
            c.rect(-0.96, cab0 - 0.12, -0.90, 0.90, paint=P_TOP, rad=0.03)
            c.rect(cab0 - 0.07, cab0 - 0.005, -0.80, 0.80, paint=P_SIDE, rad=0.04)
            u = -0.90
            while u < cab0 - 0.16:
                c.rect(u, u + 0.012, -0.86, 0.86, paint=P_SIDE)
                u += 0.10
        elif spec.get("wander"):
            # obytná dodávka: zaoblená střecha, světlíky
            c.rect(-0.94, 0.56, -0.84, 0.84, paint=P_TOP, rad=0.30)
            for u in (-0.55, -0.10, 0.30):
                c.rect(u, u + 0.16, -0.40, 0.40, col=GLASS, rad=0.08)
            c.rect(-0.92, -0.70, -0.70, 0.70, paint=P_SIDE, rad=0.10)
        else:
            c.rect(-0.96, 0.55, -0.84, 0.84, paint=P_TOP, rad=0.06)
            u = -0.86
            while u < 0.50:
                c.rect(u, u + 0.025, -0.80, 0.80, paint=P_SIDE)
                u += 0.12
    elif cls == "kombi":
        cabin(cab0, cab1, rw=0.05, ws=0.20)
        for s in (1, -1):
            c.rect(-0.70, 0.20, s * 0.67, s * 0.73, col=(42, 44, 51, 255))
    elif cls == "offroad":
        cabin(cab0, cab1, half=0.84, roof_half=0.70, rw=0.06, ws=0.14)
        # žebra na střeše
        for u in (-0.40, -0.20, 0.00):
            c.rect(u, u + 0.03, -0.62, 0.62, paint=P_SIDE)
    elif cls == "limo":
        cabin(cab0, cab1, rw=0.08, ws=0.12)
        for u in (-0.25, 0.05):
            c.rect(u - 0.02, u + 0.02, -0.80, 0.80, col=(14, 15, 18, 255))
        c.rect(cab0 + 0.08, cab1 - 0.12, -0.64, 0.64, paint=P_TOP, rad=0.06)
    elif cls == "veteran":
        cabin(cab0, cab1, half=0.66, roof_half=0.52, rw=0.08, ws=0.12)
        # kapota s podélnou spárou
        c.rect(cab1 + 0.04, 0.95, -0.015, 0.015, paint=P_SIDE)
    elif cls == "supersport":
        if spec.get("open"):
            # roadster bez střechy: čelní sklo, dvě sedadla, ochranné oblouky
            c.poly([(cab1 + 0.06, 0.58), (cab1 + 0.06, -0.58), (cab1 - 0.02, -0.70), (cab1 - 0.02, 0.70)], col=GLASS)
            c.rect(cab0, cab1 - 0.02, -0.66, 0.66, col=(40, 34, 32, 255), rad=0.12)
            for s in (1, -1):
                c.rect(cab0 + 0.06, cab1 - 0.08, s * 0.08, s * 0.56, col=(92, 52, 40, 255), rad=0.10)
                c.rect(cab0 - 0.10, cab0 - 0.02, s * 0.14, s * 0.50, paint=P_SIDE, rad=0.20)
        else:
            cabin(cab0, cab1, half=0.70, roof_half=0.50, rw=0.08, ws=0.14)
        # nasávání po stranách za kabinou
        for s in (1, -1):
            c.rect(cab0 - 0.22, cab0 - 0.04, s * 0.70, s * 0.84, col=(36, 36, 42, 255), rad=0.10)
    elif cls == "bus":
        c.rect(-0.97, 0.90, -0.90, 0.90, paint=P_TOP, rad=0.04)
        c.rect(0.91, 0.99, -0.86, 0.86, col=GLASS, rad=0.06)
        for a, b in ((-0.30, -0.10), (0.20, 0.40)):
            c.rect(a, b, -0.40, 0.40, col=OUT, rad=0.06)
            c.rect(a + 0.01, b - 0.01, -0.37, 0.37, col=(201, 205, 211, 255), rad=0.05)
            for k in range(1, 4):
                uu = a + (b - a) * k / 4
                c.rect(uu - 0.003, uu + 0.003, -0.32, 0.32, col=(160, 166, 174, 255))
        for u in (-0.75, 0.62):
            c.rect(u, u + 0.06, -0.20, 0.20, col=(96, 100, 108, 255), rad=0.04)
    elif cls == "trike":
        cabin(cab0, cab1, rw=0.10, ws=0.14)
        # řídítka a světlo na přídi
        c.rect(0.40, 0.44, -0.40, 0.40, col=(40, 40, 46, 255), rad=0.02)
    elif cls == "rickshaw":
        # plachta v laku přes celou šířku, žebra; vpředu nosník a jezdec
        c.rect(-0.90, 0.10, -0.96, 0.96, col=OUT, rad=0.20)
        c.rect(-0.88, 0.08, -0.92, 0.92, paint=P_TOP, rad=0.18)
        for u in (-0.62, -0.34, -0.06):
            c.rect(u, u + 0.03, -0.92, 0.92, paint=P_SIDE)
        c.rect(-0.98, -0.92, -0.80, 0.80, col=BUMPER, rad=0.10)

    # 3) detaily třídy
    if cls == "coupe":
        for s in (1, -1):
            for a, b in ((cab1 + 0.02, 0.96), (-0.96, cab0 - 0.02)):
                c.rect(a, b, s * 0.06, s * 0.20, col=spec.get("stripe", (240, 240, 234, 255)))
    if cls == "muscle":
        for s in (1, -1):
            c.rect(-0.97, 0.97, s * 0.14, s * 0.30, col=spec.get("stripe", (30, 30, 35, 255)))
        # nasávání na kapotě
        c.rect(0.38, 0.62, -0.10, 0.10, col=(40, 40, 46, 255), rad=0.04)
    if cls == "taxi":
        # šachovnicový pruh po bocích mezi koly, cedule bez nápisu na střeše
        n, u0, u1 = 8, -0.40, 0.36
        for s in (1, -1):
            for i in range(n):
                a = u0 + (u1 - u0) * i / n
                b = u0 + (u1 - u0) * (i + 1) / n
                for j, (v0, v1) in enumerate(((0.80, 0.87), (0.87, 0.94))):
                    col = (27, 27, 31, 255) if (i + j) % 2 == 0 else (246, 246, 240, 255)
                    c.rect(a, b, s * v0, s * v1, col=col)
        c.rect(-0.15, 0.05, -0.37, 0.37, col=OUT, rad=0.10)
        c.rect(-0.13, 0.03, -0.33, 0.33, col=(255, 246, 208, 255), rad=0.08)
        c.rect(-0.05, 0.02, -0.30, 0.30, col=(250, 214, 92, 255), rad=0.05)
    if cls == "pickup":
        # korba s lemem v laku, tmavé dno se žebry
        c.rect(-0.96, -0.02, -0.90, 0.90, paint=P_SIDE, rad=0.08)
        c.rect(-0.92, -0.06, -0.78, 0.78, col=(47, 58, 40, 255))
        for k in range(5):
            u = -0.86 + k * 0.17
            c.rect(u, u + 0.03, -0.74, 0.74, col=(36, 44, 30, 255))
    if cls == "police":
        # prázdné pouzdro majáku napříč (±0,6 hw, hloubka 0,12 hl, střed střechy)
        mid = (cab0 + 0.13 + cab1 - 0.20) / 2
        c.rect(mid - 0.06, mid + 0.06, -0.60, 0.60, col=OUT, rad=0.04)
        c.rect(mid - 0.045, mid + 0.045, -0.56, 0.56, col=(70, 72, 80, 255), rad=0.03)
    if spec.get("rally"):
        # bílý pruh mimo osu přes celé auto, světla na kapotě
        c.rect(-0.96, 0.96, -0.36, -0.20, col=(240, 240, 234, 255))
        for s in (1, -1):
            c.rect(0.74, 0.82, s * 0.30, s * 0.58, col=HEAD_OFF, rad=0.30)
    if spec.get("wood"):
        # dřevěné boční panely (ne lak)
        for s in (1, -1):
            c.rect(-0.95, 0.30, s * 0.80, s * 0.97, col=(148, 98, 56, 255))
            c.rect(-0.93, 0.28, s * 0.82, s * 0.95, col=(176, 122, 72, 255))
            for u in (-0.60, -0.20, 0.10):
                c.rect(u, u + 0.02, s * 0.82, s * 0.95, col=(120, 78, 44, 255))
    if cls == "offroad":
        # rezerva na zádi uvnitř obrysu
        r_u = 0.45 * c.hw / c.hl
        uc = -1.0 + r_u + 0.02
        c.fill(("ellipse", [c.p(uc + r_u, -0.45)[0], c.p(uc + r_u, 0)[1], c.p(uc - r_u, 0.45)[0], c.p(uc - r_u, 0)[1]]), (34, 36, 42, 255), None)
        rr_ = 0.24
        r2 = rr_ * c.hw / c.hl
        c.fill(("ellipse", [c.p(uc, -rr_)[0], c.p(uc + r2, 0)[1], c.p(uc, rr_)[0], c.p(uc - r2, 0)[1]]), (190, 192, 198, 255), None)
    if cls == "veteran":
        # blatníky jen na vnitřní straně kol a před a za nimi (kolo zvenku zůstává vidět)
        wl, _ = wheel_size(c.L, c.W)
        h = wl / (c.L / 2) / 2
        for u in (AXLE, -AXLE):
            for s in (1, -1):
                c.rect(u - h - 0.06, u + h + 0.06, s * 0.70, s * 0.80, col=(20, 20, 26, 255), rad=0.30)
                for e in (u + h + 0.03, u - h - 0.06):
                    c.rect(e, e + 0.03, s * 0.70, s * 0.98, col=(20, 20, 26, 255), rad=0.4)
        # chromové nárazníky přes celou šířku
        c.rect(0.975, 1.0, -0.96, 0.96, col=(200, 204, 210, 255), rad=0.2)
        c.rect(-1.0, -0.975, -0.96, 0.96, col=(200, 204, 210, 255), rad=0.2)
    if cls == "supersport":
        # spoiler −1,00 … −0,90 hl × ±0,95 hw
        c.rect(-1.0, -0.90, -0.95, 0.95, col=(27, 27, 31, 255), rad=0.06)
    if cls == "foodtruck":
        # markýza na pravém boku (posunutá mimo kola), střídavé pruhy po 0,15 hl
        u = -0.42
        i = 0
        while u < 0.40:
            col = (244, 240, 230, 255) if i % 2 == 0 else (210, 58, 46, 255)
            c.rect(u, min(u + 0.15, 0.40), 0.78, 0.98, col=col)
            u += 0.15
            i += 1
        # komín grilu a ventilace na střeše
        c.fill(("ellipse", c.box(-0.55, -0.45, -0.40, -0.10)), (60, 62, 68, 255), None)
        c.rect(-0.20, -0.05, -0.50, -0.20, col=(150, 154, 162, 255), rad=0.1)
    if spec.get("chrome"):
        # chromová lišta mezi kapotou a maskou
        c.rect(0.93, 0.955, -0.70, 0.70, col=(200, 204, 210, 255))

    # 4) nárazníky a světla
    if cls == "trike":
        c.rect(0.47, 0.515, -0.30, 0.30, col=HEAD_OFF, rad=0.10)
        c.light(0.47, 0.515, -0.30, 0.30, on=HEAD_ON)
    if cls not in ("veteran", "rickshaw", "trike"):
        c.rect(0.955, 1.0, -0.86, 0.86, col=BUMPER, rad=0.10)
        c.rect(-1.0, -0.96, -0.86, 0.86, col=BUMPER, rad=0.10)
    for s in ((1, -1) if cls != "rickshaw" else ()):
        hv = (s * 0.46, s * 0.80)
        tv = (s * 0.50, s * 0.84)
        c.rect(0.90, 0.975, *hv, col=HEAD_OFF, rad=0.06)
        c.light(0.90, 0.975, *hv, on=HEAD_ON)
        c.rect(-0.975, -0.915, *tv, col=TAIL_OFF, rad=0.05)
        c.light(-0.975, -0.915, *tv, on=TAIL_ON)

    # 5) ořez siluetou a výřezy pro kola (zvenku nic nezakrývá kolo, podběh tmavý)
    whs, wl_px, ww_px = wheels(c, cls)
    db_ = ImageDraw.Draw(c.body)
    for u, v in whs:
        x, y = c.p(u, v)
        s = 1 if v > 0 else -1
        gap = 0.6 * S
        if v == 0:
            # přední kolo uprostřed (tříkolka, rikša): průhledné okno přes celé kolo
            ImageDraw.Draw(sil).rounded_rectangle([x - ww_px / 2 - gap, y - wl_px / 2 - gap, x + ww_px / 2 + gap,
                                                   y + wl_px / 2 + gap], radius=1.0 * S, fill=0)
            continue
        # tmavý podběh na vnitřní straně kola
        well = [x - s * (ww_px / 2 + 1.2 * S), y - wl_px / 2 - 1.4 * S, x + s * 4 * ww_px, y + wl_px / 2 + 1.4 * S]
        db_.rounded_rectangle([min(well[0], well[2]), well[1], max(well[0], well[2]), well[3]], radius=1.5 * S, fill=WELL)
        ImageDraw.Draw(c.mask).rounded_rectangle([min(well[0], well[2]), well[1], max(well[0], well[2]), well[3]], radius=1.5 * S, fill=0)
        # průhledný výřez od vnitřní hrany kola ven (kolo pod karoserií je vidět)
        cut = [x - s * (ww_px / 2 - 0.2 * S - gap), y - wl_px / 2 - gap, x + s * 4 * ww_px, y + wl_px / 2 + gap]
        ImageDraw.Draw(sil).rounded_rectangle([min(cut[0], cut[2]), cut[1], max(cut[0], cut[2]), cut[3]], radius=1.0 * S, fill=0)
    a = ImageChops.multiply(c.body.getchannel("A"), sil)
    c.body.putalpha(a)
    c.mask = ImageChops.multiply(c.mask, sil)
    c.lights.putalpha(ImageChops.multiply(c.lights.getchannel("A"), sil))

    out = {
        "body": c.body.resize((c.cw, c.ch), Image.LANCZOS),
        "lights": c.lights.resize((c.cw, c.ch), Image.LANCZOS),
        "wheel": draw_wheel(c.L, c.W),
    }
    if cls == "rickshaw":
        del out["lights"]
        c.dm = ImageDraw.Draw(c.mask)  # maska je po ořezu nový obrázek
        rider(c, 0.42, 0.62)
        out["body"] = c.body.resize((c.cw, c.ch), Image.LANCZOS)
    if not police:
        m = c.mask.resize((c.cw, c.ch), Image.LANCZOS)
        out["paint_mask"] = Image.merge("LA", (m, out["body"].getchannel("A")))
    return out


SKIN = (226, 186, 152, 255)
HAIR = (66, 48, 38, 255)
JACKET = (40, 44, 58, 255)
DARK = (34, 34, 40, 255)


def rider(c, u_sh, u_bar, helmet=False, half=0.85):
    """Jezdec shora: ramena (elipsa), ruce k řídítkům, hlava (vlasy nebo helma v laku)."""
    S = SS
    # ramena a trup
    dv = half
    du = 0.13 / (c.L / 2)  # hloubka ramen ±13 cm
    c.fill(("ellipse", c.box(u_sh - du, u_sh + du, -dv, dv)), OUT, None)
    c.fill(("ellipse", c.box(u_sh - du * 0.85, u_sh + du * 0.85, -dv * 0.9, dv * 0.9)), JACKET, None)
    # ruce
    for s in (1, -1):
        x0, y0 = c.p(u_sh + du * 0.3, s * dv * 0.72)
        x1, y1 = c.p(u_bar - 0.02, s * dv * 0.80)
        for d, col in ((c.db, JACKET),):
            d.line([(x0, y0), (x1, y1)], fill=col, width=int(max(c.hw * 0.26, 2 * S)))
        c.db.ellipse([x1 - 0.9 * S, y1 - 0.9 * S, x1 + 0.9 * S, y1 + 0.9 * S], fill=SKIN)
        c.dm.ellipse([x1 - 0.9 * S, y1 - 0.9 * S, x1 + 0.9 * S, y1 + 0.9 * S], fill=0)
        c.dm.line([(x0, y0), (x1, y1)], fill=0, width=int(max(c.hw * 0.26, 2 * S)))
    # hlava
    r = 0.36
    ru = r * c.hw / c.hl
    uh = u_sh + du * 0.35
    c.fill(("ellipse", c.box(uh - ru, uh + ru, -r, r)), OUT, None)
    if helmet:
        c.fill(("ellipse", c.box(uh - ru * 0.85, uh + ru * 0.85, -r * 0.85, r * 0.85)), None, P_TOP)
        c.rect(uh - 0.01, uh + 0.01, -0.06, 0.06, col=DARK)
    else:
        c.fill(("ellipse", c.box(uh - ru * 0.85, uh + ru * 0.85, -r * 0.85, r * 0.85)), HAIR, None)


def draw_micro(c, spec):
    """Kolo (délka ≥ 1,5 m) nebo koloběžka, kola i jezdec v body.png, bez wheel.png a světel."""
    S = SS
    bike = c.L >= 1.5
    tire = (28, 28, 32, 255)
    if bike:
        # kola jako tenké pneu (shora úzké), blatníky v laku
        for a, b in ((0.56, 0.98), (-0.98, -0.56)):
            c.rect(a, b, -0.16, 0.16, col=tire, rad=0.16)
            c.rect(a + 0.08, b - 0.08, -0.08, 0.08, paint=P_MID, rad=0.08)
        # rám
        c.rect(-0.60, 0.62, -0.12, 0.12, col=OUT, rad=0.12)
        c.rect(-0.58, 0.60, -0.08, 0.08, paint=P_TOP, rad=0.08)
        # sedlo, nosič u cruiseru
        c.rect(-0.30, -0.16, -0.22, 0.22, col=DARK, rad=0.2)
        if spec.get("cruiser"):
            c.rect(-0.62, -0.34, -0.34, 0.34, paint=P_SIDE, rad=0.1)
            c.rect(-0.60, -0.36, -0.30, 0.30, col=DARK)
            c.rect(-0.58, -0.38, -0.26, 0.26, paint=P_SIDE)
        # řídítka (cruiser širší, zahnutá)
        bw = 0.95 if spec.get("cruiser") else 0.85
        c.rect(0.50, 0.55, -bw, bw, col=DARK, rad=0.2)
        rider(c, 0.06, 0.53, helmet=True, half=0.88)
    else:
        # koloběžka: deska v laku, malá kola, sloupek a řídítka
        for a, b in ((0.74, 0.98), (-0.98, -0.76)):
            c.rect(a, b, -0.20, 0.20, col=tire, rad=0.20)
        c.rect(-0.80, 0.50, -0.44, 0.44, col=OUT, rad=0.30)
        c.rect(-0.78, 0.48, -0.38, 0.38, paint=P_MID, rad=0.26)
        c.rect(-0.70, 0.40, -0.24, 0.24, col=(52, 54, 60, 255), rad=0.2)
        c.rect(0.50, 0.80, -0.10, 0.10, paint=P_TOP)
        c.rect(0.70, 0.76, -0.90, 0.90, col=DARK, rad=0.3)
        rider(c, -0.02, 0.72, helmet=True, half=0.92)
    body = c.body.resize((c.cw, c.ch), Image.LANCZOS)
    m = c.mask.resize((c.cw, c.ch), Image.LANCZOS)
    return {"body": body, "paint_mask": Image.merge("LA", (m, body.getchannel("A")))}


def draw_wheel(L, W):
    wl, ww = wheel_size(L, W)
    w, h = max(round(ww * PX_M), 4), max(round(wl * PX_M), 6)
    S = SS
    im = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w * S - 1, h * S - 1], radius=min(w, h) * S * 0.28, fill=(30, 30, 34, 255))
    # vzorek běhounu
    for k in range(1, 7):
        y = h * S * k / 7
        d.line([(0.6 * S, y), (w * S - 0.6 * S, y)], fill=(16, 16, 19, 255), width=max(S // 2, 1))
    # světlý disk (hra ho tónuje barvou kol z garáže)
    d.rounded_rectangle([w * S * 0.24, h * S * 0.22, w * S * 0.76, h * S * 0.78], radius=w * S * 0.12, fill=(214, 216, 222, 255))
    d.rounded_rectangle([w * S * 0.36, h * S * 0.42, w * S * 0.64, h * S * 0.58], radius=w * S * 0.06, fill=(150, 154, 162, 255))
    return im.resize((w, h), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("ids", nargs="*")
    a = ap.parse_args()
    for cid in a.ids or CARS:
        res = draw_car(cid, CARS[cid])
        d = os.path.join(a.out, cid)
        os.makedirs(d, exist_ok=True)
        for k, im in res.items():
            im.save(os.path.join(d, k + ".png"), optimize=True)
        print(cid, res["body"].size, "kolo", res["wheel"].size if "wheel" in res else "-")


if __name__ == "__main__":
    main()
