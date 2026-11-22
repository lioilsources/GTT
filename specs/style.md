# Skiny měst (paleta a risograf)

**version: 2** · P1 kreslení světa · METROPOLE_PLAN kap. 12 („výrazná paleta na město“), style
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
- Textury povrchů (`assets/cities/<city>/…`) přijdou později; zatím jen plné barvy.

## Plochý vektor (v2, styl A)
Verze 1 měnila jen barvy, a to na styl A nestačí: na style boardu ho dělají hlavně dlouhé
modré stíny budov přes ulici, světlé ploché střechy s okrajem a zebry. Všechno níže platí jen
ve **dne** a jen pro města, kde to zapíná `content/tuning.yaml` → `style`. Počítá se jednou při
stavbě geometrie chunku, za běhu nic navíc.
- **Střechy:** má-li `color.city.<city>` klíče `roof` a `roofEdge`, střecha budovy (ne památky)
  je `roof` × jitter budovy (stejný jako u fasády) místo fasády × `roofLight`. Podél obrysu
  střechy (vnější prstenec i dvory) se kreslí pás `roofEdge` široký `style.roof_edge_m`
  dovnitř (atika). Rohy nemusí lícovat přesně, pás nesmí přečnívat ven z obrysu víc než o
  `roof_edge_m`. Památky zůstávají `landmark` × `roofLight` bez okraje, aby vynikly.
- **Vržené stíny** (`style.cast_shadow.<city>`): každá budova s `minHeight = 0` vrhá na zem stín
  ve směru od slunce `s = −(sunX, sunY) / |(sunX, sunY)|` (`light.day`) délky
  `L = min(height × style.shadow_ratio, style.shadow_max_m)`. Tvar stínu = obrys posunutý o
  `L·s` a pro každou hranu obrysu čtyřúhelník (a, b, b + L·s, a + L·s) – sjednocení dá přesný
  stín hranolu na rovné zemi, sjednocení se nepočítá. Barva `color.city.<city>.castShadow`
  (s alfou). Překryvy stínů (dva stíny přes sebe, stín pod budovou) se **nesčítají**: celá
  plocha stínů má jeden odstín (klient např. kreslí stíny do vlastní vrstvy neprůhledně a skládá
  ji s alfou, nebo použije test hloubky/stencilu). Pořadí: nad zemí, zónami, silnicemi,
  značením a zebrami ve vrstvě 0; pod budovami, mosty, kolejemi tramvají, auty, chodci a
  mobiliářem. Na mosty a do tunelů stín nepadá. Stín sahající do sousedního chunku se kreslí
  s chunkem budovy (na okraji načtené oblasti smí chybět).
- **Zebry** (`style.crosswalks.<city>`): v každém uzlu s aspoň třemi ponechanými hranami ve
  vrstvě 0 dostane každá taková hrana přechod. Vzdálenost od uzlu podél hrany
  `c = max(polovina šířky ostatních hran v uzlu) + style.crosswalk_gap_m`; přechod sahá od `c`
  do `c + style.crosswalk_len_m`. „Podél hrany“ = po ulici: od uzlu po hraně a dál přes uzly
  s právě dvěma ponechanými hranami ve vrstvě 0 (balíčky dělí silnice v každém konektoru),
  až k dalšímu uzlu se ≥ 3 hranami nebo ke slepému konci. Je-li takto spojená ulice kratší
  než `2 × (c + crosswalk_len_m)`, přechod na ní není. Šířka vozovky = vozovka výchozí hrany,
  poslední pruh se ořízne okrajem vozovky. Pruhy jsou rovnoběžné s osou silnice, široké `style.crosswalk_stripe_m`, mezera
  stejná, přes celou vozovku (bez chodníků), první pruh u okraje vozovky; barva `marking`.
  Kreslí se nad značením pruhů (přerušované čáry a osa v místě zebry zůstávají pod ní).
- Barvy jsou v `color.city.<city>` (`roof`, `roofEdge`, `castShadow`); chybějící klíč = daná
  věc se nekreslí (stín, okraj) nebo zůstává podle v1 (střecha).

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
- Noc: paleta, risograf, vržené stíny i zebry vypnuté, `color.world.night`.
- Výkon: stíny a zebry přidají trojúhelníky, ne průchody; 60 fps na referenčních telefonech platí
  dál. Rozdělení budov na části (`building_part`) s `minHeight > 0` stín nevrhá.
- Ladicí přepínač schématu ovládání (`settings.scheme`) skin nemění.
- Neznámé město v tokenech: `color.world.day`, bez risografu, stínů a zeber.
