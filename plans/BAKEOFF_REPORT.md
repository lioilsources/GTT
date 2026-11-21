# BAKEOFF_REPORT – D1, souboj M0

Podklad pro bránu G1 (`Prompts/01-METROPOLE_DUALSTACK_PLAN.md`, kap. 10). Rozhoduje Ol1n.
Stav: **šablona, čeká na měření na telefonech.**

## Jak měřit
1. Obě verze z `main`: aplikace F jako `--profile` (Pixel 8a, iPhone 12 mini), web W na
   https://lioilsources.github.io/GTT/ v Chromu (Android) a Safari (iOS).
2. Benchmark (`specs/bench.md`): W `?bench`, F ladicí panel → Benchmark. Každá kombinace 3×,
   výsledek tlačítkem Kopírovat vložit níž do sekce Surová data.
3. Start: zavřít appku / kartu, změřit čas do prvního hratelného snímku na Wi-Fi a na mobilních
   datech (W ukazuje `first_frame_ms`, F také).
4. 10 minut jízdy: paměť (výsledek benchmarku po opakovaných jízdách), teplota rukou (studený / teplý /
   horký) a úbytek baterie v %.
5. Týden ježdění: dojem z ovládání, které schéma, rozdíly v pocitu z jízdy mezi F a W.

## Výsledky

| Telefon | Klient | fps průměr | fps 1 % | p99 ms | start Wi-Fi | start data | paměť MB | baterie 10 min | teplota |
|---|---|---|---|---|---|---|---|---|---|
| Pixel 8a | F (app) | | | | | | | | |
| Pixel 8a | W (Chrome) | | | | | | | | |
| iPhone 12 mini | F (app) | | | | | | | | |
| iPhone 12 mini | W (Safari) | | | | | | | | |

Rozpočty (DUALSTACK 6.3): 60 fps, ≤ 150 draw calls, ≤ 300 tis. trojúhelníků, první snímek do 5 MB,
halda JS ≤ 300 MB.

## Dojem z ovládání (Ol1n, po týdnu)


## Shrnutí pro G1

| Výsledek | Co následuje |
|---|---|
| Oba klienti drží 60 fps a hrají se stejně | oba stacky podle plánu (default) |
| W drží, F ne | jeden stack W + obal pro story |
| F drží, W na telefonech ne | jeden stack F; W zůstane jako ukázka M0 pro desktop |

Rozhodnutí: _

## Surová data
<!-- JSON z tlačítka Kopírovat, jeden blok na běh -->
