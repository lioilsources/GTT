# Specifikace modulů

Každý modul s chováním má `specs/<modul>.md` (minihry `specs/minigames/<id>.md`) s touto osnovou:

1. **Účel** – co modul dělá, pro koho.
2. **Stav** – datová struktura, jen celá čísla, řetězce, booleany, pole a objekty.
3. **Akce** – co může hráč nebo AI udělat.
4. **Pravidla** – `init`, `legalActions`, `apply`, `result` (tvar z DUALSTACK 5.4).
5. **AI** – úrovně, rozpočet v hloubce nebo iteracích (nikdy v čase).
6. **Hvězdy** – mapování výsledku na 0–3 hvězdy.
7. **Hraniční případy**.
8. **`version`** – celé číslo; změna chování = vyšší verze = nové vektory.

Kód bez specifikace se do žádného klienta nepíše. Vektory P0 jsou ve `vectors/<modul>.json`,
scénáře P1 ve `scenarios/<modul>/`.
