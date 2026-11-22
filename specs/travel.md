# Rychlý přesun: metro a taxi (M2-S3)

**version: 1** · P0 jízdné a odemykání stanic (`vectors/travel.json`) · P1 stanice ve světě,
přesun · METROPOLE_PLAN 4 („Rychlý přesun“), M2 bod 3 · parita F-038 · uložení `specs/save.md` v3

## Účel
Přes velké město se nemusí pokaždé jet. Stanice metra se odemknou návštěvou a pak se mezi
odemčenými jezdí za jízdné; taxi z telefonu odveze kamkoli na spot nebo památku za cenu podle
vzdálenosti. Přesun je střih s kartou linky, žádná jízda metrem ani taxíkem. Čísla jsou
v `content/tuning.yaml` → `travel`, texty v `i18n/` (`travel*`), barvy `design/tokens.json` →
`color.travel`. Vypíná se `travel.enabled`.

## Stanice v balíčku
Stanice = spot `kind: subway` v `content/cities/<city>/spots.yaml` (bez `minigame`): vstup do
metra přichycený na silnici jako každý spot. Pořadí stanic = pořadí ve `spots.pb`. Linka stanice
je jen popisek ve jménu (`name`), žádné oficiální logo (R10).

## Stav (P0, modul `travel`)
```
config: {stations: [spotId], fareBase, farePerKm, taxiBase, taxiPerKm}
state:  {unlocked: [spotId], paid, last: {op, amount}}
```
- `stations` – id stanic města v pořadí balíčku. `unlocked` – odemčené stanice v pořadí
  odemknutí (z uložení, `specs/save.md` v3 `stations`).
- `paid` – součet zaplaceného jízdného v relaci, `last` – poslední akce (`op = ""`, `amount = 0`
  po `init`, `load` a `unlock`; `metro` a `taxi` zapíší svůj `op` i při nulovém jízdném).
- `init(config, seed)`: `unlocked = []`, `paid = 0`, `last = {op: "", amount: 0}`; `seed` se
  nepoužívá. Klient pak pošle `load` s uloženými stanicemi.

## Akce
Všechny `by: "player"`; `÷` je celočíselné dělení nezáporných čísel.
- `{op: "load", unlocked: [spotId]}` – stanice z uložení. Zůstanou jen id ze `stations`, bez
  duplicit, v pořadí seznamu. `last` prázdné.
- `{op: "unlock", station}` – hráč navštívil stanici. Neznámá stanice = nelegální. Už odemčená =
  beze změny. Jinak se přidá na konec `unlocked`. `last` prázdné.
- `{op: "metro", from, to, distDm, cash}` – jízda metrem. Nelegální, když `from` nebo `to` není
  odemčená, `from = to`, `distDm < 0` nebo `cash < 0`. `fare = fareBase + distDm × farePerKm ÷
  10000`. Když `cash < fare`: nelegální (klient tlačítko neukáže). Jinak `paid += fare`,
  `last = {op: "metro", amount: fare}`.
- `{op: "taxi", distDm, cash}` – jízda taxíkem. Nelegální, když `distDm < 0` nebo `cash < 0`.
  `fare = taxiBase + distDm × taxiPerKm ÷ 10000`; `cash < fare` nelegální; jinak `paid += fare`,
  `last = {op: "taxi", amount: fare}`.

`distDm` je přímá vzdálenost parkovacích bodů v celých dm: `floor(sqrt(dx² + dy²))`, kde `dx, dy`
jsou rozdíly celých dm (`floor(x × 10 + 0,5)`) – stejně jako nedosažitelný cíl ve `specs/feed.md`.
Pro taxi se měří od auta.

Čisté funkce (oba klienti exportují): `metroFare(cfg, distDm)`, `taxiFare(cfg, distDm)`.
`legalActions(state)`: `load` s `[]` a `unlock` pro každou dosud zamčenou stanici v pořadí
`stations`. `result` vždy `null`, `aiAction` neexistuje.

## Hotovost
Jako bonus budek (`specs/booths.md`): klient vezme `cash` ze stavu aut, pošle ho v akci, po akci
odečte `last.amount` a zapíše zpět. Hotovost tak nikdy neklesne pod 0.

## Ve světě (P1)
- **Odemknutí:** auto (vrstva 0) je od parkovacího bodu stanice do `travel.unlock_m` → `unlock`,
  při novém odemknutí toast `travelUnlocked` se jménem stanice a uložení.
- **Metro:** u odemčené stanice stejné podmínky jako „Hrát“ (`specs/loop.md`: rychlost, vrstva,
  `loop.spot_radius_m`) ukážou kontextové tlačítko „Metro“ (`travelMetro`). Karta přes svět
  (pauza, `specs/pause.md`): seznam ostatních odemčených stanic v pořadí `unlocked` se jménem a
  jízdným (`travelFare`); stanice, na kterou hotovost nestačí, je šedá. Výběr → `metro` →
  přesun. Dokud je některá stanice zamčená, karta ukáže řádek `travelLocked` (zamčené stanice se
  v seznamu nezobrazují). Tlačítko Metro se ukazuje i během navigace. Tlačítko „Zpět“ (`travelClose`).
- **Taxi:** aplikace telefonu Taxi (id `taxi`, mezi Mapou a Garáží, `specs/phone.md`): seznam
  cílů = spoty s minigame a hero památky města, řazené podle vzdálenosti od auta, každý s cenou;
  na co hotovost nestačí, je šedé. Výběr → `taxi` → přesun na parkovací bod cíle (u památky
  průmět na nejbližší ponechanou hranu na zemi do `minigames.taxi.dest_search_m`, směr podle
  hrany, na jednosměrce po směru; památka bez silnice v tom okruhu v seznamu není). Řazení podle
  celočíselného `distDm`, při shodě spoty před památkami v pořadí seznamu. Během hledanosti > 0 je Taxi
  zamčené (`travelWanted`).
- **Přesun:** karta linky přes svět na `travel.cut_s` (jméno cíle, ikona metra nebo taxi, barvy
  `color.travel`), pak auto stojí na parkovacím bodu cíle ve směru `parkHeading` s nulovou
  rychlostí, vrstva 0. Provoz, chodci a hlídky se resetují jako po teleportu (`specs/traffic.md`,
  `specs/pedestrians.md`). Přijatá karta feedu a navigace zůstanou (trasa se přepočítá).
  Odemknutí cílové stanice je tím splněné.
- **Ukládá se** po odemknutí a po každé jízdě (změna hotovosti).
- **Kdy ne:** během minihry, Taxi směny (`specs/minigames/taxi.md`) a s hledaností > 0 se
  rychlý přesun nenabízí.
- **Kreslení:** vstup do metra shora jako obdélník `travel.entry_w_m × travel.entry_l_m` u
  parkovacího bodu (`travel.entry`, zamčený `travel.entryLocked`), na Mapě odemčené stanice jako
  bod `travel.entry`.

## Hraniční případy
- Stanice, která z balíčku zmizela, se při `load` tiše zahodí.
- `fare = 0` (nulový tarif v tuningu) je legální, hotovost se nemění.
- Hráč v cizím autě: přesun ho veze v tomtéž autě; hledanost tím nevznikne.
- Město bez stanic: tlačítko Metro se neukáže, Taxi funguje.
