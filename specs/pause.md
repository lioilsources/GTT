# Pauza hry pod překryvy

**version: 1** · P2 (kdy se hra zastaví, oba klienti) · dogfooding Ol1na 2026-11-22 · parita F-034

## Účel

Když hráč čte nebo kliká v čemkoli, co zakrývá silnici nebo čeká na klepnutí, auto ani svět se
nesmí hýbat dál „naslepo“. Hra se zastaví úplně a po zavření pokračuje přesně tam, kde byla.

## Co hru zastaví

Hra je pozastavená, dokud je otevřený aspoň jeden z těchto překryvů:

| Překryv | Odkud |
|---|---|
| telefon (všechny aplikace) | `specs/phone.md` v3 |
| garáž | `specs/cars.md` |
| Pas a obrazovka O mapách | `specs/passport.md` |
| pohlednice objevené památky | `specs/passport.md` (dokud se nezavře nebo nevyprší `passport.postcard_s`) |
| dialog s NPC | `specs/dialogue.md` |
| karta příjezdu na spot, minihra, výsledková obrazovka | `specs/loop.md` |
| Galerie miniher | `specs/minigames/README.md` |
| ladicí panel | `docs/m0.md` |
| výsledek benchmarku | `specs/bench.md` |

Krátká upozornění, která nečekají na klepnutí (hotovost, pokuta, hledanost, navigační pokyn),
hru nezastaví.

## Co pauza znamená

- Pevný krok simulace se neprovádí: jízda (`specs/drive.md`), provoz a semafory
  (`specs/traffic.md`), tramvaje (`specs/trams.md`), chodci, policie a její časovače, taxi
  (čas směny), zaparkovaná auta, streaming chunků smí doběhnout.
- Hodiny hry (čas semaforů, časovače feedu, hledanosti) stojí; po zavření pokračují ze stejné
  hodnoty, nedohánějí uplynulý čas.
- Vstup řízení se zahazuje; po zavření překryvu začíná řízení z nulového vstupu (puštěný plyn,
  žádná brzda), aby auto neodjelo s „přilepeným“ prstem.
- Kreslení běží dál (svět stojí, překryv se animuje). Hudba a zvuky se ztlumí (až budou).
- Telefon už jízdu jen nezpomaluje (`phone.time_scale` se nepoužívá), zastaví ji.

## Implementace

Čistá funkce `paused(overlays) → bool` nad množinou otevřených překryvů (každý klient má jeden
registr, do kterého se překryv při otevření přihlásí a při zavření odhlásí). Herní smyčka v kroku
`dt` použije `paused ? 0 : dt`.

## Testy

Oba klienti: otevření telefonu / garáže / pohlednice zastaví auto i provoz (poloha po N krocích
stejná), po zavření se pokračuje; krátká upozornění pauzu nespustí.
