#!/usr/bin/env python3
"""GTT dávka gtt-npc-cities (docs/art-requests.md kap. 8): šest NPC v podobě Prahy, Tokia a Moskvy.
Styl a ořez jako várka 1 (make_batch1.py): styl A, manga, šedé pozadí (alfa pak BiRefNet, run_rmbg.py).
Stejný popis + seed na postavu a město, mění se jen výraz. Dospělí, fiktivní, současné oblečení, bez textu,
značek a politických symbolů. Vypíše JSONL pro run_board.py.
  python3 make_npc_cities.py style|all"""
import json, sys

A = ("flat vector illustration, cel shading with two or three flat tones per surface, thin dark outline, "
     "clean geometric shapes, no gradients, crisp edges")
NOTXT = "no text, no letters, no words, no signs, no logos, no brand names, no badges, no insignia, no symbols"
NEG = ("text, letters, words, caption, name, watermark, signature, logo, brand name, license plate, badge, insignia, "
       "emblem, flag, political symbol, photo, photorealistic, blurry, low quality, deformed, extra limbs, extra fingers, "
       "child, teenager, nsfw, nudity, cleavage, caricature, stereotype, traditional costume, kimono, folk costume, "
       "ushanka, uniform patch")
EXPR = {"happy": "big warm genuine smile", "neutral": "calm neutral expression, slight smile",
        "annoyed": "annoyed expression, raised eyebrow, slight frown, unimpressed"}
STYLE = f"anime manga character art, attractive, clearly adult, fully clothed, dignified. Style: {A}, harmonious palette"

NPC = {
 "prague": {
  "maya": "Maya, a 24-year-old adult Czech woman, lifestyle influencer, light brown straight hair in a loose high ponytail, "
          "green-grey eyes, light freckles, oversized beige hoodie under a light olive utility jacket, small silver earrings",
  "theo": "Theo, a 27-year-old adult Czech man, hipster barista, tousled dark blond hair, neat short beard, thin round metal "
          "glasses, chunky oatmeal knitted sweater under a canvas apron",
  "ray":  "Ray, a 58-year-old Czech man, veteran Prague taxi driver, short grey hair, thick grey moustache, weathered kind "
          "face with crow's feet, dark blue zip-up jacket over a checked flannel shirt",
  "iris": "Iris, a 29-year-old adult Czech woman, bookworm, long straight light brown hair with a fringe, rectangular "
          "glasses, chunky cream cable-knit sweater, the strap of a plain canvas tote bag on her shoulder",
  "jules": "Jules, a 31-year-old adult Czech man, street musician, shaggy light brown hair, light stubble, guitar strap "
           "across the chest, worn brown corduroy jacket, grey wool scarf",
  "dana": "Dana, a 38-year-old adult Czech woman, busy corporate manager, short ash-blonde bob, charcoal tailored blazer "
          "over a white blouse, holding a smartphone",
 },
 "tokyo": {
  "maya": "Maya, a 24-year-old adult Japanese woman, fashion influencer, black hair with soft pastel pink ends in a half-up "
          "style, layered contemporary streetwear: oversized cream shirt over a black turtleneck and a lavender cardigan, "
          "small silver ear cuffs",
  "theo": "Theo, a 27-year-old adult Japanese man, barista, neat short black hair with a side part, clean-shaven, plain "
          "white t-shirt under a dark brown canvas apron, minimalist look",
  "ray":  "Ray, a 58-year-old Japanese man, veteran Tokyo taxi driver, short neat grey hair, kind calm face, plain navy "
          "driver's uniform jacket with white shirt and dark tie, white cotton gloves, plain navy driver's cap",
  "iris": "Iris, a 29-year-old adult Japanese woman, bookworm, neat chin-length black bob, thin round glasses, soft beige "
          "cardigan over a white collared blouse",
  "jules": "Jules, a 31-year-old adult Japanese man, street musician, medium-length dark brown wavy hair, light stubble, "
           "black denim jacket over a grey hoodie, guitar strap across the chest",
  "dana": "Dana, a 38-year-old adult Japanese woman, busy corporate manager, sleek shoulder-length black hair, dark navy "
          "tailored suit jacket over a white blouse, small pearl earrings, holding a smartphone",
 },
 "moscow": {
  "maya": "Maya, a 24-year-old adult Russian woman, lifestyle influencer, long straight platinum blonde hair, blue-grey "
          "eyes, polished makeup, camel wool coat, chunky gold chain necklace, sunglasses pushed up on her head",
  "theo": "Theo, a 27-year-old adult Russian man, barista, light brown hair under a dark grey beanie, trimmed beard, black "
          "t-shirt under a dark apron, abstract geometric line tattoos on his forearms",
  "ray":  "Ray, a 58-year-old Russian man, veteran Moscow taxi driver, short grey hair under a flat cap, grey stubble, "
          "broad kind face, black leather jacket",
  "iris": "Iris, a 29-year-old adult Russian woman, bookworm, dark blonde hair in a long braid over the shoulder, thin "
          "glasses, long charcoal wool coat, thick burgundy knitted scarf",
  "jules": "Jules, a 31-year-old adult Russian man, street musician, curly chestnut hair, short beard, dark green parka, "
           "guitar strap across the chest",
  "dana": "Dana, a 38-year-old adult Russian woman, busy corporate manager, dark brown hair in a sleek low bun, elegant "
          "black wool coat over a grey suit, small gold earrings, holding a smartphone",
 },
}
SEED0 = {"prague": 1101, "tokyo": 1201, "moscow": 1301}
IDS = ["maya", "theo", "ray", "iris", "jules", "dana"]
out = []


def job(name, w, h, seed, prompt):
    out.append({"name": name, "w": w, "h": h, "seed": seed, "model": "qwen", "prompt": prompt, "neg": NEG})


def person(city, nid):
    desc, seed = NPC[city][nid], SEED0[city] + IDS.index(nid)
    for ex, ed in EXPR.items():
        job(f"npc/{city}/{nid}_{ex}", 1024, 1024, seed,
            f"head and shoulders portrait of {desc}, {ed}, facing the viewer, centered, "
            f"plain flat light grey background. {STYLE}. {NOTXT}.")
    job(f"npc/{city}/{nid}_bust", 768, 1280, seed,
        f"waist-up character card of {desc}, {EXPR['happy']}, confident pose, centered, "
        f"plain flat light grey background. {STYLE}. {NOTXT}.")


mode = sys.argv[1]
for city in NPC:
    for nid in (["maya"] if mode == "style" else IDS):
        person(city, nid)
for j in out:
    print(json.dumps(j))
