# Kulečník 8-ball

**version: 1** · engine `flick` · P0 · vektory `vectors/kulecnik.json` · kontrakt
`specs/minigames/README.md` · fyzika `specs/minigames/fyzika.md` v1

## Účel

Osmička proti NPC v herně nebo baru (M2 bod 9, dávka C; METROPOLE_PLAN 9.4 č. 25). Pohled shora,
stůl na výšku. Hráč táhne od bílé: směr tahu je směr úderu, délka síla. Zjednodušená pravidla
bez falše a bez „koule do ruky“.

## Config

`content/tuning.yaml` → `minigames.kulecnik`; ve vektoru
`{tableW, tableH, ballR, pockets, rackDx, rackDy, rack, maxSpeed, dec, eBall, eCushion, maxSteps, aiCandidates, aiScatter, aiPowerBase, aiPowerPerM, starLeft}`.

| klíč | význam | default |
|---|---|---|
| `table_w`, `table_h` | hrací plocha (u = 0,01 mm), y nahoru, hráč láme zdola | 99000, 198000 |
| `ball_r` | poloměr koule | 2860 |
| `pockets` | kapsy po trojicích (x, y, poloměr zachycení), index 0–5 | `[0,0,5600, 99000,0,5600, 0,99000,4800, 99000,99000,4800, 0,198000,5600, 99000,198000,5600]` |
| `rack_dx`, `rack_dy` | rozteč koulí v trojúhelníku (vodorovně, mezi řadami) | 5740, 4972 |
| `rack` | čísla koulí v trojúhelníku po řadách zleva | `[1, 9, 2, 10, 8, 3, 11, 7, 14, 4, 5, 13, 15, 6, 12]` |
| `max_speed` | rychlost při síle 100 (u/krok) | 2500 |
| `dec` | zpomalení (u/krok²) | 4 |
| `e_ball`, `e_cushion` | odrazivost koule–koule, koule–mantinel (‰) | 950, 750 |
| `max_steps` | strop kroků na úder | 4800 |
| `ai_candidates` | kolik úderů AI zkusí, úroveň 1–5 | [3, 6, 12, 18, 24] |
| `ai_scatter` | rozptyl AI na normovaném míření (u), úroveň 1–5 | [3500, 2200, 1400, 800, 400] |
| `ai_power_base`, `ai_power_per_m` | síla AI = základ + za každý metr dráhy | 25, 30 |
| `star_left` | kolik koulí AI zbývá na stole pro 3★, 2★ | [4, 2] |
| `steps_per_frame` | kroků simulace na snímek (jen UI, 240 kroků/s) | 4 |
| `time_cap_s`, `ai_think_s` | strop a pauza před úderem AI (UI) | 600, 0.8 |

## Stůl

- Mantinely = čtyři statické obdélníky v tomto pořadí: levý `[−20000, 0] × [−20000, H + 20000]`,
  pravý `[W, W + 20000] × [−20000, H + 20000]`, dolní `[0, W] × [−20000, 0]`, horní
  `[0, W] × [H, H + 20000]` (`W = tableW`, `H = tableH`), odrazivost `eCushion`.
- Krok 2 fyziky (zachycení): koule `i` s `on`, jejíž střed je od středu kapsy `p` (v pořadí
  0–5) nejvýš na její poloměr (`dx² + dy² ≤ rp²`), spadne: `on = false`, rychlost 0, poloha
  zůstane. Zapíše se do `pots` (pořadí zachycení).
- Hmotnost všech koulí 1, poloměr `ballR`, odrazivost `eBall`, tření `dec` všude.
- Index koule = její číslo: 0 bílá, 1–7 plné, 8 černá, 9–15 půlené.
- **Rozestavení:** bílá na `headSpot = (W div 2, H div 4)`. Trojúhelník: řada `k` = 0–4 má
  `k + 1` koulí, koule `j` = 0–k má `x = W div 2 + (2j − k) × (rackDx div 2)`,
  `y = 3H div 4 + k × rackDy`; čísla bere `rack` po řadách (řada 0, pak 1 zleva…).

## Stav

```
{ balls, turn, playerGroup, shots, last, winner, over }
```

- `balls` = 16 × `{x, y, on}` (index = číslo koule).
- `turn` `"player"` | `"ai"`; `playerGroup` `""` (stůl otevřený), `"solid"`, `"stripe"`; skupina
  AI je ta druhá.
- `shots` počet odehraných úderů (0 = lámání); `last = {by, firstHit, pots, foul}` posledního
  úderu (na začátku `{by: "", firstHit: −1, pots: [], foul: false}`).
- `winner` `""` do konce, pak `"player"`, `"ai"` nebo `"draw"`.

## Akce

`{"by": "player" | "ai", "op": "shot", "x": int, "y": int, "power": int}` – bod míření (u) a síla
1–100; `{"by": "timeout"}`. Nelegální: strana mimo tah, po konci, síla mimo 1–100, bod míření
ve středu bílé. `legalActions` vrací prázdné pole.

## Úder

1. Bílé se nastaví rychlost podle „Úder“ ve fyzice (`sp = trunc(power × maxSpeed / 100)`), bez
   rozptylu. Simulace do klidu (`maxSteps`).
2. Při simulaci se zapíše `firstHit` = číslo první koule, se kterou se bílá srazila (první
   dvojice `(0, j)` v kroku 3, kde se rychlosti opravdu změnily, tj. `vn < 0`), jinak −1.
3. **Faul**, když: bílá spadla; nebo `firstHit = −1`; nebo (ne lámání) stůl otevřený a
   `firstHit = 8`; nebo skupina přidělená a `firstHit` není „cílová“ koule střelce = koule jeho
   skupiny, a pokud jich před úderem na stole nebylo, osmička. Na lámání jen první dva body.
4. **Osmička spadla:** při lámání se vrátí na `footSpot`. Jinak: když střelec neudělal faul a
   jeho skupina byla už **před** úderem celá dole, vyhrál; v ostatních případech prohrál.
   `over = true`, `winner`.
5. **Přidělení skupin:** stůl otevřený, ne lámání, bez faulu a v `pots` je koule 1–7 nebo 9–15
   → střelec dostane skupinu první takové koule v `pots`.
6. **Pokračuje** střelec, když neudělal faul a: při lámání spadla aspoň jedna koule (mimo
   bílou), jinak spadla aspoň jedna koule jeho skupiny (po přidělení). Jinak tah přejde.
7. Spadlá bílá se vrátí na stůl: zkouší se `(W div 2, H div 4 − n × rackDx)` pro n = 0, 1, …, 8;
   první místo, kde má každá koule s `on` od středu vzdálenost aspoň `2 × ballR` (`d2 ≥ (2r)²`),
   jinak n = 0. Osmička na `footSpot = (W div 2, 3H div 4)` stejně s `+ n × rackDy`.
8. `shots += 1`, `last` podle úderu.

`timeout`: `over = true`; při přidělených skupinách vyhrává strana s menším počtem svých koulí na
stole, shoda nebo otevřený stůl = `"draw"`.

## AI

Rozhoduje na kopii stavu, simulace bez rozptylu, rozpočet = počet zkoušených úderů:

1. **Lámání** (`shots = 0`): jediný kandidát = bod míření střed koule `rack[0]`, síla 100.
2. Jinak **cíle**: koule skupiny AI na stole vzestupně; když AI skupinu má a žádná na stole není,
   `[8]`; při otevřeném stole všechny koule 1–15 kromě 8 na stole vzestupně.
3. Pro každý cíl `T` (v pořadí) a kapsu `P` (0–5) **kandidát**: `L = isqrt(|P − T|²)`; `L = 0` se
   přeskočí; ghost `G = T − trunc((P − T) × 2r / L)` (po složkách); vzdálenost bílé
   `Lc = isqrt(|G − C|²)`, `Lc = 0` přeskočí; snadnost `ease = Lc + L`; síla
   `clamp(aiPowerBase + trunc(ease × aiPowerPerM / 100000), 15, 100)`; míření = `G`.
4. Kandidáti se stabilně seřadí podle `ease` vzestupně a vezme se prvních
   `aiCandidates[level − 1]`.
5. Každý se zahraje na kopii (celý úder včetně pravidel výše). Hodnota: výhra `+100000`, prohra
   `−100000`; jinak faul `−1000`, jinak `100 ×` počet spadlých koulí skupiny AI (po přidělení;
   při lámání všech mimo bílou) `+ 10`, pokud AI pokračuje. Vítězí nejvyšší, při shodě dřívější.
6. Rozptyl: z bodu míření vítěze se udělá normované míření (`AIM_R` z fyziky, od bílé) a přičte se
   `ex = ai.nextInt(2s + 1) − s`, pak `ey` stejně, `s = aiScatter[level − 1]`. Tyto dva tahy z
   `ai` jsou **vždy** (i při lámání). Výsledek `{by: "ai", op: "shot", x, y, power}`.
7. Bez kandidáta (všechny přeskočené): míření na střed prvního cíle, síla 50, rozptyl stejně.

## Výsledek a hvězdy

`{winner, stars, score, playerLeft, aiLeft}`: `playerLeft` / `aiLeft` = koule skupiny strany na
stole (otevřený stůl: 7 a 7). `score = 7 − playerLeft`. Výhra hráče: `aiLeft ≥ starLeft[0]` → 3★,
`≥ starLeft[1]` → 2★, jinak 1★; jinak 0★.

## UI

Stůl na výšku, tágo kreslené od bílé proti tahu prstu, vodicí čára do první koule (jen směr, bez
odrazů). Síla jako pruh. Simulaci kreslí krokováním (`steps_per_frame`), výsledek bere z `apply`.
Řádek nahoře: skupiny (`kulecnikSolids` / `kulecnikStripes` / `kulecnikOpen`), faul jako toast
`kulecnikFoul`.

## Hraniční případy

- Lámání nepřiděluje skupiny ani při spadlé kouli.
- Poslední koule skupiny a osmička v jednom úderu = prohra (skupina nebyla dole před úderem).
- Faul při spadlé osmičce (např. bílá taky spadla) = prohra.
- Úder s nulovou rychlostí (síla 1 a krátký směr) je legální; `firstHit = −1` → faul.

## Upřesnění v1

- `firstHit`: první dvojice `(0, j)` v kroku 3 se `0 < d2 < R²` a `vn < 0` (i když `k` vyjde 0);
  v jednom kroku tedy nejnižší `j`. Srážky dvou jiných koulí se nepočítají a pozdější srážky
  bílé `firstHit` nemění.
- `pots`: v pořadí kroků, v kroku podle indexu koule; koule padá do první kapsy (0–5), která ji
  zachytí.
- Faul i cíl se posuzují podle stavu **před** úderem (skupina střelce, jeho koule na stole).
  Spadlá osmička mimo lámání při otevřeném stole je prohra střelce i bez faulu.
- Body 4–8 se provedou vždy, i když úder hru ukončil: skupina se ještě přidělí (bod 5), `turn`
  se spočte podle bodu 6 (po vítězné osmičce tedy přejde na soupeře, osmička do skupiny
  nepatří) a spadlá bílá se vrátí.
- Při lámání se do „aspoň jedna koule mimo bílou" počítá i osmička (vrácená na `footSpot`).
- Bod 7: nejdřív se vrací bílá, potom osmička; vrácená koule má `on = true` a už vrácená bílá je
  pro osmičku překážkou. Bílá zkouší `y = H div 4 − n × rackDx` (míří ke spodní hraně).
- `timeout` změní jen `over` a `winner`; `turn`, `shots` a `last` zůstanou.
- `result.winner` = `winner` ze stavu.
- AI: kandidáti se zkoušejí jako úder strany `"ai"` bez ohledu na `turn`. Hodnota: `over` po
  úderu → `+100000` při `winner = "ai"`, jinak `−100000`; počet koulí skupiny AI se bere podle
  skupiny AI **po** úderu (přidělení v tomtéž úderu se započte; otevřený stůl po úderu = 0);
  „AI pokračuje" = `turn = "ai"` po úderu.
- Bez kandidáta (bod 7) se míří na první cíl ze seznamu bodu 2; normované míření AI vždy od
  středu bílé a z `ai` vždy právě dvě čísla (`ex`, pak `ey`).
