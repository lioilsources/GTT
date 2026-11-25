#!/usr/bin/env python3
"""Web icons from the shared app icon (specs/appicon.md "W").

Reads assets/ui/app_icon/<mode>.png (1024², opaque) and design/tokens.json and writes
web/public/icons/<mode>-<size>.png plus web/public/manifest.webmanifest. The output is committed;
rerun after the art or the tokens change:  (cd web && npm run icons)   [needs Pillow]
"""
import json
from pathlib import Path

from PIL import Image

WEB = Path(__file__).resolve().parent.parent
ROOT = WEB.parent
SRC = ROOT / "assets" / "ui" / "app_icon"
OUT = WEB / "public" / "icons"

MODES = ["day", "night", "sunset", "teal", "japan"]
DEFAULT = "sunset"
# Every mode: tab icon and apple-touch-icon (also the picker thumbnail). Default only: manifest sizes.
SIZES = [32, 180]
MANIFEST_SIZES = [192, 512]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for mode in MODES:
        src = Image.open(SRC / f"{mode}.png").convert("RGB")
        for size in SIZES + (MANIFEST_SIZES if mode == DEFAULT else []):
            src.resize((size, size), Image.LANCZOS).save(OUT / f"{mode}-{size}.png", optimize=True)

    background = json.loads((ROOT / "design" / "tokens.json").read_text("utf-8"))["color"]["ui"]["background"]
    manifest = {
        "name": "Metropole",
        "short_name": "Metropole",
        "start_url": ".",
        "scope": ".",
        "display": "standalone",
        "orientation": "portrait",
        "background_color": background,
        "theme_color": background,
        "icons": [
            {"src": f"icons/{DEFAULT}-{size}.png", "sizes": f"{size}x{size}", "type": "image/png", "purpose": purpose}
            for size in MANIFEST_SIZES
            for purpose in ("any", "maskable")
        ],
    }
    (WEB / "public" / "manifest.webmanifest").write_text(json.dumps(manifest, indent=2) + "\n", "utf-8")


if __name__ == "__main__":
    main()
