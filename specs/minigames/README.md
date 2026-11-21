# Kontrakt miniher

**version: 1** · platí pro všechny `specs/minigames/<id>.md` · plán: METROPOLE_PLAN 9.1–9.2, DUALSTACK 5.4, 6.5

## Dvě vrstvy

1. **Pravidla** – čistý modul bez UI, stejný tvar v obou klientech:

   ```
   init(config, seed)          -> State
   legalActions(state)         -> Action[]
   apply(state, action)        -> State      // čistá funkce
   aiAction(state, level, ai)  -> Action     // ai = PRNG soupeře
   result(state)               -> null | Result
   ```

   F: balíček `packages/mg_<id>` (`lib/src/rules.dart`), W: `web/src/minigames/<id>/rules.ts`.
2. **Hra** – UI nad pravidly, obalené kontraktem:
   - F: `Minigame` z `packages/mg_api` (`meta`, `build(ctx, onFinish)`),
   - W: `Minigame` z `web/src/minigames/api.ts` (`meta`, `mount(host, ctx, onFinish) → unmount`).

   `meta` je `minigameCatalog[id]` (generuje `metro gen` z `content/minigames/catalog.yaml`).
   `MinigameContext` a `MinigameResult` jsou typy ze `schema/minigame.schema.json`.

## Stav a náhoda

- Stav i akce jsou JSON: jen celá čísla, řetězce, booleany, pole a objekty (bez `null` uvnitř stavu).
- **Náhoda pravidel** (rozdávání, kostky, délka kola) žije ve stavu jako pole `rng` (uint32 stav
  PRNG ze `specs/prng.md`). `init` začne `Prng(seed)`; `apply` si z `rng` vytvoří generátor,
  použije ho a nový stav uloží zpět. Pořadí volání je součást specifikace hry.
- **Náhoda soupeře** je zvláštní proud: `ai = Prng(seed XOR 0x5BD1E995)`, jeden na partii,
  sdílený všemi tahy AI. `aiAction` smí volat jen `ai`, nikdy `rng` ze stavu.
- Úroveň AI = `MinigameContext.difficulty` (1–5). Rozpočet AI v hloubce nebo počtu iterací, nikdy v čase.
- Při shodě hodnocení vyhrává první akce v pořadí `legalActions`.

## Akce

Každá akce je objekt s polem `by`:

- `{"by": "player", …}` – tah hráče (pole podle hry),
- `{"by": "ai", …}` – tah soupeře (stejná pole jako hráč),
- `{"by": "timeout"}` – vypršel časový strop (9.2: tvrdý strop 10 min, hra může mít nižší).
  Čas měří UI, pravidla dostanou jen tuto akci a rozhodnou podle stavu.

## Výsledek

`result(state)` je `null`, dokud hra běží. Potom objekt aspoň s poli `stars` (0–3), `score` (celé
číslo) a `winner` (`"player"`, `"ai"`, nebo `"draw"`); hra může přidat vlastní. UI z něj složí
`MinigameResult` (`playedMs` a `aborted` doplní samo; přerušená hra má `stars: 0`).

## Vektory

`vectors/<id>.json`, formát `schema/vector.schema.json`. Přehrání případu:

```
ai = Prng(seed XOR 0x5BD1E995)
state = init(config, seed)
pro každý krok:
  action = krok.action
  pokud action.by == "ai" a action nemá další pole kromě "level":
      action = aiAction(state, action.level, ai)
  state = apply(state, action)
  porovnej toJson(state) s krok.state (klíče seřazené)
na konci porovnej result(state) s case.result
```

Hráčovy tahy jsou ve vektoru vypsané celé; tahy AI jen jako `{"by": "ai", "level": L}`, takže
vektor hlídá i rozhodování AI. Nahrává vedoucí klient (`metro vectors record`).

## UI (obě strany stejně)

- na výšku, jednou rukou, pauza kdykoli (tlačítko zpět = pauza s volbou Pokračovat / Vzdát)
- před první hrou nejvýš 3 karty návodu (`<id>Rules1..3` v `i18n/`)
- konec: obrazovka výsledku (hvězdy, skóre, Znovu, Zpět)
- texty jen z `i18n/`, čísla jen z `content/tuning.yaml` (`minigames.<id>`), barvy z `design/tokens.json`

## Galerie

Ladicí seznam všech miniher z katalogu, spustitelných bez jízdy (9.2), s volbou obtížnosti 1–5 a
seedu. F: tlačítko v ladicím panelu. W: `?gallery`; přímo hra `?mg=<id>&seed=<n>&level=<1–5>`
(DUALSTACK 6.6; cesta `/gallery` na GitHub Pages bez serveru nejde, proto parametr).
Hry, které klient ještě nemá, jsou v Galerii zašedlé.
