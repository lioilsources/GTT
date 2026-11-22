#!/usr/bin/env python3
"""GTT style board přes ComfyUI (lokální ComfyUI), Qwen-Image fp8.
Hotové PNG přeskakuje, workflow (API JSON) ukládá vedle obrázku kvůli reprodukci.
  python3 run_board.py jobs.jsonl --out png
"""
import argparse, json, os, sys, time, urllib.error, urllib.parse, urllib.request

BASE = "http://127.0.0.1:8188"


def wf(j, prefix):
    return {
        "u": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_fp8_e4m3fn.safetensors", "weight_dtype": "default"}},
        "c": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors", "type": "qwen_image"}},
        "v": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_vae.safetensors"}},
        "ms": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["u", 0], "shift": 3.1}},
        "p": {"class_type": "CLIPTextEncode", "inputs": {"text": j["prompt"], "clip": ["c", 0]}},
        "n": {"class_type": "CLIPTextEncode", "inputs": {"text": j["neg"], "clip": ["c", 0]}},
        "l": {"class_type": "EmptySD3LatentImage", "inputs": {"width": j["w"], "height": j["h"], "batch_size": 1}},
        "k": {"class_type": "KSampler", "inputs": {"seed": j["seed"], "steps": 24, "cfg": 3.0, "sampler_name": "euler",
              "scheduler": "simple", "denoise": 1.0, "model": ["ms", 0], "positive": ["p", 0],
              "negative": ["n", 0], "latent_image": ["l", 0]}},
        "d": {"class_type": "VAEDecode", "inputs": {"samples": ["k", 0], "vae": ["v", 0]}},
        "s": {"class_type": "SaveImage", "inputs": {"images": ["d", 0], "filename_prefix": prefix}},
    }


def call(path, body=None):
    wait = 10
    while True:
        try:
            req = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body else None,
                                         headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
            if isinstance(e, urllib.error.HTTPError):
                raise
            print(json.dumps({"comfy_down": str(e), "retry_s": wait}), flush=True)
            time.sleep(wait)
            wait = min(wait * 2, 300)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs")
    ap.add_argument("--out", required=True)
    ap.add_argument("--depth", type=int, default=3)
    a = ap.parse_args()
    jobs = [json.loads(l) for l in open(a.jobs) if l.strip()]
    todo = [j for j in jobs if not os.path.exists(os.path.join(a.out, j["name"] + ".png"))]
    print(json.dumps({"todo": len(todo), "skipped": len(jobs) - len(todo)}), flush=True)
    pending, done, failed, t0 = {}, 0, 0, time.time()
    it, exhausted = iter(todo), False
    while pending or not exhausted:
        while not exhausted and len(pending) < a.depth:
            j = next(it, None)
            if j is None:
                exhausted = True
                break
            w = wf(j, "gtt_styleboard/" + j["name"].replace("/", "_"))
            try:
                r = json.loads(call("/prompt", {"prompt": w}))
                pending[r["prompt_id"]] = (j, w, time.time())
            except Exception as e:
                print(json.dumps({"name": j["name"], "error": str(e)}), flush=True)
                failed += 1
        time.sleep(0.5)
        for pid in list(pending):
            j, w, ts = pending[pid]
            h = json.loads(call("/history/" + pid)).get(pid)
            if not h:
                if time.time() - ts > 1200:
                    del pending[pid]
                    print(json.dumps({"name": j["name"], "error": "timeout"}), flush=True)
                    failed += 1
                continue
            del pending[pid]
            imgs = [i for o in h.get("outputs", {}).values() for i in o.get("images", [])]
            if not imgs:
                print(json.dumps({"name": j["name"], "error": "no output", "status": h.get("status")}), flush=True)
                failed += 1
                continue
            i = imgs[0]
            q = urllib.parse.urlencode({"filename": i["filename"], "subfolder": i["subfolder"], "type": i["type"]})
            dst = os.path.join(a.out, j["name"] + ".png")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with urllib.request.urlopen(BASE + "/view?" + q, timeout=60) as r, open(dst + ".tmp", "wb") as f:
                f.write(r.read())
            os.replace(dst + ".tmp", dst)
            with open(dst[:-4] + ".workflow.json", "w") as f:
                json.dump(w, f, indent=1)
            done += 1
            print(json.dumps({"done": done, "of": len(todo), "name": j["name"],
                              "s_per_img": round((time.time() - t0) / done, 1)}), flush=True)
    print(json.dumps({"images": {"ok": done, "failed": failed}}), flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
