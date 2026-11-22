# Napojení grafiky (portréty, pohlednice)

**version: 1** · P2 UI · `docs/art-requests.md` (objednávka a stav), `assets/LICENSES.md` · parita F-040

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
- **Dialog:** místo kruhu s iniciálami `npc/<id>_<výraz>.png` ořezaný do kruhu (střed obrázku,
  horní třetina = obličej; ořez `cover` na čtverec). Bez souboru výrazu `npc/<id>.png`, bez něj
  iniciály.
- **Karta feedu a nabídka budky** (`specs/phone.md`, `specs/booths.md`): hostitel jako
  `npc/<id>_bust.png` (768 × 1280, průhledné pozadí) místo siluety, ukotvený dole, výška ≈ 45 %
  karty; jemný pohyb siluety zůstává. Bez souboru silueta.
- **Kontakty a soupeř** (všude, kde je dnes kruh s iniciálami): `npc/<id>.png` v kruhu.

## Pohlednice (`specs/passport.md`)
- Památka `id` ve městě `city`: `postcards/<city>/<id>.png` (1080 × 1350, 4 : 5).
- Když soubor existuje, karta pohlednice má obrázek v poměru 4 : 5 (`contain` do šířky karty,
  zaoblené rohy jako dosud) místo zástupného výkresu 3 : 2; text a razítko pod ním beze změny.
  Karta se vejde na výšku obrazovky: když ne, obrázek se zmenší (zachová poměr).
- Seznam v Pasu ukazuje u získané památky s obrázkem jeho miniaturu (ořez `cover` na čtverec).
- Bez souboru zástupný výkres podle `specs/passport.md`.

## Výkon a velikost
Obrázky se načítají líně (při prvním zobrazení), dekódované se drží v cache s limitem 24 kusů
(LRU). Na webu `loading="lazy"` / `decode()`, ve Flutteru `Image.asset` s `cacheWidth` podle
skutečné velikosti na obrazovce.

## Hraniční případy
- Chybí jen některé výrazy: použije se `<id>.png` (= neutral), pak iniciály.
- Neznámé město nebo památka bez `hero: true`: žádná pohlednice, beze změny.
