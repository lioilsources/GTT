# Tuning a kosmetika (M2-S7)

**version: 1** · P0 nákup vylepšení a vzhledu (`vectors/garage.json`) · P1 účinek na jízdu,
kreslení, garáž · METROPOLE_PLAN 10 (sloty auta), M2 bod 7 a N5 · parita F-044 · uložení
`specs/save.md` v4 (formát 5)

## Účel
Za hotovost si hráč v garáži vylepší vlastní auto (motor, pneumatiky, brzdy, odlehčení, drift)
a změní jeho vzhled (lak, polep, kola, podsvícení, barva kouře). Vylepšení mění jízdu
měřitelně, vzhled jen kresbu. Čísla jsou v `content/tuning.yaml` → `garage`, texty v `i18n/`
(`garage*`), barvy v `design/tokens.json` → `color.garage`. Vypíná se `garage.enabled`
(tabulky Tuning a Vzhled se pak neukážou).

## Sloty a úrovně
- Sloty auta jsou `tuning_slots` z `content/cars/<id>.json` (`engine`, `tyres`, `brakes`,
  `weight`, `drift`; auta třídy `micro` mají prázdný seznam a vylepšit nejdou). Každý slot má
  úroveň 0 až `garage.max_level` (3).
- Cena další úrovně: `garage.price_<slot>[lvl]` (seznam délky `max_level`, ceny 1 000–8 000 podle
  N5), kde `lvl` je současná úroveň. Kupuje se jen další úroveň, prodat ani snížit nejde.

## Vzhled
Části (pevné pořadí): `paint`, `decal`, `wheels`, `glow`, `smoke`. Hodnota je index volby, 0 =
výchozí:
- `paint` – 0 = lak auta z katalogu (`paint`, `color.carPaint`), `i ≥ 1` = `color.garage.paints[i − 1]`.
- `decal` – 0 bez polepu, 1 pruhy, 2 plameny, 3 šachovnice (kreslí se procedurálně, barva
  `color.garage.decal`).
- `wheels` – 0 původní, 1 sportovní, 2 bílé obruče (`color.garage.wheels[value]`).
- `glow` – 0 bez podsvícení, `i ≥ 1` = `color.garage.glow[i − 1]` (záře pod autem).
- `smoke` – 0 výchozí, `i ≥ 1` = `color.garage.smoke[i − 1]`. Klienti kouř při driftu zatím
  nekreslí (jen stopy smyku), takže v1 se volba **jen ukládá a ukazuje v garáži**; kreslit se
  začne s kouřem.
- Počet voleb části = `parts[part]`: `paint` 1 + počet `paints`, `decal` 4, `wheels` 3, `glow` a
  `smoke` 1 + počet barev. Cena volby `i ≥ 1` = `garage.look_price_<part>`, návrat na 0 je zdarma.
  Vzhled jde měnit u všech vlastních aut (i `micro`).

## Stav (P0, modul `garage`)
```
config: {cars: {carId: [slot]}, maxLevel, prices: {slot: [int]}, parts: {part: int},
         lookPrices: {part: int}}
state:  {upgrades: {carId: {slot: lvl}}, looks: {carId: {part: value}}, last: {op, amount}}
```
- `cars` – všechna auta katalogu s jejich `tuning_slots` (v pořadí z JSON). Vlastnictví hlídá UI
  (jako `specs/cars.md`: „kde smí hráč akci udělat, hlídá UI“); garáž nabízí jen vlastní auta.
- Ve stavu jsou jen nenulové hodnoty: slot s úrovní 0 a část s hodnotou 0 v mapě nejsou, auto bez
  nich také ne. Klíče map se při porovnání řadí.
- `last` – poslední nákup: `op` (`""`, `upgrade`, `look`) a `amount` (zaplaceno).
- `init(config, seed)`: `upgrades = {}`, `looks = {}`, `last = {op: "", amount: 0}`; `seed` se
  nepoužívá.

## Akce
Všechny `by: "player"`, čísla celá:
- `{op: "load", upgrades, looks}` – stav z uložení. Zahodí auta mimo `cars`, sloty mimo sloty
  auta, části mimo `parts`; úroveň se ořízne do 0…`maxLevel`, hodnota části mimo
  0…`parts[part] − 1` se zahodí (= 0); nuly se vynechají. `last` prázdné. Hodnota, která není celé
  číslo, nebo mapa, která není objekt = nelegální.
- `{op: "upgrade", car, slot, cash}` – nelegální, když `car ∉ cars`, `slot` není slot auta,
  úroveň je už `maxLevel`, `cash < 0` nebo `cash < price` (`price = prices[slot][lvl]`). Jinak úroveň
  +1, `last = {op: "upgrade", amount: price}`.
- `{op: "look", car, part, value, cash}` – nelegální, když `car ∉ cars`, `part ∉ parts`, `value`
  mimo 0…`parts[part] − 1`, `value` = současná hodnota, `cash < 0` nebo `cash < price`
  (`price = 0` pro `value = 0`, jinak `lookPrices[part]`). Jinak nastaví hodnotu,
  `last = {op: "look", amount: price}`.

`legalActions(state)`: `load` s `{}` a `{}`; pak pro auta v pořadí id (řazení po kódových
jednotkách) `upgrade` každého slotu pod `maxLevel` s `cash = price` (pořadí slotů auta); pak pro
auta v pořadí id a části v pevném pořadí `look` s každou hodnotou ≠ současné, `cash = price`.
`result` vždy `null`, `aiAction` neexistuje.

## Hotovost
Jako obchody (`specs/shops.md`): klient vezme `cash` ze stavu aut (`specs/cars.md`), pošle ho
v akci, po akci odečte `last.amount` a zapíše zpět, pak uloží. Ekonomika (`specs/economy.md`) se
nemění: nákupy v garáži (auto přes `cars.buy`, vylepšení a vzhled přes `garage`) do ní nepatří,
ta řeší jen odměnu, odtah a pokutu.

## Účinek na jízdu (P1)
Efektivní parametry auta = parametry z katalogu × násobiče podle úrovní (`l` = úroveň slotu):
- `engine`: `power × (1 + engine_power_step × l)`, `top_speed × (1 + engine_top_step × l)`;
- `tyres`: `grip_front` i `grip_rear` × `(1 + tyres_step × l)`;
- `brakes`: `brake × (1 + brakes_step × l)`;
- `weight`: `mass × (1 − weight_mass_step × l)`, `power × (1 + weight_power_step × l)`,
  `steer_speed × (1 + weight_steer_step × l)`;
- `drift`: `drift_bias × (1 − drift_step × l)` (zadní grip při ruční brzdě, menší = delší smyk).

Násobiče jednoho parametru se násobí mezi sebou. Oba klienti exportují čistou funkci
`tunedSpec(spec, levels, tuning)`. Pravidla jízdy (`specs/drive.md`), jejich scénáře a vektory
se nemění: klient jen postaví těleso auta z efektivních parametrů. Stává se to při vyjetí
z garáže, přesednutí do vlastního auta, respawnu a startu hry. Garáž svět zastaví, takže auto
s novými úrovněmi se po zavření garáže postaví znovu na tomtéž místě se stejnou rychlostí 0.
Grip z počasí (`specs/weather.md`, `gripScale`) se násobí s gripem pneumatik.
Vylepšení mají jen vlastní auta. Cizí (ukradené) auto, provoz, hlídky a tramvaje jedou podle
katalogu.

**Akceptace (M2_NYC.md „tuning mění jízdu měřitelně“):** oba klienti mají test nad čistou jízdou
(drive_core, web `drive`). Plný plyn z 0 na rovině: auto s `engine` 3 dosáhne 25 m/s aspoň o 10 %
dřív než základní. Plná zatáčka při 15 m/s po 3 s: auto s `tyres` 3 má aspoň o 5 % menší poloměr
(nebo menší boční skluz).

## Garáž (P1)
- U garáže (`specs/cars.md`) má seznam garáže záložky **Auta** (dosavadní výběr a nákup aut),
  **Tuning**, **Vzhled** a **Polička** (suvenýry, `specs/shops.md`). Svět stojí jako dosud.
- **Tuning:** pro řízené vlastní auto (nebo vybrané ze seznamu) řádek na slot: jméno
  (`garageSlot<Slot>`), ukazatel úrovně (`color.garage.level`, prázdné `color.garage.levelEmpty`),
  řádek účinku (`garageEffect<Slot>` s procentem při další úrovni) a tlačítko `garageUpgrade`
  s cenou. Na maximu `garageMaxed`, na málo hotovosti šedé s `garageNoCash`. Auto bez slotů ukáže
  `garageNoSlots`.
- **Vzhled:** živý náhled auta shora (kreslí se stejně jako ve světě, s vybranou volbou), pro
  každou část řada voleb (barevné kroužky, u `decal` a `wheels` názvy `garageDecal*`,
  `garageWheels*`), u vybrané cena a tlačítko `garageLookBuy`; současná volba je označená. Volba 0 je
  zdarma.
- Po nákupu toast `garageBought` a uložení.
- Aplikace **Garáž** v telefonu (`specs/phone.md`) ukazuje vlastní auta s úrovněmi a vzhledem jen
  ke čtení a Poličku; nakupuje se jen u garáže.

## Kreslení (P1)
- `paint` mění barvu karoserie (sklo zůstává lak + 12 % bílé). Zaparkované vlastní auto, které
  hráč odstavil, se kreslí se svým vzhledem; ostatní zaparkovaná auta a provoz podle katalogu.
- `decal`: pruhy = dva podélné pruhy ±0,22 `hw` přes celé auto; plameny = tři trojúhelníky od
  přídě do 0,35 `hl`; šachovnice = pás čtverců na obou bocích. Barva `color.garage.decal`; muscle a
  taxi mají své detaily pod polepem.
- `wheels`: barva ráfku `color.garage.wheels[value]`.
- `glow`: zaoblený obdélník o `garage.glow_margin_m` větší než auto pod stínem, barva s alfou,
  jen v noci nebo v tunelu plnou silou, ve dne × `garage.glow_day`.

## Uložení
`specs/save.md` v4 (formát 5): `upgrades: {carId: {slot: int}}`, `looks: {carId: {part: int}}`,
obě nepovinné (chybí = `{}`). Po startu `load` z uložení, po každém nákupu uložení.

## Hraniční případy
- Auto z uložení, které už v katalogu není: `load` ho zahodí.
- Auto, které ztratí slot v katalogu: úroveň slotu se zahodí.
- Méně barev v tokenech než index ve vzhledu: `load` hodnotu zahodí (výchozí).
- Garáž bez hotovosti: tlačítka šedá, návrat vzhledu na 0 jde vždy.
