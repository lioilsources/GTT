# Obchody a bary (M2-S5)

**version: 1** · P0 nákupy, svačina a piva (`vectors/shops.json`) · P1 podniky ve světě, karty,
polička v Garáži · METROPOLE_PLAN 4 a 5.5, M2 bod 5 · parita F-042 · uložení `specs/save.md` v3

## Účel
Cestou se dá zastavit: občerstvení dá dočasný bonus k odměně příští minihry, obchod se suvenýry
prodá suvenýr na poličku v Garáži a v baru se dá dát pivo a zahrát si barovou minihru. Podniky
mají fiktivní jména (R10), poloha je skutečné místo toho druhu. Čísla jsou v
`content/tuning.yaml` → `shops`, texty v `i18n/` (`shop*`, `bar*`), barvy `design/tokens.json` →
`color.shops`. Vypíná se `shops.enabled`, po městech `shops.cities.<city>` (v1 jen New York).

## Podniky v balíčku
Podnik = spot v `content/cities/<city>/spots.yaml`:
- `kind: food` – občerstvení (stánek, pekárna, pizza), bez `minigame`;
- `kind: souvenir` – suvenýry, bez `minigame`; suvenýr = id spotu, jméno = jméno obchodu;
- `kind: bar` – bar; smí mít `minigame` (bar, kde se hraje, `specs/loop.md`), nebo ne.

Pořadí podniků = pořadí ve `spots.pb`. Cena podle druhu: `shops.price_food`,
`shops.price_souvenir`, `shops.price_beer` (bar prodává pivo).

## Stav (P0, modul `shops`)
```
config: {snackPct, beerLimit, beerS, snackS, items: [{id, kind, price}]}
state:  {snackLeft, beers, beerLeft, drunk, owned: [id], last: {op, amount}}
```
- `items` – podniky města v pořadí balíčku, `kind` ∈ `food`, `souvenir`, `bar`.
- `snackLeft` – sekundy hry, po které ještě platí svačina (0 = žádná).
- `beers` – vypitá piva, která ještě nevyprchala; `beerLeft` – sekundy do vyprchání dalšího piva
  (0, když `beers = 0`). `drunk` – hráč vypil víc než `beerLimit` a musí vyhrát minihru.
- `owned` – koupené suvenýry v pořadí koupě.
- `last` – poslední akce: `op` ∈ `""`, `buy`, `reward`, `amount` = zaplaceno / bonus.
- `init(config, seed)`: `snackLeft = beers = beerLeft = 0`, `drunk = false`, `owned = []`,
  `last = {op: "", amount: 0}`; `seed` se nepoužívá.

## Akce
Všechny `by: "player"`, jen celá čísla; `÷` je celočíselné dělení nezáporných čísel.
Každá akce kromě `buy` a `reward` nastaví `last = {op: "", amount: 0}`.
- `{op: "load", owned: [id]}` – suvenýry z uložení. Zůstanou jen id podniků `souvenir`, bez
  duplicit, v pořadí seznamu.
- `{op: "tick"}` – jedna sekunda hry. `snackLeft = max(0, snackLeft − 1)`. Když `drunk` je false
  a `beers > 0`: `beerLeft −= 1`; při `beerLeft = 0`: `beers −= 1` a `beerLeft = beerS`, je-li
  ještě `beers > 0`, jinak 0. Když `drunk`, piva nevyprchávají.
- `{op: "buy", shop, cash}` – nákup. Nelegální: `shop` není id podniku, `cash < 0`,
  `cash < price`, nebo suvenýr už je v `owned`. Podle druhu:
  - `food`: `snackLeft = snackS` (nová svačina nahradí starou, nesčítá se);
  - `souvenir`: `shop` se přidá na konec `owned`;
  - `bar`: je-li `beers = 0`, `beerLeft = beerS`; pak `beers += 1`; když `beers > beerLimit`,
    `drunk = true`.

  `last = {op: "buy", amount: price}`.
- `{op: "reward", amount}` – odměna smyčky z ekonomiky (`amount ≥ 0`, jinak nelegální). Když
  `snackLeft > 0`: `bonus = amount × snackPct ÷ 100`, `snackLeft = 0` (svačina se spotřebuje);
  jinak `bonus = 0`. `last = {op: "reward", amount: bonus}`.
- `{op: "finish", stars, aborted}` – výsledek smyčky (`stars` 0–3, `aborted` bool, jinak
  nelegální). Když `drunk`, `stars ≥ 1` a ne `aborted`: `drunk = false`, `beers = 0`,
  `beerLeft = 0`. Jinak beze změny.

`legalActions(state)`: `load` s `[]`, `tick`, `finish` s `stars = 1, aborted = false`, `reward`
s `amount = 0` a `buy` pro každý podnik v pořadí `items` s `cash = price` (bez koupených
suvenýrů). `result` vždy `null`, `aiAction` neexistuje.

## Hotovost
Jako budky a rychlý přesun (`specs/booths.md`, `specs/travel.md`): klient vezme `cash` ze stavu
aut, pošle ho v `buy`, odečte `last.amount` a zapíše zpět. Po výsledku smyčky pošle `reward`
s hotovostní odměnou ekonomiky téže smyčky (`economy.last.amount`, po akci `reward` ekonomiky) a
nenulové `last.amount` přičte k hotovosti; výsledková obrazovka ukáže řádek `loopSnack`
(zahrnutý v `loopCash`). Pak pošle `finish`. Ekonomika se nemění.

## Ve světě (P1)
- **U podniku:** stejné podmínky jako „Hrát“ (`specs/loop.md`: rychlost, vrstva 0, parkovací bod
  do `loop.spot_radius_m`). U `food` a `souvenir` HUD ukáže kontextové tlačítko „Koupit“
  (`shopOpen`), u baru „Bar“ (`barOpen`) – bar s `minigame` místo „Hrát“ ukáže „Bar“ (hra je
  v kartě baru). Pořadí kontextových tlačítek: Zvednout > Foťák > Bar / Koupit > Hrát >
  Přesednout; Metro zvlášť. Během minihry a Taxi směny se tlačítka neukazují.
- **Karta obchodu** (hra stojí, `specs/pause.md`, druh `shop`): hostitel =
  `characters[fnv1a(spotId) mod počet postav]` (bust jako u budky, `specs/art.md`), pod ním skit
  z kontextu `shop` (`specs/dialogue.md`, `startSkit`), jméno podniku, co prodává (`shopSnack`
  s procenty u občerstvení, jméno suvenýru u obchodu) a cena. Tlačítka „Koupit“ (`shopBuy`,
  šedé s `shopNoCash`, když hotovost nestačí) a „Zpět“ (`shopBack`). Koupený suvenýr ukáže
  `shopOwned` místo tlačítka. Po koupi toast a uložení (suvenýr).
- **Karta baru:** stejně, skit z kontextu `bar`, řádek „Pivo“ (`shopBeer` s cenou) a pro každou
  různou minihru spotů `kind: bar` ve městě (v pořadí spotů) tlačítko „Zahrát <název>“
  (`shopPlay`). Výběr spustí smyčku na **tomto** baru s vybranou minihrou (`specs/loop.md`,
  „Zvolená minihra“). Bez barových miniher ve městě jen pivo.
- **Piva:** s `beers ≤ beerLimit` se jezdí normálně, HUD smí ukázat malý počet piv
  (`shopBeers`). Když `drunk`: vstup řízení se ignoruje, auto brzdí do zastavení, HUD ukáže pruh
  `shopsDrunk` v barvě `shops.drunk` (vyhraj minihru a vystřízlivíš). Taxi a Metro fungují (`specs/travel.md`, auto
  jede s hráčem), minihry jdou spustit jako jindy (karta baru, „Hrát“ u spotu v dosahu, Feed).
  Když `drunk` skončí, toast `shopsSober`. Tik jen v běžícím světě (pauza hodiny zastaví).
- **Polička:** aplikace Garáž (`specs/cars.md`, `specs/phone.md`) má oddíl „Polička“ (`shopShelf`)
  se suvenýry z `owned` v pořadí koupě: obrázek `assets/souvenirs/<id>.png`, je-li v
  `assets/index.json` (`specs/art.md`), jinak ikona v barvě `shops.souvenir`, pod ním jméno.
  Prázdná polička: `shopShelfEmpty`.
- **Kreslení:** podnik u parkovacího bodu jako kruhová ikona průměru `shops.icon_m` v barvě
  druhu (`shops.food`, `shops.souvenir`, `shops.bar`), na Mapě bod stejné barvy.
- **Ukládá se** jen `owned` (uložení `souvenirs`, `specs/save.md`); po startu `load`. Svačina a
  piva žijí jen v relaci.

## Rozhodnutí
Pravidlo piv rozhodl Ol1n 2026-11-22 („Pár piv řídit můžeš, když si jich dáš moc, musíš vyhrát
minigame.“) místo výchozí volby N6 z `plans/M2_NYC.md`.

## Hraniční případy
- Podnik zmizelý z balíčku: suvenýr se při `load` tiše zahodí.
- Hotovost na nákup nestačí: tlačítko šedé, `buy` se neposílá.
- Svačina vyprší dřív, než hráč dohraje: bonus 0, řádek `loopSnack` se neukáže.
- Vzdaná minihra (`aborted`) ani 0★ opilého hráče nevystřízliví.
- Bar s `minigame`: „Hrát“ se tam neukáže, hra je v kartě baru.
- Město bez podniků nebo s `shops.cities.<city> = false`: modul se nespouští, tlačítka se
  neukážou, polička zůstává (suvenýry z jiného města se ukládají po městech, `specs/save.md`).
