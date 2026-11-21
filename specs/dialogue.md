# Dialogy NPC (skity)

**version: 1** · P0 · vektory `vectors/dialogue.json` · plán: METROPOLE_PLAN 11, R9; M1 bod 10 · parita F-021

## Účel

Krátké „pokecy“ s postavami: na ulici, v baru, v obchodě, po nehodě, s majitelem převzatého auta
a se soupeřem v minihře. Hra se dialogem nemění; jediný důsledek je ukazatel **vibe** u postavy
a šance, že si hráče postava uloží do telefonu jako **kontakt** (kontakty pak hostují karty feedu).
Žádné LLM za běhu (R9): pool je předpsaný a ručně prošlý.

> **Návrh k revizi Ol1nem.** Postavy (`content/npc/characters.yaml`) i všech 30 skitů
> (`content/npc/skits/*.yaml`) jsou první ručně psaný draft. Generátor `tools/dialoggen`
> (dávky přes LLM bránu na SPARKu + revizní UI) zatím není; až bude, nahradí nebo rozšíří tento pool.
> Portréty jsou zatím zástupné (iniciály v kruhu barvy z `design/tokens.json`), manga portréty
> přijdou z ComfyUI.

## Obsah

- **Postava**: `id`, `name` (vlastní jméno, nepřekládá se), `age` ≥ 21, `archetype`, `portrait`
  (index do `color.npc.portraits`), `tones` = celočíselná změna vibe za odpověď daného tónu,
  `bio`, `quips` = krátké hlášky soupeře na výsledkové obrazovce (`win` = hráč vyhrál, `lose`,
  `draw`).
- **Skit**: `id` (= jméno souboru), `character`, `context`, volitelně `city` (prázdné = všude),
  `beats` = přesně 5 replik NPC. Každá replika má `npc`, `replies` a `reactions`, obojí po tónech
  `flirt`, `joke`, `dry`.
- **Kontexty** (pevné pořadí): `street`, `bar`, `shop`, `minigame_win` (hráč soupeře porazil),
  `minigame_lose`, `crash`, `car_owner`.
- Text je objekt `{en, cs}` přímo v obsahu (vlastní formát místo `i18n/`, `docs/metro.md`).
  Mantinely obsahu: jen dospělí, žádní skuteční lidé ani značky (R10), žádné vtipy na národnost
  nebo původ (místní příchuť = místa, jídlo, počasí, doprava), nic explicitního, flirt hravý.
  Hráčovy repliky i oslovení hráče jsou v češtině bez rodu (žádné „byl/byla jsi“).

## Stav

```
rng: uint32           // PRNG ze specs/prng.md
recent: [skitId]      // fronta posledních skitů, nejstarší první, délka ≤ recentK
vibe: {characterId: int}   // všechny postavy z configu, start vibeStart
contacts: [characterId]    // v pořadí získání
skit: skitId | ""     // běžící skit, "" = nic neběží
character: characterId | ""   // postava běžícího nebo posledního skitu
beat: int             // počet odpovědí v běžícím / posledním skitu (0..beats)
tones: [tone]         // zvolené tóny v běžícím / posledním skitu
gained: int           // skutečná změna vibe v běžícím / posledním skitu (po ořezu)
last: skitId | ""     // poslední ukončený skit
completed: bool       // poslední ukončený skit došel do konce (ne „Odejít“)
newContact: bool      // poslední ukončený skit přinesl nový kontakt
```

## Config

```
{ city, recentK, vibeMax, vibeStart, contactMinVibe, contactBasePct, contactStepPct, contactMaxPct,
  characters: [{id, tones: {flirt, joke, dry}}],
  skits: [{id, character, context, city, beats}] }
```

Čísla jsou z `content/tuning.yaml` (`npc.*`), postavy a skity z obsahu. Klient skládá `skits`
seřazené podle `id` (porovnání po kódových jednotkách, id jsou `[a-z0-9_]`), `characters` v pořadí
z `characters.yaml`. Ve vektorech je pool syntetický, aby nezávisel na obsahu.

## Akce

- `{"by": "player", "type": "start", "character": c, "context": x}` – začni skit (jen když nic neběží),
- `{"by": "player", "type": "reply", "tone": "flirt" | "joke" | "dry"}` – odpověď na repliku,
- `{"by": "player", "type": "leave"}` – odejdi z běžícího skitu.

`legalActions`: když nic neběží, `start` pro každou postavu (pořadí configu) × kontext (pevné pořadí),
pro které existuje kandidát; během skitu `reply` flirt, joke, dry a pak `leave`. AI nehraje
(`aiAction` je chyba).

## Pravidla

`init(config, seed)`: `rng = Prng(seed)`, `vibe[c] = vibeStart` pro každou postavu, ostatní prázdné
(`skit = character = last = ""`, `beat = gained = 0`, `completed = newContact = false`).

**Výběr skitu** (`start`):

1. Kandidáti = skity configu (v jeho pořadí) s `character == c`, `context == x` a
   `city == "" nebo city == config.city`. Žádný kandidát → akce je nelegální.
2. Čerství = kandidáti, kteří nejsou v `recent`. Když nějací jsou: `skit = čerství[rng.nextInt(n)]`
   (spotřebuje se vždy, i pro n = 1).
3. Jinak (pool vyčerpaný, točí se dokola): skit = kandidát s nejmenším indexem v `recent`
   (nejdéle nehraný), bez spotřeby `rng`.
4. `recent`: vyjmi skit, pokud tam je, přidej ho na konec, pak odebírej ze začátku, dokud
   `délka > recentK`.
5. `character = c`, `beat = 0`, `tones = []`, `gained = 0`.

**Odpověď** (`reply`, jen během skitu): `d = tones[tón]` postavy;
`nový = clamp(vibe[c] + d, 0, vibeMax)`; `gained += nový − vibe[c]`; `vibe[c] = nový`;
`tones` += tón; `beat += 1`. Když `beat == beats` skitu, skit končí s `completed = true`:

- Kontakt jen když postava ještě není v `contacts` a `vibe[c] ≥ contactMinVibe`:
  `pct = min(contactMaxPct, contactBasePct + (vibe[c] − contactMinVibe) × contactStepPct)`,
  `roll = rng.nextInt(100)`; `roll < pct` → postava přibude do `contacts`, `newContact = true`.
  Jinak se `rng` nespotřebuje a `newContact = false`.

**Odejít** (`leave`): skit končí s `completed = false`, `newContact = false`, bez hodu na kontakt;
vibe zůstává, jak se do té doby změnila. Skit zůstává v `recent`.

Konec skitu vždy: `last = skit`, `skit = ""`.

## Výsledek

`result(state)` je `null`, když skit běží nebo když žádný ještě neskončil. Jinak
`{skit: last, character, completed, gained, vibe: vibe[character], contact: character ∈ contacts,
newContact}`. Hvězdy ani vítěz nejsou (dialog není minihra).

## Hláška soupeře (P0)

Minihra s `MinigameContext.opponentId` ukáže na výsledkové obrazovce jednu hlášku postavy:
`výsledek = winner == "player" → win, "ai" → lose, "draw" → draw`;
`hláška = quips[výsledek][Prng(seed).nextInt(délka)]` (`seed` partie z `MinigameContext`).
Pokryto unit testy v obou klientech se stejnými očekávanými hodnotami.

## UI (P2, obě strany stejně)

Komponenta dialogu, kterou si připojí jiné funkce (`startSkit(characterId, context)`):
portrét (iniciály na kruhu barvy `color.npc.portraits[portrait]`), jméno a věk, ukazatel vibe
(`vibe / vibeMax`), bubliny NPC (`color.npc.bubble`) a hráče (`color.npc.player`), tři tlačítka
odpovědí (text + štítek tónu) a „Odejít“. Po odpovědi přibude bublina hráče, reakce NPC podle tónu
a další replika. Na konci zpráva o kontaktu a „Hotovo“. Sezení (vibe, kontakty, fronta) drží klient
v paměti; ukládání přijde s M1 bodem 11.

Ladění: F tlačítko „Skity“ v ladicím panelu, W `?skits` – seznam postav × kontextů (`?skits=maya:street`
otevře skit rovnou). Galerie miniher má volbu soupeře (W `?opponent=<id>`) pro hlášku na výsledkové obrazovce.

## Hraniční případy

- Pool postavy pro kontext s jedním skitem: druhý `start` hned vrátí týž skit (točí se dokola).
- `recentK = 0`: fronta je vždy prázdná, výběr je vždy náhodný z kandidátů.
- vibe se ořezává na `0..vibeMax` u každé odpovědi; `gained` počítá jen skutečnou změnu.
- Postava, která už je v kontaktech, se na kontakt znovu nelosuje.
