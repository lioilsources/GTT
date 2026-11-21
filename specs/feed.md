# Feed: výběr balíčku karet

**version: 1** · P0 · vektory `vectors/feed.json` · plán: METROPOLE_PLAN 8 („Výběr karet“), M1 bod 7

## Účel

Feed v herním telefonu nabízí hráči, kam jet hrát. Balíček se skládá lokálně (bez sítě) ze spotů
města, které mají minihru. Oba klienti musí ze stejných vstupů složit **stejný** balíček, proto je
výběr celočíselný a náhoda jde jen z `Prng` (`specs/prng.md`). Čísla jsou v `content/tuning.yaml`
pod `feed`; v M1 má balíček `feed.deck_size = 6` karet (plán obecně 12).

## Kandidáti (klient, mimo vektory)

Klient sestaví seznam kandidátů a předá ho pravidlům v configu. Pořadí kandidátů = pořadí spotů
ve `spots.pb`.

- Každý spot s neprázdným `minigame`, které je v katalogu (`content/minigames/catalog.yaml`):
  `game` = id minihry, `engine` = engine z katalogu, `local` = katalog u minihry uvádí `cities`
  a je v nich aktuální město („místní hra“).
- **Jízdní výzva** = kandidát s `engine = "drive"` (v NYC Taxi). Když ve městě žádný není, přidá
  se na konec seznamu za každý spot **bez** minihry (v pořadí spotů) zástupný kandidát `game = "challenge"`, `engine = "drive"`,
  `local = false` (karta „Jízdní výzva“, cíl = dojet na místo).
- `distDm` – délka cesty v dm: start a cíl podle `specs/phone.md` („Navigace“), trasa
  `findRoute` ze `specs/route.md`, `distDm` = součet `polylineDm` hran trasy (délka, ne cena;
  úseky po hraně auta a po hraně spotu se nepočítají). Nedosažitelný cíl:
  `floor(sqrt(dx² + dy²)) × feed.straight_pct ÷ 100`, kde `dx, dy` je rozdíl celých dm
  (`floor(x × 10 + 0,5)`) mezi autem a parkovacím bodem spotu.
- `district` – jméno čtvrti, ve které leží bod spotu (`x, y`), nebo `""`.
- `landmark` – `true`, když v okruhu `feed.landmark_radius_dm` od bodu spotu leží památka, kterou
  hráč ještě neobjevil (`dx² + dy² ≤ r²` v celých dm). Dokud není Pas (M1 bod 9), neobjevená je
  každá památka.
- `visits` – kolikrát hráč na spot dojel (událost `arrived`).

## Stav

```
{
  deck: [{spot, game, engine, district, local, driveS, distDm, score, host, reward, difficulty}],
  at: index zobrazené karty,
  prefs: {engine: celé číslo v [prefMin, prefMax]},
  liked: [spot …],
  accepted: "" nebo spot přijaté karty,
  over: bool
}
```

## Config

```
{deckSize, novelty, prefStep, prefMin, prefMax, driveDmPerS, bandMinS, bandMaxS, bandPoints,
 nearPoints, bandFalloffS, districtBonus, landmarkBonus, jitter, hostLines, rewardBase,
 rewardPerMin, difficultyBase, difficultyMax,
 candidates: [{spot, game, engine, local, district, distDm, visits, landmark}],
 prefs: {engine: n}, visitedDistricts: [jméno …]}
```

Čísla jsou `feed.*` z tuningu (camelCase), `prefs` si klient nese z minulého balíčku
(na začátku `{}`), `visitedDistricts` jsou čtvrti, kde hráč už dojel na spot.

## Pravidla

`÷` je celočíselné dělení nezáporných čísel (dolů).

### init(config, seed)

1. `rng = Prng(seed)`; `prefs` = kopie `config.prefs`, každá hodnota oříznutá do `[prefMin, prefMax]`.
2. Pro každého kandidáta v pořadí configu:
   - `driveS = distDm ÷ driveDmPerS`
   - `band` = `nearPoints`, když `driveS < bandMinS`; `bandPoints`, když `driveS ≤ bandMaxS`;
     jinak `max(0, bandPoints − (driveS − bandMaxS) × bandPoints ÷ bandFalloffS)`
   - `score = (visits = 0 ? novelty : 0) + (prefs[engine] ?? 0) × prefStep + band`
     `+ (district ≠ "" a není ve visitedDistricts ? districtBonus : 0) + (landmark ? landmarkBonus : 0)`
     `+ rng.nextInt(jitter + 1)`
3. Pořadí: `score` sestupně, při shodě nižší index kandidáta.
4. Výběr: nejdřív nejlépe seřazený kandidát s `local = true` (je-li), pak nejlépe seřazený
   s `engine = "drive"` (je-li a není už vybraný); pak další v pořadí, dokud není `deckSize`
   karet (nebo kandidáti nedojdou). Když je `deckSize` menší než počet povinných, bere se jen
   prvních `deckSize` povinných. Vybrané karty se seřadí podle pořadí z bodu 3.
5. Pro každou kartu balíčku v tomto pořadí: `host = rng.nextInt(hostLines)` (klient ukáže
   `feedHost{host + 1}`), `reward = rewardBase + driveS × rewardPerMin ÷ 60`,
   `difficulty = min(difficultyMax, difficultyBase + visits)`.
6. `at = 0`, `liked = []`, `accepted = ""`, `over = (balíček je prázdný)`.

### Akce

`{"by": "player", "op": …}`; `legalActions` v pořadí `next`, `like` (jen když karta ještě není
v `liked`), `less`, `accept`; po `over` žádné.

- `next` (tah nahoru) – `at + 1`; když `at` = délka balíčku, `over = true`.
- `like` (dvojité klepnutí) – spot karty do `liked`, `prefs[engine] = min(prefMax, prefs[engine] + 1)`
  (chybějící klíč = 0); karta zůstává.
- `less` (tah vlevo) – `prefs[engine] = max(prefMin, prefs[engine] − 1)`, pak jako `next`.
- `accept` (tah vpravo nebo „Jedu“) – `accepted` = spot karty, `over = true`. Klient spustí
  navigaci ke spotu (`specs/phone.md`).

Jiná akce (neznámé `op`, `like` podruhé, cokoli po `over`) je nelegální.

### result(state)

Vždy `null` – feed není hra; výsledek je ve stavu (`accepted`, `prefs`).

## AI

Žádná.

## Hvězdy

Nejsou.

## Po balíčku (klient, P2)

Po poslední kartě nebo po přijetí feed ukáže „Běž si zajezdit“ a další karty nenabízí (žádné
nekonečné scrollování). Nový balíček se rozdá při dalším otevření feedu, až hráč od posledního
rozdání ujede `feed.redeal_m` nebo dojede do cíle. Seed balíčku volí klient náhodně; `prefs` se
přenášejí z posledního stavu do dalšího configu.

## Hraniční případy

- Žádný kandidát → prázdný balíček, `over = true`, feed rovnou ukáže „Běž si zajezdit“.
- Méně kandidátů než `deckSize` → balíček má všechny.
- Kandidát bez místní hry nebo jízdní výzvy ve městě → povinná karta se vynechá.
