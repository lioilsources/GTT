# Fotomísta a Foťák (M2-S4)

**version: 1** · P0 kontrola záběru (`vectors/photo.json`) · P1 fotomísta ve světě, aplikace
Foťák · METROPOLE_PLAN 4 („Pas turisty“), M2 bod 4 · parita F-041 · razítka `specs/passport.md`

## Účel
Fotomísto je výhled, ne památka: místo u cesty, odkud je vidět něco pěkného (most nad ulicí,
řeka, kaňon ulice). Hráč zastaví, otevře v telefonu Foťák, tahem zarámuje výhled a dostane
razítko `photo:<id>` do Pasu; procento Pasu tak počítá i fotomísta (váha `passport.weights[3]`).
Čísla jsou v `content/tuning.yaml` → `photo`, texty v `i18n/` (`photo*`), barvy
`design/tokens.json` → `color.photo`. Vypíná se `photo.enabled`.

## Fotomísta v balíčku
Fotomísto = spot `kind: photo` v `content/cities/<city>/spots.yaml` (bez `minigame`) se dvěma
poli navíc: `look: {lat, lon}` (střed výhledu, co se má zarámovat) a `subject_m` (poloměr
výhledu v metrech). citypack je zapíše do `Spot.look_x`, `Spot.look_y` (dm) a `Spot.subject_dm`;
`build` bez nich selže, `validate` hlídá `subject_dm > 0` a `look` nejdál 1,5 km od parkovacího
bodu. Pořadí = pořadí ve
`spots.pb`. Katalog Pasu `photo` = id fotomíst v tomto pořadí.

## Stav (P0, modul `photo`)
```
config: {spots: [{id, x, y, r}], loosePct}
state:  {taken: [id], last: {spot, verdict}}
```
- `spots` – fotomísta města: `x, y` = `look` v dm, `r` = `subject_dm`.
- `loosePct` – nejvolnější povolený záběr: polovina kratší strany rámečku smí být nejvýš
  `r × loosePct ÷ 100`.
- `taken` – vyfocená fotomísta v pořadí vyfocení. `last.verdict` ∈ `""`, `ok`, `again`, `cut`,
  `loose`; `last.spot` id posledního pokusu (`""` po `init` a `load`).
- `init(config, seed)`: `taken = []`, `last = {spot: "", verdict: ""}`; `seed` se nepoužívá.

## Akce
Všechny `by: "player"`; `÷` je celočíselné dělení nezáporných čísel.
- `{op: "load", taken: [id]}` – vyfocená místa z razítek Pasu (`photo:<id>`). Zůstanou jen id ze
  `spots`, bez duplicit, v pořadí seznamu. `last` prázdné.
- `{op: "shoot", spot, cx, cy, hw, hh}` – snímek u fotomísta `spot`: střed rámečku `cx, cy` ve
  světě (celé dm), poloviny stran `hw, hh` (celé dm, ≥ 1). Neznámý `spot`, `hw < 1` nebo `hh < 1`
  = nelegální. Pak, s `h = min(hw, hh)` a `d = floor(sqrt((cx − x)² + (cy − y)²))`:
  1. `d + r > h` → `cut` (výhled se do rámečku nevejde nebo je mimo).
  2. jinak `h × 100 > r × loosePct` → `loose` (moc široký záběr).
  3. jinak, je-li `spot` už v `taken` → `again`; jinak `ok` a `spot` se přidá na konec `taken`.
  `last = {spot, verdict}`.

`legalActions(state)`: `load` s `[]` a pro každé fotomísto `shoot` se středem přesně na `x, y` a
`hw = hh = r`. `result` vždy `null`, `aiAction` neexistuje.

## Ve světě (P1)
- **U fotomísta:** stejné podmínky jako „Hrát“ (`specs/loop.md`: rychlost, vrstva 0, parkovací
  bod do `loop.spot_radius_m`). HUD ukáže kontextové tlačítko „Foťák“ (`photoOpen`); přednost má
  „Zvednout“ (budka), pak Foťák, pak „Hrát“. Stejně jde otevřít aplikace Foťák v telefonu (id
  `camera`, slot z `specs/phone.md`); jinde než u fotomísta ukáže jen `photoNoSpot`.
- **Foťák:** telefon se zavře, hra stojí (`specs/pause.md`, druh `photo`), kamera plynule
  (`photo.zoom_s`) přejede na střed mezi autem a `look` a oddálí se tak, aby šířka pohledu byla
  `max(view_width_m.slow, 2 × subject_m × photo.view_factor)`. Na `look` se kreslí zaměřovač
  (`photo.cross`), nahoře text `photoHint` se jménem fotomísta. Tah prstem/myší = rámeček
  (protilehlé rohy, obdélník rovnoběžný s obrazovkou, barva `photo.frame`); puštění = snímek.
  Klient převede rámeček do světa: střed obrazovkového rámečku → světový bod (`cx, cy`), poloviny
  stran ÷ měřítko kamery → `hw, hh` (celé dm, `floor(x × 10 + 0,5)`, nejméně 1).
- **Výsledek:** `ok` → záblesk `photo.flash` na `photo.flash_s`, razítko do Pasu
  (`visit photo`), toast `photoTaken` se jménem, uložení; Foťák se zavře. `again` → záblesk a
  toast `photoAgain`, bez razítka. `cut` → `photoCut`, `loose` → `photoLoose`, rámeček zmizí,
  hráč zkouší dál. Tlačítko „Zpět“ (`photoClose`) Foťák zavře bez snímku.
- **Kdy ne:** během minihry, Taxi směny a s hledaností > 0 (`photoWanted`). Během navigace
  s přijatou kartou Foťák jde, navigace pokračuje.
- **Kreslení:** fotomísto u parkovacího bodu jako ikona fotoaparátu (`photo.spot`, vyfocené
  `photo.spotDone`), na Mapě jako bod stejné barvy.
- **Ukládá se** jen přes razítka Pasu (`Save.stamps`), modul `photo` se po startu naplní `load`
  z razítek `photo:*`.

## Hraniční případy
- Fotomísto zmizelé z balíčku: razítko v Pasu zůstane (Pas ho jen nepočítá do katalogu), `load`
  ho tiše zahodí.
- Rámeček přes celou obrazovku na malém výhledu = `loose`; malý rámeček vedle = `cut`.
- Město bez fotomíst: tlačítko se neukáže, aplikace ukáže `photoNoSpot`.
