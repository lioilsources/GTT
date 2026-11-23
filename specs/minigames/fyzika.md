# Celočíselná fyzika miniher

**version: 1** · P0 · sdílená část pro `kulecnik`, `bowling`, `minigolf`, `cihly`, `hokej` ·
kontrakt `specs/minigames/README.md` · vektory hlídají hry, které ji používají

## Účel

Koule, puky a kuželky se v obou klientech musí pohybovat bit po bitu stejně, jinak vektory
neprojdou. Proto žádná desetinná čísla: polohy a rychlosti jsou celá čísla, simulace běží
v pevných krocích a každý vzorec níže je předepsaný včetně zaokrouhlení. Hry z této části
skládají svůj „svět“ a doplní vlastní pravidla (jamky, góly, kuželky).

## Jednotky a aritmetika

- Délka v `u`; co je `u`, určí hra (kulečník, bowling, minigolf: 1 u = 0,01 mm; cihly a hokej
  abstraktní jednotky hřiště). Rychlost v `u` za krok, zpomalení v `u` za krok na krok.
- `trunc(a / b)` = podíl zaokrouhlený k nule (Dart `~/`, TS `Math.trunc(a / b)`). Jiné dělení
  se v P0 kódu nepoužívá.
- `isqrt(n)` pro `n ≥ 0` = největší celé `s` se `s² ≤ n`. TS: `s = Math.floor(Math.sqrt(n))`,
  pak oprava `while (s*s > n) s--; while ((s+1)*(s+1) <= n) s++`. Dart stejně přes `sqrt`
  a opravu. Výsledek musí být přesný.
- Všechny mezivýsledky níže zůstávají pod `2^53` (ověřeno pro rozměry v tuningu her); hra,
  která rozměry zvětší, to musí přepočítat.
- `clamp(v, lo, hi)` = `min(max(v, lo), hi)`.

## Tělesa a statika

- **Těleso**: `{x, y, vx, vy, r, m, on}` – poloha středu, rychlost, poloměr, hmotnost (celé
  ≥ 1), `on = true` dokud je ve hře (spadlá koule, sražená kuželka mimo dráhu: `false`; takové
  těleso se nehýbe a nic s ním nekoliduje).
- **Statický obdélník** `[x0, x1] × [y0, y1]` a **statický kruh** `(cx, cy, R)` – nekonečná
  hmotnost, nehýbou se.

## Krok simulace

Hra volá `step(world)` po jednom kroku. Pořadí je pevné:

1. **Pohyb:** každé těleso s `on` v pořadí indexů: `x += vx`, `y += vy`.
2. **Zachycení** (jamky, góly, voda – podle hry): hra projde tělesa v pořadí indexů a může je
   vypnout (`on = false`, `vx = vy = 0`).
3. **Srážky těleso–těleso:** dvojice `(i, j)`, `i < j`, lexikograficky (nejdřív `i`, pak `j`),
   obě `on`. Viz níže.
4. **Srážky se statikou:** každé těleso s `on` v pořadí indexů, pro něj každý statický objekt
   v pořadí seznamu hry.
5. **Tření:** každé těleso s `on` (zpomalení podle hry, může záviset na místě – písek).

Klient smí kreslit mezikroky jen čtením stavu po celém kroku; počet kroků na snímek je číslo
v tuningu (`steps_per_frame`), pravidla ho neznají.

## Srážka dvou těles

`dx = xj − xi`, `dy = yj − yi`, `d2 = dx² + dy²`, `R = ri + rj`. Nic se neděje, když
`d2 ≥ R²` nebo `d2 = 0`. Jinak `vn = (vxj − vxi)·dx + (vyj − vyi)·dy`; při `vn ≥ 0` (vzdalují
se) nic. Jinak s odrazivostí `e` (promile, hra):

```
k   = trunc(vn × (1000 + e) × 1000 / ((mi + mj) × d2))
vxi += trunc(k × mj × dx / 1000000);  vyi += trunc(k × mj × dy / 1000000)
vxj −= trunc(k × mi × dx / 1000000);  vyj −= trunc(k × mi × dy / 1000000)
```

(`vn` je záporné, takže `k ≤ 0`: těleso `i` dostane rychlost proti směru k `j`, `j` od `i`.)
Polohy se nemění; překryv se rozplete sám, protože tělesa se už vzdalují.

## Srážka se statikou

Nejbližší bod `q` statiky ke středu tělesa: obdélník `qx = clamp(x, x0, x1)`,
`qy = clamp(y, y0, y1)`; kruh `q = (cx, cy)`. `dx = x − qx`, `dy = y − qy`, `d2 = dx² + dy²`.
Dotyk: obdélník `0 < d2 < r²`, kruh `0 < d2 < (r + R)²`. `vn = vx·dx + vy·dy`; při `vn ≥ 0` nic.
Jinak s odrazivostí `e` (promile, podle hry a druhu statiky):

```
k  = trunc(vn × (1000 + e) × 1000 / d2)
vx −= trunc(k × dx / 1000000);  vy −= trunc(k × dy / 1000000)
```

Rovná stěna tak odráží jen kolmou složku, roh a kruh podle spojnice. Střed uvnitř obdélníku
(`d2 = 0`) se ignoruje; hry volí rozměry a rychlosti tak, aby nenastal (pohyb za krok `<` poloměr).

## Tření

Se zpomalením `dec ≥ 0`: `s = isqrt(vx² + vy²)`. `s ≤ dec` → `vx = vy = 0`. Jinak
`vx −= trunc(vx × dec / s)`, `vy −= trunc(vy × dec / s)`.

## Úder

Z bodu míření `(ax, ay)` a síly: `dx = ax − x`, `dy = ay − y`, `L = isqrt(dx² + dy²)`; `L = 0`
je nelegální akce. Rychlost `sp` podle hry, pak `vx = trunc(sp × dx / L)`,
`vy = trunc(sp × dy / L)`.

**Normované míření** (kde hra přidává rozptyl): bod se nejdřív přenese do vzdálenosti
`AIM_R = 100000` u: `ax' = x + trunc(dx × 100000 / L)`, `ay'` stejně; rozptyl se přičte k
`(ax', ay')`, a teprve z něj se počítá rychlost (znovu přes `isqrt`).

## Konec simulace úderu

Hry s údery (`kulecnik`, `bowling`, `minigolf`) volají `step`, dokud mají všechna tělesa s `on`
nulovou rychlost, nejvýš `max_steps` kroků; po posledním kroku se zbylé rychlosti vynulují.
Počet kroků ani rychlosti nejsou ve stavu: stav po úderu obsahuje jen polohy a `on`.

## Hraniční případy

- Dvě srážky téhož tělesa v jednom kroku se počítají postupně v pořadí výše, každá už
  s rychlostí po té předchozí.
- `trunc` záporných čísel jde k nule (`trunc(−7 / 2) = −3`), ne dolů.
- Rychlost `0` a dotyk: `vn = 0` → nic (stojící koule u mantinelu zůstane).
