# Napojení grafiky (portréty, pohlednice)

**version: 2** · P2 UI · `docs/art-requests.md` (objednávka a stav), `assets/LICENSES.md` · parita F-040

## Účel
Hotová grafika z ComfyUI nahradí zástupné kresby tam, kde existuje. Kde soubor chybí, kreslí klient
dál zástupný výkres podle dosavadní specifikace, takže grafika může přicházet po částech.
Soubory jsou v `assets/` a `metro sync` je kopíruje do obou klientů (`app/assets/shared/assets/`,
`web/public/shared/assets/`).

## Zjištění, co existuje
`metro sync` zapíše vedle assetů `assets/index.json`: seřazený seznam relativních cest všech PNG
(`["npc/maya.png", …]`). Klient ho načte při startu; soubor, který v něm není, neexistuje (žádné
zkoušení cest za běhu). Chybějící `index.json` = žádná grafika.

## Portréty postav (`specs/dialogue.md`)
- **Výraz podle vibe** postavy `c`: `vibe[c] ≥ contactMinVibe` → `happy`; `vibe[c] < vibeStart`
  → `annoyed`; jinak `neutral`.
- **Dialog:** místo kruhu s iniciálami `npc/<id>_<výraz>.png` ořezaný do kruhu (ořez `cover` na
  čtverec kolem středu). Bez souboru výrazu `npc/<id>.png`, bez něj
  iniciály.
- **Karta feedu a nabídka budky** (`specs/phone.md`, `specs/booths.md`): hostitel karty feedu =
  `characters[fnv1a(spotId) mod počet postav]` (jako soupeř a hostitel budky), zobrazený jako
  `npc/<id>_bust.png` (768 × 1280, průhledné pozadí) místo siluety, ukotvený dole, výška ≈ 45 %
  karty; jemný pohyb siluety zůstává. Bez souboru silueta (budka bez busty jen text, siluetu nemá). U budky busta nad textem
  nabídky.
- **Kontakty a soupeř** (všude, kde je dnes kruh s iniciálami): `npc/<id>.png` v kruhu.

## Pohlednice (`specs/passport.md`)
- Památka `id` ve městě `city`: `postcards/<city>/<id>.png` (1080 × 1350, 4 : 5).
- Když soubor existuje, karta pohlednice má obrázek v poměru 4 : 5 (`contain` do šířky karty,
  zaoblené rohy jako dosud) místo zástupného výkresu 3 : 2; text a razítko pod ním beze změny.
  Karta se vejde na výšku obrazovky: když ne, obrázek se zmenší (zachová poměr).
- Seznam v Pasu ukazuje u získané památky s obrázkem jeho miniaturu (ořez `cover` na čtverec).
- Bez souboru zástupný výkres podle `specs/passport.md`.

## Auta (v2)
Sprity aut nahrazují **jen kreslení** podle `specs/cars.md` → „Kreslení“; rozměry, kolize, fyzika i
stín zůstávají z JSON a z kódu. Formát souborů a seznam: `docs/art-requests.md` kap. 3.
- **Kdy:** auto `id` (nebo `traffic_sedan`, `police_patrol`) kreslí sprite, když `index.json`
  obsahuje `cars/<id>/body.png`, `cars/<id>/paint_mask.png` (u hlídky ne) a `cars/<id>/wheel.png`
  (u třídy `micro` ne). Jinak celé auto procedurálně jako dosud – nikdy napůl. `lights.png` je
  volitelné: bez něj kreslí kód světla jako dosud i přes sprite.
- **Měřítko a poloha:** sprite `w × h` px má střed ve středu auta, předek ve směru +x auta (nahoru
  na plátně). Velikost ve světě = `w ÷ 32 × car_scale` napříč a `h ÷ 32 × car_scale` podél (stejné
  měřítko jako kolize, plátno má okraj 5 %). U provozu a hlídek se místo `car_scale × JSON` bere
  jejich tuning (`traffic.car_length_m`/`car_width_m` × `car_scale`) a sprite se natáhne na
  `rozměr × 1,1`.
- **Lak:** výsledná barva = `body.rgb × mix(1, lak.rgb, m)`, `m` = jas `paint_mask`, alfa z
  `body.png`. `lak` = aktivní barva auta (katalog, garáž `looks.paint`, náhodná barva provozu
  `color.traffic.bodies`, zaparkovaná auta jako dosud). Hlídka se netónuje.
  - **W:** jeden materiál pro všechna auta se sprity: atlas `body` a atlas `mask` (stejné rozložení,
    sestavené při načtení města z aut s `tags` města + `traffic_sedan` + `police_patrol`, max
    2048², řádkové pakování podle výšky), thin instances s atributy `uvRect` (vec4) a `paint`
    (vec4); shader `body × mix(1, paint, mask)`. Kola: druhý atlas a druhá síť thin instances
    (pozice a natočení v matici instance). Světla: třetí atlas, aditivně, jen v noci / při brzdění.
    Celkem nejvýš **+3 draw calls** pro hráče, zaparkovaná auta, provoz i hlídky dohromady
    (procedurální auta bez spritu zůstávají ve svých dosavadních sítích).
  - **F:** předtónovaný `ui.Image` na dvojici (auto, lak) – `body` přes `ColorFilter`/`BlendMode`
    podle vzorce výše, složené jednou v `PictureRecorder` – v LRU cache s limitem **48** (zvlášť od
    24 obrázků portrétů a pohlednic). Kreslení přes `Canvas.drawAtlas` (jedno volání pro karoserie,
    jedno pro kola, jedno pro světla), `RSTransform` podle polohy, natočení a měřítka.
- **Kola:** `wheel.png` se kreslí **pod** karoserii na pozicích `wheelLayout` ze `specs/cars.md`
  (osa `drive.axle_offset × hl`, `±0,92 hw`; autobus, tříkolka a rikša podle třídy), přední se
  natáčí o úhel řízení (jen auto hráče; zaparkovaná a provoz rovně), kola na levé straně
  zrcadlená. Velikost kola z obrázku (`÷ 32 × car_scale`). Garáž `looks.wheels > 0` násobí kolo
  barvou `color.garage.wheels[value]` (sprite kola má světlý disk).
- **Světla:** `lights.png` v noci celé (aditivně, alfa 1), ve dne zadní polovina plátna (pod
  středem) jen při brzdění. Kužel světlometů v noci a podsvícení (`looks.glow`) kreslí kód jako
  dosud. Hlídka: blikání majáku kreslí kód do pouzdra na střeše (`specs/police.md`).
- **Polep** (`looks.decal`) se kreslí jako dosud procedurálně, oříznutý alfou `paint_mask`
  (nanáší se jen na lak).
- **Stín** auta zůstává procedurální obdélník (`shadow`), sprite stín nemá.
- **Kde:** auto hráče, zaparkovaná auta, provoz, hlídky, náhled v garáži a v seznamu na prodej
  (stejný obrázek zmenšený).

## Výkon a velikost
Obrázky se načítají líně (při prvním zobrazení), dekódované se drží v cache s limitem 24 kusů
(LRU). Na webu `loading="lazy"` / `decode()`, ve Flutteru `Image.asset` s `cacheWidth` podle
skutečné velikosti na obrazovce.

## Hraniční případy
- Chybí jen některé výrazy: použije se `<id>.png` (= neutral), pak iniciály.
- Neznámé město nebo památka bez `hero: true`: žádná pohlednice, beze změny.
- Auto s `body.png`, ale bez masky nebo kola: celé procedurálně (sprite se nepoužije).
- Atlas se nevejde do 2048² (W): auta nad limit procedurálně, v pořadí `content/cars` id.
- Noc a skin města (`specs/style.md`): sprite se nebarví paletou města, jen lakem.
