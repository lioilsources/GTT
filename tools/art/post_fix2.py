import sys, os, numpy as np
from PIL import Image
S, OUT = sys.argv[1], sys.argv[2]
def q(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.quantize(256, method=Image.Quantize.MEDIANCUT).save(path, optimize=True)
def pc(src, dst, fix=None):
    im = Image.open(src).convert("RGB")
    if fix: im = fix(im)
    w, h = im.size; l, t = (w - 1080) // 2, (h - 1350) // 2
    q(im.crop((l, t, l + 1080, t + 1350)), dst)
def syn_fix(im):
    a = np.asarray(im).copy()
    paper = np.median(a[1335:1355, 20:600].reshape(-1, 3), axis=0).astype(np.uint8)
    a[1300:, 650:] = paper   # nápis v okraji papíru vpravo dole
    return Image.fromarray(a)
F = f"{S}/fix2/postcards"
pc(f"{F}/nyc/guggenheim_s214.png", f"{OUT}/postcards/nyc/guggenheim.png")
pc(f"{F}/nyc/msg_s211.png", f"{OUT}/postcards/nyc/msg.png")
pc(f"{F}/prague/old_new_synagogue_s214.png", f"{OUT}/postcards/prague/old_new_synagogue.png", syn_fix)
def seamless(path, out, crop):
    im = Image.open(path).convert("RGB"); w, h = im.size; c = int(w * crop)
    a = np.asarray(im.crop((c, c, w - c, h - c)).resize((512, 512), Image.LANCZOS)).astype(np.float32)
    r = np.roll(a, (256, 256), axis=(0, 1))
    x = np.abs(np.arange(512) - 255.5) / 255.5
    wgt = np.clip((1 - np.maximum.outer(x, x)) / 0.35, 0, 1)[..., None]
    q(Image.fromarray((a * wgt + r * (1 - wgt)).round().astype(np.uint8)), out)
seamless(f"{S}/fix2/cities/nyc/asphalt_s413.png", f"{OUT}/cities/nyc/asphalt.png", 0.12)
seamless(f"{S}/fix2/cities/nyc/sidewalk_concrete_s411.png", f"{OUT}/cities/nyc/sidewalk_concrete.png", 0.15)
print("ok")
