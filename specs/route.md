# GPS trasa

**version: 1** · P0 · vektory `vectors/route.json` · plán: METROPOLE_PLAN 8 („trasa A* po grafu“), M1 bod 1

## Účel

Po přijetí karty ve feedu (nebo v Taxi) vede hráče trasa po ponechaných silnicích k cíli. Oba klienti
musí najít **stejnou** trasu, proto je hledání celočíselné s pevným rozhodováním shod.

## Vstup

Graf z `graph.pb` (`specs/citypack.md`): uzly s `x, y` v dm, hrany s polylinií `points` (dm), třídou,
`oneway` a `kept`. Do trasy smí jen hrany s `kept = true` (uličky nemají GPS).

## Cena hrany

- Délka segmentu polylinie: `floor(sqrt(dx² + dy²))` v dm (IEEE sqrt je v JS i Dartu přesně
  zaokrouhlená, výsledek je stejný). Délka hrany = součet segmentů.
- Cena = délka × `route.class_cost[třída]` (`content/tuning.yaml`; index = `RoadClass`, 0–7).
- Směr: `oneway = 0` oba, `1` jen from → to, `−1` jen to → from.

## Hledání

Dijkstra z uzlu `from` do uzlu `to`:

- Fronta podle dvojice `(cena, id uzlu)` vzestupně; vybírá se nejmenší.
- Sousedé uzlu se procházejí v pořadí indexu hrany; cena se zlepší jen **ostře** menší hodnotou
  (při shodě zůstává první nalezený předchůdce).
- Konec, když se z fronty vybere `to`. Nedosažitelný cíl = prázdná trasa, cena −1.

Výstup: `{cost, nodes: [from … to], edges: [indexy hran po cestě]}`.

## Napojení na hru (P2, jen klient)

- Start: hrana, na které auto je; z jejích konců povolených jednosměrkou se vezme ten ve směru jízdy
  (při jízdě po uličce nejbližší ponechaná hrana).
- Cíl: spot má `edge` a parkovací bod; trasa vede do bližšího konce té hrany a pak k parkovacímu bodu.
- Přepočet, když se auto vzdálí od trasy o víc než `route.reroute_m` na déle než `route.reroute_s`.
- Kreslení: čára po trase (`colorUiRoute`), šipka na okraji obrazovky ke vzdálenému cíli,
  v HUD jméno cíle a vzdálenost; dojezd = do `route.arrive_m` od parkovacího bodu.

## Vektory

Modul `route` má tvar pravidel (`specs/minigames/README.md`): `init(config, seed)` si vezme graf
z configu `{nodes: [x, y, …], edges: [[from, to, class, oneway, kept, x0, y0, x1, y1, …], …], classCost}`,
stav je `{cost, nodes, edges}` poslední trasy (na začátku `{cost: −1, nodes: [], edges: []}`),
akce `{"by": "player", "from": n, "to": m}`. Grafy ve vektorech jsou syntetické mřížky
s jednosměrkami a uličkami, aby nezávisely na verzi balíčku města.

## Hraniční případy

- `from == to` → `{cost: 0, nodes: [from], edges: []}`.
- Paralelní hrany mezi dvěma uzly: vyhrává levnější, při shodě nižší index.
