#!/usr/bin/env python3
"""Odstranění pozadí (BiRefNet-general, MIT/Apache) přes ComfyUI-RMBG. Vstupní PNG zkopíruje do input/,
výsledek (RGBA) uloží do --out se stejnou relativní cestou. Hotové přeskakuje.
  python3 run_rmbg.py --src png/npc --out alpha/npc --comfy-input /path/to/ComfyUI/input
"""
import argparse, json, os, shutil, sys, time, urllib.parse, urllib.request

BASE = "http://127.0.0.1:8188"


def call(path, body=None):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--comfy-input", required=True)
    a = ap.parse_args()
    files = sorted(os.path.relpath(os.path.join(d, f), a.src) for d, _, fs in os.walk(a.src) for f in fs if f.endswith(".png"))
    todo = [f for f in files if not os.path.exists(os.path.join(a.out, f))]
    print(json.dumps({"todo": len(todo), "skipped": len(files) - len(todo)}), flush=True)
    stage = os.path.join(a.comfy_input, "gtt_rmbg")
    os.makedirs(stage, exist_ok=True)
    ok = failed = 0
    for rel in todo:
        flat = rel.replace("/", "_")
        shutil.copy(os.path.join(a.src, rel), os.path.join(stage, flat))
        wf = {
            "i": {"class_type": "LoadImage", "inputs": {"image": f"gtt_rmbg/{flat}"}},
            "r": {"class_type": "BiRefNetRMBG", "inputs": {"image": ["i", 0], "model": "BiRefNet-general",
                  "sensitivity": 1.0, "mask_blur": 0, "mask_offset": 0, "invert_output": False,
                  "refine_foreground": True, "background": "Alpha"}},
            "s": {"class_type": "SaveImage", "inputs": {"images": ["r", 0], "filename_prefix": "gtt_rmbg/" + flat[:-4]}},
        }
        try:
            pid = call("/prompt", {"prompt": wf})["prompt_id"]
            t0 = time.time()
            while True:
                h = call("/history/" + pid).get(pid)
                if h or time.time() - t0 > 600:
                    break
                time.sleep(0.5)
            imgs = [i for o in (h or {}).get("outputs", {}).values() for i in o.get("images", [])]
            if not imgs:
                raise RuntimeError(json.dumps((h or {}).get("status")))
            i = imgs[0]
            q = urllib.parse.urlencode({"filename": i["filename"], "subfolder": i["subfolder"], "type": i["type"]})
            dst = os.path.join(a.out, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with urllib.request.urlopen(BASE + "/view?" + q, timeout=60) as r, open(dst + ".tmp", "wb") as f:
                f.write(r.read())
            os.replace(dst + ".tmp", dst)
            ok += 1
            print(json.dumps({"done": rel}), flush=True)
        except Exception as e:
            failed += 1
            print(json.dumps({"name": rel, "error": str(e)}), flush=True)
        finally:
            os.remove(os.path.join(stage, flat))
    print(json.dumps({"images": {"ok": ok, "failed": failed}}), flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
