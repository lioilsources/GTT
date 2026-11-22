# Policie a hledanost (M1-S4)

**version: 1** · P0 pravidla hledanosti (`vectors/police.json`) · P1 hlídky, dohled, honička ·
METROPOLE_PLAN 7.4, R7, M1 bod 4 · parita F-024

## Účel
Svět reaguje na přestupky: hlídka, která hráče vidí, mu zvedne hledanost a honí ho. Hráč uteče,
když ho žádná hlídka chvíli nevidí; když ho hlídka dostihne stojícího, zaplatí pokutu. Žádné
násilí (R7): žádné střílení, žádné rozbíjení, dopadení je jen karta „Dopaden“ a pokuta.
M1 měla hledanost 1–2, M2 zvedá strop na 3 (`police.max_level`; pravidla se nemění, vektory mají
i případy se stropem 3). Zátaras na úrovni 3 je ve `specs/roadblock.md`.
Čísla jsou v `content/tuning.yaml` → `police`, texty v `i18n/` (`police*`), barvy v
`design/tokens.json` → `color.police`. Vypíná se `police.enabled`.

## Stav (P0, modul `police`)
Pravidla běží v celých **tikách** (`police.tick_hz` tiků za sekundu). Klient převede sekundy
z tuningu na tiky `round(s · tick_hz)` a předá je v konfiguraci.
```
config: {maxLevel, escapeTicks, captureTicks, hitRunTicks, cooldownTicks,
         levels: {crash, hitrun, sidewalk, theft}, fines: [int]}
state:  {level, unseen, capture, hitRun, hitRunSeen, cool: {crash, hitrun, sidewalk, theft},
         offences, last, busted, fined}
```
- `levels[k]` – hledanost, kterou přestupek `k` dá z nuly (`police.offence_level`).
- `fines[l]` – pokuta při dopadení na hledanosti `l` (`police.fines`, index = úroveň).
- `level` 0…`maxLevel`. `unseen` – tiky v kuse mimo dohled. `capture` – tiky v kuse u hlídky.
- `hitRun` – zbývající tiky okna „ujetí“ po nárazu (0 = žádné), `hitRunSeen` – náraz viděla hlídka.
- `cool[k]` – zbývající tiky, než se přestupek `k` počítá znovu.
- `offences` – počet započtených přestupků, `last` – druh posledního (`""` na začátku).
- `busted` – počet dopadení, `fined` – součet pokut (hotovost přijde s M1-S11).
- `init`: všechno 0, `false`, `""`; `seed` se nepoužívá.

## Akce
Všechny mají `by: "player"` (jsou to pozorování hráčova chování, ne tahy soupeře):
- `{op: "offence", kind, seen}` – přestupek `kind ∈ {crash, hitrun, sidewalk, theft}`;
  `seen` = vidí ho právě teď aspoň jedna hlídka (viz Dohled).
- `{op: "tick", seen, near, away}` – jeden tik: `seen` – hráče vidí hlídka; `near` – hlídka je
  u pomalého hráče (viz Dopadení); `away` – hráč je dál než `police.hit_run_m` od místa
  posledního nárazu.

## Pravidla
**Započtení přestupku** `commit(k, seen)`: když `seen` a `cool[k] = 0`, pak
`level = min(maxLevel, max(levels[k], level > 0 ? level + 1 : 0))`, `offences += 1`, `last = k`,
`cool[k] = cooldownTicks`, `unseen = 0`. Jinak se nic nemění.

`offence(kind, seen)`:
1. Neznámý `kind` = `IllegalAction`.
2. Je-li `kind = crash`: `hitRunSeen = (hitRun > 0 a hitRunSeen) nebo seen`, `hitRun = hitRunTicks`.
3. `commit(kind, seen)`.
   Přímo poslaný `hitrun` jde jen přes `commit` (klient ho sám neposílá, vzniká v tiku).

`tick(seen, near, away)` v tomto pořadí:
1. Každé `cool[k] = max(0, cool[k] − 1)`.
2. Ujetí: když `hitRun > 0`: je-li `away`, pak `hitRun = 0`, `s = seen nebo hitRunSeen`,
   `hitRunSeen = false` a `commit(hitrun, s)`; jinak `hitRun −= 1` a při 0 `hitRunSeen = false`.
3. Když `level = 0`: `unseen = 0`, `capture = 0`, konec tiku.
4. Dopadení: `capture = near ? capture + 1 : 0`. Když `capture ≥ captureTicks`:
   `fined += fine(level)`, `busted += 1`, `level = 0`, `unseen = 0`, `capture = 0`, `hitRun = 0`,
   `hitRunSeen = false`, všechna `cool[k] = cooldownTicks` (chvíle klidu), konec tiku.
5. Únik: `unseen = seen ? 0 : unseen + 1`; když `unseen ≥ escapeTicks`: `level −= 1`, `unseen = 0`.
   Únik tedy sníží hledanost o jednu; z 2 na 0 trvá dvakrát `escape_s` (10 s podle plánu).

`fine(level) = fines[min(level, len(fines) − 1)]` (čistá funkce, oba klienti ji exportují).

`legalActions(state)`: všechny akce, které jdou poslat – `offence` pro každý druh v abecedním
pořadí, nejdřív `seen = false`, pak `true`; potom 8 tiků v pořadí bitů (`seen`, `near`, `away`)
od `000` do `111`. `result` je vždy `null`, `aiAction` neexistuje.

## Události (háčky pro další feature)
Klient po každé akci porovná stav před a po:
- `wantedChanged {level, prev, reason}` – změna `level`; `reason` = druh přestupku, `escape`
  (únik) nebo `busted`. API `wantedLevel`, `onWantedChanged`.
- `offence {kind}` – přibyl `offences`; HUD ukáže důvod (`policeReason_<kind>`).
- `fined {amount}` – přibyl `busted`; `amount` = přírůstek `fined`. Hotovost (M1-S11) ho odečte.
  API `onFined`. Hráč zůstává na místě (žádný respawn), hlídky přestanou honit.

## Přestupky v klientovi (P1)
- **Náraz** – událost provozu „auto trefené hráčem“ (`traffic.onHit`, i do policejního auta);
  klient si zapamatuje místo nárazu (pro `away`).
- **Chodník** – hráč ve vrstvě 0 jede aspoň `sidewalk_min_mps` a jeho střed je v pásu chodníku
  nějaké ponechané hrany na zemi (`carriageHalf + sidewalk_margin_m < d ≤ width/2`) a zároveň
  není na vozovce žádné jiné (`d ≤ carriageHalf + sidewalk_margin_m`), hledá se do
  `width/2`. Když to trvá v kuse `sidewalk_s`, pošle se jeden přestupek; další až po sjetí z chodníku.
- **Cizí auto** – událost aut `stolen` (`fleet.on('stolen')` / `onStolen`).
- **Ujetí** – vzniká v pravidlech z nárazu a `away` (výše).

## Dohled (P1)
Hlídka vidí hráče, když: obě auta jsou buď v tunelu, nebo obě mimo tunel (vrstva < 0 ↔ < 0),
vzdálenost středů ≤ `police.view_m` a úsečku mezi středy nekříží žádná hrana obrysu kolidující
budovy (`collide`) z načtených chunků (napřed hrubý test kružnicí `cx, cy, radius`). Zaparkovaná
auta ani stromy výhled neblokují. Dohled se počítá v každém tiku a v okamžiku přestupku.

## Hlídky (P1)
- Hlídka je auto provozu s příznakem `police` (stejné kinematické těleso, stejné jízdní chování).
  Klient chce mít `police.patrols[level]` hlídek. Chybí-li, každých `pick_interval_s` označí
  jedno auto provozu (v pořadí seznamu aut), které je od hráče aspoň `pick_min_m` (víc než
  `view_m`, takže ho hráč nevidí „proměnit se“). Hlídky navíc se neodebírají, zmizí s provozem (`despawn_m`, reset).
- **Honička:** když `level > 0` a hlídka je do `pursuit_m`, má `pursuing = true`, cíl = hráč,
  rychlost `min(pursuit_mps[level], sqrt(2 · brake_mps2 · max(0, d − capture_m / 2)))`, kde `d`
  je vzdálenost k cíli (hlídka u hráče zabrzdí a zůstane stát vedle něj). V honičce: nečeká na semafory, nečeká za jinými auty provozu
  (sirény; auta se nesrážejí, jen překryjí), zato zastaví za hráčem (mezera jako u provozu).
  Na konci hrany volí hranu směrem k cíli (`chooseToward`) a smí proti jednosměrce.
  Je-li cíl za hlídkou (`dot(směr, cíl − poloha) < 0`) dál než `uturn_m`, hlídka se otočí na
  místě hrany (`dir = −dir`, `s = délka − s`), nejvýš jednou za `uturn_s`. Silnice neopouští.
- `chooseToward(graph, node, from, gx, gy)`: kandidáti = ponechané hrany v uzlu (bez duplicit a
  smyček, vzestupně podle indexu), z nichž lze vyjet ve kterémkoli směru, včetně `from` (otočka).
  Vyhrává největší `dot(u, g)`, kde `u` je jednotkový směr hrany z uzlu k prvnímu odlišnému bodu
  a `g` jednotkový směr z uzlu k cíli; při shodě první. Hraniční uzel = −1 (hlídka zmizí).
- **Dopadení:** `near` = `level > 0`, hráč jede nejvýš `capture_mps` a některá hlídka je do
  `capture_m` (ve stejné vrstvě). Za `capture_s` v kuse → dopadení.

## Kreslení a HUD (P2)
- Hlídka shora jako auto provozu: karoserie `police.body`, dveře `police.door`, na střeše
  maják `police.bar` s dvěma světly (`police.lightRed`, `police.lightBlue`), která se při honičce
  střídají po `light_blink_s`; bez honičky svítí tlumeně (`police.lightOff`).
- HUD nahoře uprostřed: `max_level` odznaků, plné `police.star`, prázdné `police.starEmpty`
  (jen když `level > 0`). Při přestupku krátký toast s důvodem (`toast_s`), při úniku
  `policeEscaped`, při dopadení karta `policeBusted` + `policeFine` (`busted_s`).

## Hraniční případy
- Přestupek, který nikdo neviděl, hledanost nezvedne (náraz ale otevře okno ujetí).
- Hráč po nárazu zůstane stát do konce okna `hit_run_s`: žádné ujetí.
- Hledanost na stropu: další přestupky ji nezvednou, ale počítají se (`offences`, toast).
- Po dopadení `cooldown_s` klidu, než se stejný přestupek znovu počítá.
- Respawn hráče a reset provozu zahodí hlídky; hledanost zůstane a nové hlídky se označí.
- `police.enabled = false`: žádné hlídky, žádné přestupky, HUD skrytý.
- Hledanost na stropu 3 a další přestupek: zůstane 3, toast se ukáže.
