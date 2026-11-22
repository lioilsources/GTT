# Počasí: jasno, déšť, mlha (M2-S6)

**version: 1** · P0 střídání počasí (`vectors/weather.json`) · P1 přilnavost, kreslení, HUD ·
METROPOLE_PLAN 5 (style pack „počasí“), M2 bod 6 · parita F-043

## Účel
Město se mění i samo od sebe: chvíli je jasno, pak prší nebo se zvedne mlha. Déšť zhorší
přilnavost auta, mlha zúží výhled. Střídání běží v herním čase a je stejné v obou klientech
ze stejného seedu. Čísla jsou v `content/tuning.yaml` → `weather`, texty v `i18n/`
(`weather*`), barvy `design/tokens.json` → `color.weather`. Vypíná se `weather.enabled`, po
městech `weather.cities.<city>` (vypnuté město = pořád jasno, modul se nespouští).

## Stav (P0, modul `weather`)
Pravidla běží v celých sekundách hry (tik = 1 s; klient tikne jednou za sekundu pevného kroku,
pauza hodiny zastaví, `specs/pause.md`).
```
config: {weights: [clear, rain, fog], minS, maxS}
state:  {kind, left, changes, rng}
```
- `weights` – celočíselné váhy ≥ 0 druhů v pevném pořadí `clear`, `rain`, `fog` (z tuningu
  `weather.weight_clear`, `weight_rain`, `weight_fog`).
- `minS ≤ maxS` – rozsah trvání jednoho počasí v sekundách (`weather.min_s`, `weather.max_s`).
- `kind` – `clear`, `rain` nebo `fog`. `left` – sekundy do další změny. `changes` – počet změn
  od `init` (tikem i akcí `set`). `rng` – stav PRNG (`specs/prng.md`).
- `gap() = minS + rng.nextInt(maxS − minS + 1)`.
- `init(config, seed)`: `rng = Prng(seed)`, `kind = clear`, `changes = 0`, `left = gap()`.

## Akce
Všechny `by: "player"`:
- `{op: "tick"}` – jedna sekunda. `left −= 1`. Když `left > 0`: konec. Jinak:
  1. `total` = součet vah druhů různých od `kind`.
  2. Když `total > 0`: `r = rng.nextInt(total)`; projdi druhy v pořadí `clear`, `rain`, `fog`,
     přeskoč `kind`; když `r < váha`, je to nový druh, jinak `r −= váha` a dál. `kind` = nový
     druh. Když `total = 0`, `kind` zůstává a PRNG se nevolá.
  3. `left = gap()`, `changes += 1`.
- `{op: "set", kind}` – ladění a testy: `kind` = zadaný druh, `left = gap()`, `changes += 1`.
  Neznámý druh = nelegální. Stejný druh jako teď je legální (jen nové trvání).

Nelegální: neznámé `op`, `by ≠ "player"`. `legalActions(state)`: `tick` a `set` pro každý druh
v pořadí `clear`, `rain`, `fog`. `result` je vždy `null`, `aiAction` neexistuje.

## Ve světě (P1)
- **Start a uložení:** neukládá se. Po startu a přepnutí města `init` s náhodným seedem, takže
  hra začíná za jasna. Klient tiká jen nepozastavenou hru (minihra, Foťák, karty a telefon
  podle `specs/pause.md` hodiny zastaví).
- **Přilnavost:** za deště klient předá jízdě grip auta vynásobený `weather.rain_grip` (jen
  auto hráče; provoz, hlídky a tramvaje se v1 nemění). Je to vstup do jízdy, ne její pravidlo:
  `specs/drive.md`, jeho scénáře a vektory zůstávají beze změny (počítají s jasnem). Mlha
  přilnavost nemění. Grip se přepne hned při změně druhu.
- **Přechod:** vzhled (déšť, mokrá vozovka, mlha) se při změně prolne za `weather.blend_s`
  sekund (lineárně, odchod starého a příchod nového zároveň).
- **Déšť:** přes svět a auta, pod HUD, `weather.rain_drops` tahů v prostoru obrazovky, každý
  dlouhý `rain_len_px` (× poměr pixelů), padá rychlostí `rain_speed_px_s` pod úhlem
  `rain_angle_deg` od svislice, barva `color.weather.rain`. Pozice tahů jsou pseudonáhodné a
  cyklí (P2, nemusí se shodovat mezi klienty). Vozovka, chodníky a uličky se ztmaví
  na `1 − weather.wet_darken` své barvy (jen vzhled). Odlesky v1 nejsou.
- **Mlha:** přes svět a auta, pod HUD, barva `color.weather.fog`; krytí roste od středu
  obrazovky k okrajům: uprostřed `fog_center_alpha`, na okraji (vzdálenost od středu ÷ polovina
  úhlopříčky = 1) `fog_edge_alpha`, mezi tím hladce (smoothstep od `fog_inner` do 1).
- **Noc:** déšť i mlha jdou i v noci, stejné barvy (alfa s nocí).
- **Risograf** (Praha, `specs/style.md`) se kreslí na vrstvu světa před počasím; déšť a mlha
  jdou až přes něj.
- **HUD:** malá ikona počasí vedle ostatních pilulek HUD (barva `color.weather.icon`, jasno =
  slunce, déšť = kapka, mlha = vlnky). Při změně druhu toast `weatherClear` / `weatherRain` /
  `weatherFog`.
- **Ladění:** W `?weather=clear|rain|fog` pošle po `init` akci `set`; F tlačítko v ladicím
  panelu, které druhy protočí (`set`).
- **Výkon:** 60 fps za deště na Times Square na referenčních telefonech (akceptace M2). Kapky
  jako instance nebo jeden průchod shaderem, žádná alokace za snímek.

## Hraniční případy
- Všechny váhy kromě aktuálního druhu nulové: počasí se nemění, jen se obnoví `left`.
- `minS = maxS`: pevné trvání, `nextInt(1)` přesto spotřebuje jedno číslo PRNG.
- Minihra běží dlouho: hodiny stojí, po návratu počasí pokračuje, kde bylo.
- Přepnutí města: nové `init`, nové město začíná jasnem.
- Vypnuté počasí ve městě: žádná ikona, žádné toasty, grip beze změny.
