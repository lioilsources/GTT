#!/usr/bin/env python3
"""Skiny herních ploch miniher M2 (docs/art-requests.md kap. 5), procedurálně (PIL + numpy, bez modelu).
Plochý vektor (styl A) s jemnou strukturou materiálu, 1080×1920 na výšku, pohled shora, bez textu a značek.
Klienti je zatím nepoužívají (do zásoby); názvy podle `specs/minigames/<id>.md`.

  assets/minigames/
    karty_stul.png   plsťový stůl pro karetní hry (prsi, durak, oko, srdce, prase)
    karty_rub.png    rub karty 512×768, fiktivní „Metropole“ (panorama a geometrie, bez písmen)
    kostky.png       dřevěný stůl s plstěnou miskou na kostky (kostky, desetitisic)
    sachy.png        šachovnice 8×8 na dřevě (sachy, dama, reversi jako podklad)
    kulecnik.png     kulečníkový stůl shora
    bowling.png      bowlingová dráha shora
    hokej.png        stůl vzdušného hokeje
    minigolf.png     dráha minigolfu s motivem NYC (taxík, most, vodní hydrant)
    stickball.png    newyorská ulice shora s křídovými metami
    doubledutch.png  chodník a hřiště s křídovým kruhem
  python3 tools/art/minigame_skins.py --out assets/minigames
"""
import argparse, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H, SS = 1080, 1920, 2
OUT = (27, 27, 31, 255)


def hx(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def mix(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


class C:
    def __init__(self, w=W, h=H, bg=(0, 0, 0, 255)):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w * SS, h * SS), bg)
        self.d = ImageDraw.Draw(self.im)

    def b(self, x0, y0, x1, y1):
        return [x0 * SS, y0 * SS, x1 * SS, y1 * SS]

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle(self.b(x0, y0, x1, y1), fill=c)

    def rr(self, x0, y0, x1, y1, r, c, outline=None, ow=0):
        self.d.rounded_rectangle(self.b(x0, y0, x1, y1), radius=r * SS, fill=c, outline=outline, width=ow * SS)

    def ell(self, x0, y0, x1, y1, c, outline=None, ow=0):
        self.d.ellipse(self.b(x0, y0, x1, y1), fill=c, outline=outline, width=ow * SS)

    def poly(self, pts, c):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=c)

    def line(self, pts, w, c):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=c, width=int(w * SS))

    def out(self):
        return self.im.resize((self.w, self.h), Image.LANCZOS).convert("RGB")


def grain(im, seed, amt=10, sx=1.0, sy=8.0):
    """Jemná struktura materiálu (protažený šum), ploché tóny zůstanou."""
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, (im.height // 4 + 1, im.width // 4 + 1)).astype(np.float32)
    nimg = Image.fromarray(((n * 40) + 128).clip(0, 255).astype(np.uint8)).resize(im.size, Image.BICUBIC)
    nimg = nimg.filter(ImageFilter.GaussianBlur((sx, sy)))
    a = np.asarray(im).astype(np.float32)
    g = (np.asarray(nimg).astype(np.float32) - 128) / 128 * amt
    return Image.fromarray((a + g[..., None]).clip(0, 255).astype(np.uint8))


def wood(c, x0, y0, x1, y1, base="#9A6A3E", plank=120, seed=1, vertical=True):
    rng = np.random.default_rng(seed)
    tones = [hx(base), mix(hx(base), 0.92), mix(hx(base), 1.06), mix(hx(base), 0.97)]
    if vertical:
        x = x0
        while x < x1:
            c.rect(x, y0, min(x + plank, x1), y1, tones[rng.integers(4)])
            c.rect(x, y0, x + 2, y1, mix(hx(base), 0.75))
            x += plank
    else:
        y = y0
        while y < y1:
            c.rect(x0, y, x1, min(y + plank, y1), tones[rng.integers(4)])
            c.rect(x0, y, x1, y + 2, mix(hx(base), 0.75))
            y += plank


# ------------------------------------------------------------------ plochy
def karty_stul():
    c = C(bg=hx("#2A1E1A"))
    wood(c, 0, 0, W, H, "#4A3022", 140, 11)
    c.rr(60, 140, W - 60, H - 140, 420, hx("#6B4426"))           # dřevěný lem
    c.rr(100, 180, W - 100, H - 180, 390, hx("#1F6B4A"))          # plsť
    c.rr(150, 230, W - 150, H - 230, 350, None, outline=mix(hx("#1F6B4A"), 1.2), ow=4)
    return grain(c.out(), 21, 6, 2, 2)


def karty_rub():
    c = C(512, 768, bg=hx("#F5EBDA"))
    c.rr(16, 16, 496, 752, 36, hx("#193B62"))
    c.rr(36, 36, 476, 732, 24, None, outline=hx("#F2BD2C"), ow=4)
    # kosočtverečný vzor
    for y in range(60, 720, 48):
        for x in range(60, 460, 48):
            off = 24 if (y // 48) % 2 else 0
            cx, cy = x + off, y
            if 50 < cx < 462:
                c.poly([(cx, cy - 12), (cx + 12, cy), (cx, cy + 12), (cx - 12, cy)], hx("#2E465D"))
    # střední medailon: panorama v kruhu (stejné nahoře i dole otočené = karta bez orientace)
    for flip in (False, True):
        m = C(512, 384, bg=(0, 0, 0, 0))
        m.ell(136, 72, 376, 312, hx("#F5EBDA"))
        m.ell(150, 86, 362, 298, hx("#D7263D"))
        bx = 168
        for w_, h_ in ((30, 70), (24, 110), (36, 90), (20, 150), (34, 80), (28, 120), (26, 60)):
            m.rect(bx, 250 - h_, bx + w_, 250, hx("#193B62"))
            bx += w_ + 2
        m.rect(170, 248, 342, 262, hx("#193B62"))
        part = m.im.crop((0, 0, 512 * SS, 192 * SS))
        if flip:
            part = part.rotate(180)
            c.im.alpha_composite(part, (0, 384 * SS))
        else:
            c.im.alpha_composite(part, (0, 192 * SS))
    return c.out()


def kostky():
    c = C()
    wood(c, 0, 0, W, H, "#9A6A3E", 135, 12)
    c.rr(120, 520, W - 120, H - 520, 60, hx("#6B4426"))
    c.rr(150, 550, W - 150, H - 550, 44, hx("#7A1E2A"))
    c.rr(170, 570, W - 170, H - 570, 36, None, outline=mix(hx("#7A1E2A"), 1.25), ow=3)
    return grain(c.out(), 22, 9, 1, 10)


def sachy():
    c = C()
    wood(c, 0, 0, W, H, "#7A5232", 150, 13)
    s = 110
    x0, y0 = (W - 8 * s) // 2, (H - 8 * s) // 2
    c.rect(x0 - 36, y0 - 36, x0 + 8 * s + 36, y0 + 8 * s + 36, hx("#3E2616"))
    c.rect(x0 - 30, y0 - 30, x0 + 8 * s + 30, y0 + 8 * s + 30, hx("#5A3A22"))
    for i in range(8):
        for j in range(8):
            c.rect(x0 + i * s, y0 + j * s, x0 + (i + 1) * s, y0 + (j + 1) * s, hx("#EBD9B4") if (i + j) % 2 == 0 else hx("#9C6B43"))
    return grain(c.out(), 23, 8, 1, 9)


def kulecnik():
    c = C(bg=hx("#2A1E1A"))
    wood(c, 0, 0, W, H, "#3E2A20", 160, 14)
    rx0, ry0, rx1, ry1 = 110, 120, W - 110, H - 120
    c.rr(rx0, ry0, rx1, ry1, 70, hx("#5A3220"))                     # mantinel
    cx0, cy0, cx1, cy1 = rx0 + 70, ry0 + 70, rx1 - 70, ry1 - 70
    c.rect(cx0, cy0, cx1, cy1, hx("#1D6E8C"))                        # sukno (modrozelené)
    c.rect(cx0, cy0, cx1, cy0 + 14, mix(hx("#1D6E8C"), 0.8))
    c.rect(cx0, cy0, cx0 + 14, cy1, mix(hx("#1D6E8C"), 0.8))
    for x, y in ((cx0, cy0), (cx1, cy0), (cx0, (cy0 + cy1) / 2), (cx1, (cy0 + cy1) / 2), (cx0, cy1), (cx1, cy1)):
        c.ell(x - 38, y - 38, x + 38, y + 38, hx("#111114"))
    for k in range(1, 4):  # diamanty na mantinelu
        for y in (ry0 + 35, ry1 - 35):
            x = cx0 + (cx1 - cx0) * k / 4
            c.poly([(x, y - 9), (x + 9, y), (x, y + 9), (x - 9, y)], hx("#E8DCC0"))
        for x in (rx0 + 35, rx1 - 35):
            for half in (0, 1):
                y = cy0 + (cy1 - cy0) / 2 * half + (cy1 - cy0) / 2 * k / 4
                c.poly([(x, y - 9), (x + 9, y), (x, y + 9), (x - 9, y)], hx("#E8DCC0"))
    hy = cy0 + (cy1 - cy0) * 0.75
    c.line([(cx0, hy), (cx1, hy)], 2, mix(hx("#1D6E8C"), 1.3))
    c.ell(W / 2 - 6, cy0 + (cy1 - cy0) * 0.25 - 6, W / 2 + 6, cy0 + (cy1 - cy0) * 0.25 + 6, mix(hx("#1D6E8C"), 1.35))
    return grain(c.out(), 24, 5, 2, 2)


def bowling():
    c = C(bg=hx("#2B2B33"))
    lx0, lx1 = 250, W - 250
    c.rect(lx0 - 70, 0, lx0, H, hx("#4A4A55"))                       # žlaby
    c.rect(lx1, 0, lx1 + 70, H, hx("#4A4A55"))
    wood(c, lx0, 0, lx1, H, "#D9B57E", 30, 15)
    # šipky a tečky (rozpoznávací značky)
    for k in range(7):
        x = lx0 + (lx1 - lx0) * (k + 1) / 8
        y = 1250 - abs(3 - k) * 40
        c.poly([(x, y - 34), (x + 14, y + 10), (x - 14, y + 10)], hx("#3C2A1C"))
        c.ell(x - 7, 1560 - 7, x + 7, 1560 + 7, hx("#3C2A1C"))
    c.rect(lx0, 1780, lx1, 1788, hx("#3C2A1C"))                      # čára přešlapu
    # místa kuželek nahoře (trojúhelník 1-2-3-4)
    for row in range(4):
        for i in range(row + 1):
            x = W / 2 + (i - row / 2) * 92
            y = 150 + (3 - row) * 80
            c.ell(x - 14, y - 14, x + 14, y + 14, mix(hx("#D9B57E"), 0.8))
    c.rect(lx0 - 70, 0, lx1 + 70, 40, hx("#1A1A20"))
    return grain(c.out(), 25, 7, 1, 14)


def hokej():
    c = C(bg=hx("#193B62"))
    c.rr(70, 90, W - 70, H - 90, 120, hx("#2E465D"))
    c.rr(110, 130, W - 110, H - 130, 90, hx("#F1F3F5"))
    for y in range(170, H - 160, 34):                                 # dírky vzduchu
        for x in range(150, W - 140, 34):
            c.ell(x - 2, y - 2, x + 2, y + 2, hx("#C9D0D8"))
    red, blue = hx("#D7263D"), hx("#2F6FB0")
    c.rect(110, H / 2 - 5, W - 110, H / 2 + 5, red)
    c.ell(W / 2 - 150, H / 2 - 150, W / 2 + 150, H / 2 + 150, None, outline=red, ow=10)
    for y, col in ((520, blue), (H - 520, blue)):
        c.rect(110, y - 4, W - 110, y + 4, col)
    for y0, y1 in ((130, 300), (H - 300, H - 130)):
        c.d.arc(c.b(W / 2 - 200, y0 - 170 if y0 == 130 else y0, W / 2 + 200, y1 if y0 == 130 else y1 + 170),
                0 if y0 == 130 else 180, 180 if y0 == 130 else 360, fill=red, width=8 * SS)
    for y in (110, H - 150):                                          # branky
        c.rr(W / 2 - 180, y, W / 2 + 180, y + 40, 10, hx("#111114"))
    return c.out()


def minigolf():
    c = C(bg=hx("#8D8780"))
    for y in range(0, H, 40):                                         # cihlové okolí
        off = 60 if (y // 40) % 2 else 0
        for x in range(-off, W, 120):
            c.rect(x + 2, y + 2, x + 118, y + 38, hx("#A84B4A") if (x // 120 + y // 40) % 3 else hx("#C75A56"))
    path = [(540, 1760), (540, 1350), (320, 1150), (320, 760), (720, 560), (720, 300)]
    for w_, col in ((290, hx("#F5EBDA")), (250, hx("#5DA348"))):     # okraj a trávník dráhy
        c.line(path, w_, col)
        for x, y in path:
            c.ell(x - w_ / 2, y - w_ / 2, x + w_ / 2, y + w_ / 2, col)
    # překážky: žlutý taxík shora, ocelový mostek, hydrant
    c.rr(430, 1280, 650, 1380, 30, hx("#F2BD2C"))
    c.rr(475, 1295, 605, 1365, 20, hx("#2E465D"))
    c.rect(500, 1270, 580, 1290, hx("#1D1A1A"))
    for x in (380, 460):
        c.rect(x - 8, 900, x + 8, 1040, hx("#5678A3"))
    c.rect(250, 960, 400, 980, hx("#5678A3"))
    c.ell(735, 690, 795, 750, hx("#D7263D"))
    c.ell(752, 707, 778, 733, mix(hx("#D7263D"), 0.7))
    # jamka s vlajkou (prázdná vlajka) a odpaliště
    c.ell(700, 280, 740, 320, hx("#111114"))
    c.rect(718, 180, 724, 300, hx("#F5EBDA"))
    c.poly([(724, 180), (800, 205), (724, 230)], hx("#D7263D"))
    c.rr(500, 1700, 580, 1740, 8, hx("#F5EBDA"))
    return grain(c.out(), 26, 5, 2, 2)


def stickball():
    c = C(bg=hx("#A49E9A"))
    c.rect(0, 0, 200, H, hx("#DEC3B4"))                               # chodníky
    c.rect(W - 200, 0, W, H, hx("#DEC3B4"))
    c.rect(196, 0, 214, H, hx("#8F8985"))
    c.rect(W - 214, 0, W - 196, H, hx("#8F8985"))
    for y in range(0, H, 180):                                        # spáry chodníku
        c.rect(0, y, 196, y + 3, hx("#C9AFA0"))
        c.rect(W - 196, y, W, y + 3, hx("#C9AFA0"))
    # křídové mety: kanál jako domácí meta dole, mety v kosočtverci
    chalk = hx("#F5F2EA")
    hpx, hpy = W / 2, 1580
    c.ell(hpx - 60, hpy - 60, hpx + 60, hpy + 60, hx("#5E5860"))
    for k in range(-3, 4):
        c.rect(hpx - 50, hpy + k * 14 - 3, hpx + 50, hpy + k * 14 + 3, hx("#4A4542"))
    for x, y in ((W / 2 + 300, 1280), (W / 2, 980), (W / 2 - 300, 1280)):
        c.rr(x - 40, y - 40, x + 40, y + 40, 6, None, outline=chalk, ow=6)
    c.line([(hpx, hpy), (W / 2 + 300, 1280), (W / 2, 980), (W / 2 - 300, 1280), (hpx, hpy)], 4, chalk)
    # zaparkovaná auta u obrubníků (siluety shora)
    for x, y, col in ((222, 260, "#2F6FB0"), (222, 600, "#C75A56"), (W - 312, 380, "#F2BD2C"), (W - 312, 1760, "#46A06E")):
        c.rr(x, y, x + 90, y + 210, 24, hx(col))
        c.rr(x + 12, y + 60, x + 78, y + 140, 12, hx("#2C3848"))
    return grain(c.out(), 27, 6, 3, 3)


def doubledutch():
    c = C(bg=hx("#8E8A86"))
    for y in range(0, H, 240):                                        # betonové desky hřiště
        for x in range(0, W, 270):
            c.rect(x + 2, y + 2, x + 268, y + 238, hx("#A49E9A") if (x // 270 + y // 240) % 2 else hx("#9A948F"))
    c.rect(0, 0, W, 140, hx("#A84B4A"))                               # cihlová zeď nahoře
    for y in range(0, 140, 28):
        off = 40 if (y // 28) % 2 else 0
        for x in range(-off, W, 80):
            c.rect(x + 2, y + 2, x + 78, y + 26, hx("#C75A56"))
    chalk = [hx("#F5F2EA"), hx("#F2BD2C"), hx("#E67896"), hx("#5DA9E9")]
    cx, cy = W / 2, H / 2 + 100
    for k, r in enumerate((330, 300)):
        c.ell(cx - r, cy - r, cx + r, cy + r, None, outline=chalk[k], ow=8)
    for x, y, col in ((cx - 300, cy - 420, 2), (cx + 300, cy - 420, 3)):  # místa točících
        c.rr(x - 50, y - 50, x + 50, y + 50, 8, None, outline=chalk[col], ow=6)
    for i in range(8):                                                # křídové hvězdičky a tečky okolo
        a = i * math.pi / 4
        x, y = cx + 460 * math.cos(a), cy + 600 * math.sin(a)
        c.ell(x - 14, y - 14, x + 14, y + 14, chalk[i % 4])
    return grain(c.out(), 28, 6, 3, 3)


SKINS = dict(karty_stul=karty_stul, karty_rub=karty_rub, kostky=kostky, sachy=sachy, kulecnik=kulecnik,
             bowling=bowling, hokej=hokej, minigolf=minigolf, stickball=stickball, doubledutch=doubledutch)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("ids", nargs="*")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for k in a.ids or SKINS:
        im = SKINS[k]()
        im.quantize(256, method=Image.Quantize.MEDIANCUT).save(os.path.join(a.out, f"{k}.png"), optimize=True)
        print(k, im.size)


if __name__ == "__main__":
    main()
