# Chodci

**version: 1** · P1 (uskakování, testy v obou klientech) / P2 (chůze, hustota, kreslení) ·
plán: METROPOLE_PLAN 7.3, R7, M1 bod 3 · parita F-017

## Účel

Chodci oživují chodníky. **Nikdy je nelze srazit (R7):** když se k chodci blíží auto, chodec včas
uskočí stranou a nad hlavou mu na chvíli vyskočí bublina „!!“. Chodci nejsou fyzikální tělesa;
uskočení je čistá funkce polohy a rychlosti auta. Všechna čísla jsou v `content/tuning.yaml`
(`pedestrians`), barvy v `design/tokens.json` (`color.pedestrians`), text bubliny v `i18n`
(`pedestrianBubble`). Vypínač: `pedestrians.enabled`.

## Stav

Svět chodců (`PedestrianWorld`) drží pole chodců, jeden `Prng` (`specs/prng.md`) se seedem
`pedestrians.seed`, čítač id a polohu „ohniska“ (auto hráče) z minulého kroku.

Chodec:

- `id` – celé číslo od 1, v rámci jednoho světa se neopakuje.
- Cesta: `edge` (index hrany), `side` (±1, strana vůči směru from → to: +1 vlevo), `s` (metry od
  `from`), `dir` (±1, směr chůze po hraně), `speed` (m/s).
- Režim: `walk` (po chodníku), `cross` (rovně z konce jedné hrany na začátek další; přechází
  křižovatku), `leap` (skok stranou), `stun` (stojí po skoku), `recover` (vrací se na cestu).
- Odsazení `ox, oy` (metry) od bodu na cestě; mimo `leap`/`stun`/`recover` je nulové.
- `bubble` – zbývající sekundy bubliny „!!“.
- Výsledná poloha `x, y` = bod cesty + odsazení, `heading` = směr chůze.

Bod cesty (`walk`): bod polylinie hrany ve vzdálenosti `s`, posunutý po normále aktuálního
segmentu o `side · offset`, kde `offset = width / 2 − sidewalk_width_m / 2` (stejný chodník jako
rekvizity). Chodit se smí jen po hranách `kept`, v přízemí (`isGround`), ne po mostech, s `offset > 0`.

## Auto (vstup)

Každé auto, kterému se uhýbá (hráč, později provoz): střed `x, y`, `heading`, `halfLength`,
`halfWidth` (už vynásobené `car_scale`), rychlost `vx, vy`. Poloměr chodce `r = radius_m · car_scale`.

## Uskočení (P1, čistá funkce `dodge(px, py, auto)`)

1. `v = |(vx, vy)|`. Při `v < dodge_min_mps` se nepředpovídá (jen pojistka níž) → žádná hrozba.
2. `u = (vx, vy) / v`, `n = (−u.y, u.x)`. `θ = heading − atan2(vy, vx)`.
   Polovina rozměru krabice auta podél `u`: `a = halfLength·|cos θ| + halfWidth·|sin θ|`,
   napříč: `e = halfWidth·|cos θ| + halfLength·|sin θ|`.
3. `d = (px − x, py − y)`, `along = d·u`, `perp = d·n`, `R = r + dodge_margin_m`.
4. Hrozba, když `|perp| < e + R` a `−a − R < along < a + v · dodge_horizon_s + R`
   (chodec je v pásu, který krabice auta zametá za horizont).
5. Čas do kontaktu `tc = max(0, (along − a − R) / v)`.
6. Strana `s = sign(perp)`, při `perp = 0` `s = +1`. Cíl napříč: `s · (e + R + dodge_extra_m)`.
   Skok = `n · (cíl − perp)` (jen napříč, `along` se nemění, takže `tc` platí dál).
7. Délka skoku `dur = min(leap_s, tc · leap_fraction)`; je-li `dur` kratší než krok, skok je okamžitý.

Výsledek `{tc, dx, dy, dur}` nebo nic. Víc aut → platí hrozba s nejmenším `tc`.

**Záruka:** chodec po skoku leží mimo celý pás `|perp| ≥ e + R`, tedy mimo zametenou krabici auta
(pás je její nadmnožina). Protože `leap_fraction ≤ 0.5`, skok skončí nejpozději v `tc` i s chybou
jednoho kroku. Pro auto jedoucí rovně stálou rychlostí se chodec krabice auta nikdy nedotkne.

### Průběh v kroku (pro každého chodce)

1. Hrozba se počítá v **cílové** poloze (u `leap` v cíli skoku, jinak v aktuální poloze). Je-li
   hrozba, začne nový skok z aktuální polohy: `mode = leap`, `bubble = bubble_s`.
2. `leap`: odsazení lineárně k cíli za `dur`; pak `stun` na `stun_s`.
3. `recover`: odsazení se zmenšuje rychlostí `speed` k nule, ale krok se udělá, jen když nová
   poloha není v hrozbě ani v krabici auta zvětšené o `R` (jinak chodec počká). Na nule se vrací
   předchozí režim (`walk` nebo `cross`).
4. `walk`/`cross` posunou bod cesty (viz níž); `leap`/`stun`/`recover` ho drží.
5. **Pojistka:** leží-li kruh chodce (poloměr `r`) v krabici některého auta, chodec se okamžitě
   posune kolmo ven přes nejbližší stranu krabice na vzdálenost `r + dodge_margin_m` a odsazení
   se tomu přizpůsobí. Počítá se `clamps`; u auta jedoucího rovně musí zůstat 0 (test).
6. `bubble` klesá o `dt` k nule.

## Chůze, odbočování, přecházení (P2)

- `walk`: `s += dir · speed · dt`. Na konci hrany (`s ≥ délka` při `dir = +1`, `s ≤ 0` při `−1`) je
  uzel `N`. Možnosti = pochozí hrany v `N` kromě současné (pořadí jako v grafu); prázdné =
  slepá ulice, otočí se po téže hraně. Další hrana = `možnosti[prng.nextInt(počet)]`.
- Strana vůči směru chůze `ws = side · dir` zůstává, jen s pravděpodobností `cross_chance`
  (`prng.nextU32() / 2^32 < cross_chance`) se otočí (přejde ulici).
- Nový směr `dir' = +1`, když nová hrana začíná v `N` (`from = N`), jinak `−1`; `side' = ws · dir'`.
- `cross`: chodec jde rovně rychlostí `speed` z bodu, kde skončil, na začátek nové cesty; pak `walk`.
- Semafory zatím nejsou (přijdou s provozem); chodci přecházejí na každé křižovatce.

## Hustota, vznik a zánik (P2)

- `R_view` = poloměr kruhu, který pokrývá obrazovku (kamera klienta).
- Vznik v prstenci mezi `R_view + spawn_margin_m` a `R_view + spawn_margin_m + spawn_band_m`
  kolem auta hráče; `spawn_per_s` pokusů za sekundu, dokud je chodců méně než strop.
- Pokus: náhodný bod v prstenci (úhel a poloměr z `prng`), nejbližší pochozí hrana do `snap_m`,
  přijetí s pravděpodobností `min(1, class_density[třída] · čtvrť · noc)`, kde čtvrť =
  `busy_factor`, je-li bod ve čtvrti ze seznamu `busy_districts`, jinak `quiet_factor`;
  noc = `night_factor` (ve dne 1). Strana podle toho, na které straně osy bod leží, směr `±1` z `prng`,
  rychlost `walk_mps ± walk_jitter_mps`.
- Strop `max_count`, v noci `round(max_count · night_factor)`.
- Zánik: chodec dál než `R_view + despawn_margin_m` od auta hráče zmizí.
- Naplnění: na začátku a po teleportu (auto se za krok posune o víc než `spawn_band_m`) se zkusí
  `fill_attempts` pokusů v celém kruhu do vnějšího okraje prstence, ne blíž než `fill_clear_m` k autu.

## Kreslení (P2)

- Postavička shora ve vrstvě 0 pod budovami (pořadí 6.3 krok 4): stín, ramena (kapsle napříč
  směrem chůze) v barvě trička z `color.pedestrians.shirts` (podle `id`), hlava (`head`).
- Bublina „!!“ v prostoru obrazovky nad chodcem (W: překryvné plátno, F: painter) po dobu `bubble`;
  velikost `bubble_px`, zdvih `bubble_lift_px`.

## API pro další funkce

`peds` (pole chodců s `id`, `x`, `y`, `heading`), `nearest(x, y, maxDist)` → nejbližší chodec nebo
nic, `byId(id)`. Použije „pokec na ulici“ a policie.

## Testy (oba klienti)

- `dodge`: auto míjí chodce mimo pás → nic; chodec před autem → skok na správnou stranu, mimo pás,
  `dur ≤ tc · leap_fraction`; stojící auto → nic; couvání (rychlost proti `heading`).
- Záruka: 400 náhodných průjezdů (`Prng(1)`, rychlost `dodge_min_mps`–45 m/s, smyk ±0,6 rad,
  chodec v okolí trasy, ne v krabici) krokem 1/60 s; v žádném kroku se kruh chodce nepřekryje
  s krabicí auta, `clamps = 0` a tam, kde skok skončí, leží chodec mimo krabici, kterou auto zametá
  za zbytek průjezdu.
- Svět nad balíčkem NYC: naplnění dá chodce na chodnících pochozích hran, strop platí, noc snižuje
  strop, po chůzi zůstávají na chodnících, `nearest` vrací nejbližšího.

## Hraniční případy

- Hrana nulové délky se pro chůzi přeskočí (není pochozí).
- `enabled = false` → svět je prázdný, nic se nekreslí.
- Auto v tunelu nebo na mostě (vrstva ≠ 0) chodcům neuhýbá jinak – kontrola je jen v rovině; to je
  bezpečné (chodec uskočí zbytečně, nikdy ne pozdě).
