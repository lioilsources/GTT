#!/usr/bin/env python3
"""GTT oprava várky 1: pohlednice s textem, synagoga bez kříže, sprity Lidka a chodec kolmo shora."""
import json
B = [json.loads(l) for l in open("batch1.jsonl")]
by = {j["name"]: j for j in B}
out = []
NOTXT_EXTRA = (" Absolutely no lettering, no inscriptions on facades or friezes, no signs, no banners with words; "
               "replace any inscription with plain blank stone.")
for k in ["amnh", "carnegie_hall", "guggenheim", "met_museum", "msg", "federal_hall"]:
    for s in (202, 203):
        j = dict(by[f"postcards/nyc/{k}"]); j["seed"] = s; j["name"] = f"postcards/nyc/{k}_s{s}"
        j["prompt"] += NOTXT_EXTRA; j["neg"] += ", inscription, engraved letters, banner, marquee, signage"
        out.append(j)
syn = dict(by["postcards/prague/old_new_synagogue"])
syn["prompt"] = syn["prompt"].replace(
    "the Gothic Old New Synagogue with its brick gable",
    "the Old New Synagogue in Prague's Jewish Quarter: a medieval Jewish synagogue, a simple stone hall with a tall "
    "steep roof and a stepped serrated brick gable, small Gothic windows, no cross anywhere, no church tower, no spire")
syn["neg"] += ", cross, crucifix, church, christian symbols, spire, bell tower"
for s in (202, 203, 204):
    j = dict(syn); j["seed"] = s; j["name"] = f"postcards/prague/old_new_synagogue_s{s}"; out.append(j)
TOP = ("a top-down game sprite as seen by a drone hovering straight above, camera pointing straight down, "
       "like a 2D top-down racing game such as classic overhead arcade racers, only the roof, windshield, hood and "
       "trunk lid are visible as flat shapes, no wheels visible from the side, no doors visible, perfectly symmetric "
       "left and right, front of the car pointing to the top of the image, centered on a plain flat white background, "
       "light from the top-left, short soft shadow to the bottom-right")
cp = by["test/sprites/coupe_s301"]
for s in (311, 312, 313, 314, 315, 316):
    out.append(dict(cp, seed=s, name=f"test/sprites/lidka_s{s}",
        prompt=f"a small boxy cream-colored 1980s four-door sedan car with a long flat roof, {TOP}. Style: flat vector, "
               "thin dark outline, flat colors, no texture, ochre and cream palette. no text, no license plates."))
    out.append(dict(cp, seed=s, name=f"test/sprites/ped_s{s}",
        prompt="a top-down game sprite of one adult pedestrian as seen by a drone hovering straight above, camera "
               "pointing straight down: we see the top of the head (hair), both shoulders and the arms from above, "
               "shoes peeking out, body foreshortened to a small oval, like characters in classic 2D top-down games, "
               "centered on a plain flat white background, light from the top-left, short soft shadow. Style: flat "
               "vector, thin dark outline, flat colors. no text."))
for j in out: print(json.dumps(j))
