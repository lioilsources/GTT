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
}


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
    if cls == "bus":
        us = (0.60, -0.70)
    else:
        us = (AXLE, -AXLE)
    wl, ww = wheel_size(c.L, c.W)
    return [(u, s * WHEEL_V) for u in us for s in (1, -1)], wl * PX_M * SS, ww * PX_M * SS


def draw_car(cid, spec):
    c = Car(spec["L"], spec["W"])
    cls = spec["cls"]
    rf, rr = spec["r"]
    police = cls == "police"
    S = SS

    # 1) silueta (alfa), obrys a základní lak
    sil_pts = silhouette(c, rf, rr)
    sil = Image.new("L", c.size, 0)
    ImageDraw.Draw(sil).polygon([c.p(u, v) for u, v in sil_pts], fill=255)
    c.poly(sil_pts, col=OUT)
    inset = 1.6 * S / c.hw  # obrys ~1,6 px
    inner = silhouette(c, max(rf - inset, 0.05), max(rr - inset, 0.05), half_w=1 - inset)
    inner = [(u * (1 - inset * c.hw / c.hl), v) for u, v in inner]
    base = P_MID
    c.poly(inner, paint=base)
    # boční pás tmavší, středový pruh světlejší (dva až tři tóny)
    c.rect(-0.97, 0.97, 0.74, 0.92, paint=P_SIDE)
    c.rect(-0.97, 0.97, -0.92, -0.74, paint=P_SIDE)

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
    elif cls == "van":
        # jen přední sklo, za ním nákladová střecha (lak + žebra)
        c.poly([(cab1, 0.72), (cab1, -0.72), (cab0, -0.84), (cab0, 0.84)], col=GLASS)
        c.poly([(cab1 - 0.02, 0.30), (cab1 - 0.02, 0.12), (cab0 + 0.03, -0.02), (cab0 + 0.03, 0.18)], col=GLASS_HI)
        c.rect(-0.96, 0.55, -0.84, 0.84, paint=P_TOP, rad=0.06)
        u = -0.86
        while u < 0.50:
            c.rect(u, u + 0.025, -0.80, 0.80, paint=P_SIDE)
            u += 0.12

    # 3) detaily třídy
    if cls == "coupe":
        for s in (1, -1):
            for a, b in ((cab1 + 0.02, 0.96), (-0.96, cab0 - 0.02)):
                c.rect(a, b, s * 0.06, s * 0.20, col=(240, 240, 234, 255))
    if cls == "muscle":
        for s in (1, -1):
            c.rect(-0.97, 0.97, s * 0.14, s * 0.30, col=(30, 30, 35, 255))
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
    if spec.get("chrome"):
        # chromová lišta mezi kapotou a maskou
        c.rect(0.93, 0.955, -0.70, 0.70, col=(200, 204, 210, 255))

    # 4) nárazníky a světla
    c.rect(0.955, 1.0, -0.86, 0.86, col=BUMPER, rad=0.10)
    c.rect(-1.0, -0.96, -0.86, 0.86, col=BUMPER, rad=0.10)
    for s in (1, -1):
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
    if not police:
        m = c.mask.resize((c.cw, c.ch), Image.LANCZOS)
        out["paint_mask"] = Image.merge("LA", (m, out["body"].getchannel("A")))
    return out


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
        print(cid, res["body"].size, "kolo", res["wheel"].size)


if __name__ == "__main__":
    main()
