#!/usr/bin/env python3
"""GTT oprava 3: amnh (seed 221, CPW fasáda) – zamazání podpisu v rohu, ořez 1080×1350, 256 barev.
  python3 post_fix3.py SRC_PNG OUT_PNG"""
import sys, os, numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).copy()
road = np.median(a[1300:1330, 950:1020].reshape(-1, 3), axis=0).astype(np.uint8)
a[1330:, 1020:] = road   # podpis vpravo dole na silnici
im = Image.fromarray(a); w, h = im.size; l, t = (w - 1080) // 2, (h - 1350) // 2
os.makedirs(os.path.dirname(sys.argv[2]), exist_ok=True)
im.crop((l, t, l + 1080, t + 1350)).quantize(256, method=Image.Quantize.MEDIANCUT).save(sys.argv[2], optimize=True)
