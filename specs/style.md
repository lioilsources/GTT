# Skiny měst (paleta a risograf)

**version: 1** · P1 kreslení světa · METROPOLE_PLAN kap. 12 („výrazná paleta na město“), style
pack v `city.yaml` · parita F-039

## Účel
Každé město má vlastní vzhled. Ol1n vybral ze style boardu: New York = **A, plochý vektor**
(teplý asfalt, cihlové nízké domy, ocelově modré věže, modré stíny), Praha = **C, sítotisk /
risograf** (papír, okrová dlažba, měděnka, omezená sada barev s posunutým tiskem a zrnem).
Barvy jsou v `design/tokens.json` → `color.city.<city>`, čísla efektu v `content/tuning.yaml` →
`style`. Pole `style: style.yaml` v `city.yaml` je zatím jen odkaz na tento dokument; soubor
nevzniká, protože barvy a čísla mají svá místa.

## Paleta
- `color.city.<city>` má stejné klíče jako `color.world.day` (land, water, park, plaza,
  pedestrian, rail, sidewalk, asphalt, alley, marking, centerLine, bridgeDeck, bridgeEdge,
  tunnel, landmark, facades) a navíc `shadow` (barva s alfou).
- Ve **dne** klient kreslí svět paletou města (`id` z manifestu balíčku). Světla (`light.day`:
  roofLight, slunce, ambient) zůstávají společná. Město bez `color.city.<id>` = `color.world.day`.
- **Noc** zůstává v1 společná (`color.world.night`), skin se v noci neuplatní.
- Fasáda budovy: `facades[seed mod len]` jako dosud, památka `landmark`. Střecha = fasáda ×
  `roofLight` jako dosud.
- `shadow`: stín pod autem hráče, zaparkovanými auty, provozem, hlídkami a tramvajemi (kde klient
  stín kreslí); chodci mají svůj token. Ve stylu A jsou
  stíny modré, ne černé. Kde klient stín nekreslí, v1 nic nepřidává.
- Přepnutí města (`specs/cities.md`) přestaví geometrii v nové paletě jako přepnutí den/noc.
- Textury povrchů (`assets/cities/<city>/…`) přijdou později; v1 jen plné barvy.

## Risograf (Praha)
Zapíná `style.risograph.<city>`, jen ve dne. Efekt se týká jen **vrstvy světa** (země, silnice,
zóny, budovy, koleje); auta, chodci, mobiliář, tramvaje, ikony a HUD se kreslí až po něm a bez
něj. Inkousty `color.city.<city>.inks`, papír = `land`. Pro každý pixel obrazu světa `c` (px =
fyzické pixely, `dpr` = poměr pixelů zařízení):
1. **Posun tisku:** `o = misregistration_px × dpr`. Vzorek `c'` na pozici `p + (o, o/2)`. Hrana
   `e = min(1, |lum(c') − lum(c)| × 4)`. `c = mix(c, inks[0], fringe × e)` – tenký okraj prvního
   inkoustu vedle kontur, jako posunutá tisková deska.
2. **Raster:** v buňkách `halftone_cell_px × dpr`, tečka = kruh ve středu buňky s poloměrem
   `(1 − lum(c)) × buňka × 0,7071` (černá vyplní celou buňku). Jen když `halftone_low ≤ lum(c) ≤ halftone_high` (polotóny, ne kontury ani
   papír): uvnitř tečky `c ×= 1 − halftone_strength`.
3. **Zrno:** `n` = deterministický hash souřadnic buňky `grain_size_px × dpr` (rozsah −1…1,
   stálý mezi snímky, posouvá se se světem nebo je přilepený k obrazovce – obojí v pořádku);
   `c += n × grain_strength`.

`lum` = 0,299 r + 0,587 g + 0,114 b. Parita je vizuální (podobný dojem), ne po pixelech. Efekt
nesmí stáhnout snímkovou frekvenci pod 60 fps na referenčních telefonech; když klient neumí
efekt kreslit jen pod vrstvou aut, smí ho kreslit přes celý svět bez HUD.

## Hraniční případy
- Noc: paleta i risograf vypnuté, `color.world.night`.
- Ladicí přepínač schématu ovládání (`settings.scheme`) skin nemění.
- Neznámé město v tokenech: `color.world.day`, bez risografu.
